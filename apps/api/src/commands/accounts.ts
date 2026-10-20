import { randomUUID } from 'node:crypto';
import type { Database } from '../shared/database.ts';
import { ApiError } from '../shared/errors.ts';
import { hashPassword, normalizeUsername } from '../modules/auth/security.ts';

export async function createPrivateUser(db: Database, username: string, displayName: string, password: string) {
  const normalized = normalizeUsername(username);
  if (displayName.trim().length < 1 || displayName.length > 80) throw new ApiError(422, 'INVALID_DISPLAY_NAME', 'Display name must contain 1-80 characters');
  const passwordHash = await hashPassword(password);
  const id = randomUUID();
  await db.run('INSERT INTO users (id, username, display_name, password_hash) VALUES (?, ?, ?, ?)', [id, normalized, displayName.trim(), passwordHash]);
  return { id, username: normalized, displayName: displayName.trim() };
}

export async function disablePrivateUser(db: Database, username: string) {
  await db.transaction(async (sql) => {
    const result = await sql.run("UPDATE users SET status = 'DISABLED', updated_at = UTC_TIMESTAMP(3) WHERE username = ?", [normalizeUsername(username)]);
    if (!result.affectedRows) throw new ApiError(404, 'USER_NOT_FOUND', 'User not found');
    await sql.run(`UPDATE auth_sessions s JOIN users u ON u.id = s.user_id
      SET s.revoked_at = COALESCE(s.revoked_at, UTC_TIMESTAMP(3)) WHERE u.username = ?`, [normalizeUsername(username)]);
  });
}
