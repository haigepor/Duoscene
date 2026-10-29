import { randomUUID, timingSafeEqual } from 'node:crypto';
import type { RowDataPacket } from 'mysql2/promise';
import type { Database } from '../../shared/database.ts';
import { ApiError } from '../../shared/errors.ts';
import { authRepository, publicUser } from './repository.ts';
import { createToken, dummyPasswordHash, hashToken, hashPassword, normalizeUsername, verifyPassword } from './security.ts';

export interface Identity { id: string; username: string; displayName: string; sessionId: string }
export interface LoginInput { username: string; password: string; deviceLabel: string }
const unauthorized = () => new ApiError(401, 'UNAUTHORIZED', 'Authentication required');

/** WS 在握手时验证 access，后续按会话撤销/过期/账号状态校验，允许正常 REST 凭据轮换。 */
export async function validateConnection(db: Database, identity: Identity) {
  // 会话撤销/过期在 WS 消息与心跳里逐条查库，房间热时每秒可达几十次；
  // 用 3s TTL 缓存把频率压到最多 1 次/秒/会话，撤销最迟 3s 生效。
  const cached = connectionCache.get(identity.sessionId);
  const now = Date.now();
  if (cached && cached.expires > now) {
    if (!cached.ok) throw unauthorized();
    return;
  }
  const ok = !!(await authRepository(db).activeConnection(identity.sessionId, identity.id));
  connectionCache.set(identity.sessionId, { ok, expires: now + 3000 });
  if (connectionCache.size > 4096) pruneConnectionCache();
  if (!ok) throw unauthorized();
}

const connectionCache = new Map<string, { ok: boolean; expires: number }>();
function pruneConnectionCache() {
  const now = Date.now();
  for (const [key, value] of connectionCache) if (value.expires <= now) connectionCache.delete(key);
}

export function createAuthService(db: Database) {
  const repo = authRepository(db);
  function credentials() {
    return { accessToken: createToken(), refreshToken: createToken() };
  }
  return {
    async register(input: { username: string; displayName: string; password: string }) {
      const username = normalizeUsername(input.username);
      const displayName = input.displayName.trim();
      if (!displayName || displayName.length > 80) throw new ApiError(422, 'INVALID_DISPLAY_NAME', 'Invalid display name');
      const passwordHash = await hashPassword(input.password);
      const recoveryCode = createToken(), id = randomUUID();
      try {
        await db.run(
          'INSERT INTO users (id, username, display_name, password_hash, recovery_token_hash) VALUES (?, ?, ?, ?, ?)',
          [id, username, displayName, passwordHash, hashToken(recoveryCode)],
        );
      } catch (error) {
        if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'ER_DUP_ENTRY') {
          throw new ApiError(409, 'USERNAME_UNAVAILABLE', 'Username unavailable');
        }
        throw error;
      }
      // 原码仅在成功响应中返回，不写日志，不创建未被客户端接收的登录会话。
      return { user: { id, username, displayName }, recoveryCode };
    },
    async recover(input: { username: string; recoveryCode: string; password: string }) {
      const username = normalizeUsername(input.username);
      const passwordHash = await hashPassword(input.password);
      const recoveryCode = createToken();
      await db.transaction(async sql => {
        // 与登录/刷新一致，先锁账户再撤销会话；并发消费同一个恢复码只有一次成功。
        const users = await sql.rows<RowDataPacket & { id: string; status: string; recoveryHash: string | null }>(
          'SELECT id, status, recovery_token_hash AS recoveryHash FROM users WHERE username=? FOR UPDATE', [username],
        );
        const user = users[0];
        const expected = Buffer.from(user?.recoveryHash ?? '0'.repeat(64), 'hex');
        const valid = timingSafeEqual(expected, Buffer.from(hashToken(input.recoveryCode), 'hex'));
        if (!user || user.status !== 'ACTIVE' || !user.recoveryHash || !valid) {
          throw new ApiError(401, 'RECOVERY_INVALID', 'Account or recovery code invalid');
        }
        await sql.run('UPDATE users SET password_hash=?, recovery_token_hash=?, updated_at=UTC_TIMESTAMP(3) WHERE id=?',
          [passwordHash, hashToken(recoveryCode), user.id]);
        await sql.run('UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at, UTC_TIMESTAMP(3)) WHERE user_id=?', [user.id]);
      });
      return { recoveryCode };
    },
    async login(input: LoginInput) {
      const username = normalizeUsername(input.username);
      const user = await repo.userByName(username);
      const valid = await verifyPassword(input.password, user?.passwordHash ?? dummyPasswordHash);
      if (!user || !valid || user.status !== 'ACTIVE') throw unauthorized();
      const tokens = credentials();
      const id = randomUUID();
      await db.transaction(async (sql) => {
        const tx = authRepository(sql);
        const current = await tx.userById(user.id, true);
        if (!current || current.status !== 'ACTIVE' || current.passwordHash !== user.passwordHash) throw unauthorized();
        await tx.insertSession(id, user.id, hashToken(tokens.accessToken), hashToken(tokens.refreshToken), input.deviceLabel);
      });
      return { ...tokens, tokenType: 'Bearer' as const, expiresIn: 900, user: publicUser(user) };
    },
    async authenticate(accessToken: string): Promise<Identity> {
      if (!/^[A-Za-z0-9_-]{43}$/.test(accessToken)) throw unauthorized();
      const user = await repo.access(hashToken(accessToken));
      if (!user) throw unauthorized();
      return { ...publicUser(user), sessionId: user.sessionId };
    },
    async refresh(token: string) {
      const hash = hashToken(token);
      const existingToken = await repo.refreshToken(hash);
      if (!existingToken) throw unauthorized();
      const existingSession = await repo.session(existingToken.sessionId);
      if (!existingSession) throw unauthorized();
      const tokens = credentials();
      const outcome = await db.transaction(async (sql) => {
        const tx = authRepository(sql);
        // 固定顺序：先用户共享锁，再会话排他锁，最后刷新 token 行锁。
        const user = await tx.userById(existingSession.userId, true);
        const session = await tx.session(existingSession.id, true);
        if (!user || user.status !== 'ACTIVE' || !session || session.revokedAt || session.expiresAt.getTime() <= Date.now()) {
          throw unauthorized();
        }
        const stored = await tx.refreshToken(hash, true);
        if (!stored || stored.consumedAt || session.refreshHash !== hash) {
          // 返回结果后再抛错，让撤销能够提交，不被异常路径 rollback 撤销。
          await tx.revoke(session.id);
          return { replay: true as const };
        }
        await tx.rotate(session.id, hash, hashToken(tokens.refreshToken), hashToken(tokens.accessToken));
        return { replay: false as const, user: publicUser(user) };
      });
      if (outcome.replay) throw new ApiError(401, 'TOKEN_REPLAY', 'Session revoked; sign in again');
      return { ...tokens, tokenType: 'Bearer' as const, expiresIn: 900, user: outcome.user };
    },
    async logout(identity: Identity) { await repo.revoke(identity.sessionId); },
  };
}

export type AuthService = ReturnType<typeof createAuthService>;
