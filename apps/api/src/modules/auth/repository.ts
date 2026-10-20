import type { RowDataPacket } from 'mysql2/promise';
import type { SqlSession } from '../../shared/database.ts';

export interface UserRow extends RowDataPacket {
  id: string; username: string; displayName: string; passwordHash: string;
  status: 'ACTIVE' | 'DISABLED';
}
export interface SessionRow extends RowDataPacket {
  id: string; userId: string; refreshHash: string; expiresAt: Date;
  revokedAt: Date | null; accessExpiresAt: Date;
}
export interface RefreshRow extends RowDataPacket {
  sessionId: string; consumedAt: Date | null;
}

const userColumns = 'id, username, display_name AS displayName, password_hash AS passwordHash, status';

export function authRepository(sql: SqlSession) {
  return {
    async activeConnection(sessionId: string, userId: string) {
      return (await sql.rows<RowDataPacket>(
        `SELECT s.id FROM auth_sessions s JOIN users u ON u.id=s.user_id
         WHERE s.id=? AND s.user_id=? AND s.revoked_at IS NULL
         AND s.expires_at > UTC_TIMESTAMP(3) AND u.status='ACTIVE'`, [sessionId, userId],
      )).length === 1;
    },
    async userByName(username: string) {
      return (await sql.rows<UserRow>(`SELECT ${userColumns} FROM users WHERE username = ?`, [username]))[0];
    },
    async userById(id: string, lock = false) {
      return (await sql.rows<UserRow>(`SELECT ${userColumns} FROM users WHERE id = ?${lock ? ' FOR SHARE' : ''}`, [id]))[0];
    },
    async access(tokenHash: string) {
      return (await sql.rows<UserRow & { sessionId: string }>(
        `SELECT u.id, u.username, u.display_name AS displayName, s.id AS sessionId
         FROM auth_sessions s JOIN users u ON u.id = s.user_id
         WHERE s.access_token_hash = ? AND s.revoked_at IS NULL AND u.status = 'ACTIVE'
         AND s.access_expires_at > UTC_TIMESTAMP(3) AND s.expires_at > UTC_TIMESTAMP(3)`, [tokenHash],
      ))[0];
    },
    async insertSession(id: string, userId: string, accessHash: string, refreshHash: string, label: string) {
      await sql.run(
        `INSERT INTO auth_sessions
          (id, user_id, access_token_hash, refresh_token_hash, device_label, access_expires_at, expires_at)
         VALUES (?, ?, ?, ?, ?, TIMESTAMPADD(MINUTE, 15, UTC_TIMESTAMP(3)), TIMESTAMPADD(DAY, 30, UTC_TIMESTAMP(3)))`,
        [id, userId, accessHash, refreshHash, label],
      );
      await sql.run('INSERT INTO auth_refresh_tokens (token_hash, session_id) VALUES (?, ?)', [refreshHash, id]);
    },
    async session(id: string, lock = false) {
      return (await sql.rows<SessionRow>(
        `SELECT id, user_id AS userId, refresh_token_hash AS refreshHash, expires_at AS expiresAt,
         revoked_at AS revokedAt, access_expires_at AS accessExpiresAt
         FROM auth_sessions WHERE id = ?${lock ? ' FOR UPDATE' : ''}`, [id],
      ))[0];
    },
    async refreshToken(hash: string, lock = false) {
      return (await sql.rows<RefreshRow>(
        `SELECT session_id AS sessionId, consumed_at AS consumedAt FROM auth_refresh_tokens
         WHERE token_hash = ?${lock ? ' FOR UPDATE' : ''}`, [hash],
      ))[0];
    },
    async rotate(id: string, oldHash: string, refreshHash: string, accessHash: string) {
      await sql.run('UPDATE auth_refresh_tokens SET consumed_at = UTC_TIMESTAMP(3) WHERE token_hash = ?', [oldHash]);
      await sql.run('INSERT INTO auth_refresh_tokens (token_hash, session_id) VALUES (?, ?)', [refreshHash, id]);
      await sql.run(
        `UPDATE auth_sessions SET refresh_token_hash = ?, access_token_hash = ?,
         access_expires_at = TIMESTAMPADD(MINUTE, 15, UTC_TIMESTAMP(3)), last_used_at = UTC_TIMESTAMP(3)
         WHERE id = ?`, [refreshHash, accessHash, id],
      );
    },
    async revoke(id: string) {
      await sql.run('UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, UTC_TIMESTAMP(3)) WHERE id = ?', [id]);
    },
  };
}

export function publicUser(user: Pick<UserRow, 'id' | 'username' | 'displayName'>) {
  return { id: user.id, username: user.username, displayName: user.displayName };
}
