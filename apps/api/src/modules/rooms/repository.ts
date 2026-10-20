import type { RowDataPacket } from 'mysql2/promise';
import type { SqlSession } from '../../shared/database.ts';

export interface RoomRow extends RowDataPacket {
  id: string; name: string; ownerUserId: string; status: 'OPEN' | 'CLOSED';
  controlMode: 'BOTH' | 'OWNER_ONLY'; createdAt: Date;
}
export interface MemberRow extends RowDataPacket { userId: string; displayName: string; seatNo: number; joinedAt: Date }
export interface InviteRow extends RowDataPacket {
  id: string; roomId: string; expiresAt: Date; revokedAt: Date | null; maxUses: number; usedCount: number;
}
const roomColumns = 'r.id, r.name, r.owner_user_id AS ownerUserId, r.status, r.control_mode AS controlMode, r.created_at AS createdAt';

export function roomRepository(sql: SqlSession) {
  return {
    async room(id: string, lock = false) {
      return (await sql.rows<RoomRow>(`SELECT ${roomColumns} FROM rooms r WHERE r.id = ?${lock ? ' FOR UPDATE' : ''}`, [id]))[0];
    },
    async members(id: string) {
      return sql.rows<MemberRow>(
        `SELECT m.user_id AS userId, u.display_name AS displayName, m.seat_no AS seatNo, m.joined_at AS joinedAt
         FROM room_members m JOIN users u ON u.id = m.user_id WHERE m.room_id = ? ORDER BY m.seat_no`, [id],
      );
    },
    async list(userId: string, afterId: string, limit: number) {
      return sql.rows<RoomRow>(
        `SELECT ${roomColumns} FROM rooms r JOIN room_members m ON m.room_id = r.id
         WHERE m.user_id = ? AND r.id > ? ORDER BY r.id LIMIT ?`, [userId, afterId, limit],
      );
    },
    async insertRoom(id: string, userId: string, name: string) {
      await sql.run('INSERT INTO rooms (id, name, owner_user_id) VALUES (?, ?, ?)', [id, name, userId]);
      await sql.run('INSERT INTO room_members (room_id, user_id, seat_no) VALUES (?, ?, 1)', [id, userId]);
    },
    async insertInvite(id: string, roomId: string, tokenHash: string, userId: string) {
      await sql.run(
        `INSERT INTO room_invites (id, room_id, token_hash, created_by, expires_at)
         VALUES (?, ?, ?, ?, TIMESTAMPADD(MINUTE, 15, UTC_TIMESTAMP(3)))`, [id, roomId, tokenHash, userId],
      );
    },
    async inviteByHash(hash: string, lock = false) {
      return (await sql.rows<InviteRow>(
        `SELECT id, room_id AS roomId, expires_at AS expiresAt, revoked_at AS revokedAt,
         max_uses AS maxUses, used_count AS usedCount FROM room_invites WHERE token_hash = ?${lock ? ' FOR UPDATE' : ''}`, [hash],
      ))[0];
    },
    async addMember(roomId: string, userId: string, seat: number, inviteId: string) {
      await sql.run('INSERT INTO room_members (room_id, user_id, seat_no) VALUES (?, ?, ?)', [roomId, userId, seat]);
      await sql.run('UPDATE room_invites SET used_count = used_count + 1 WHERE id = ?', [inviteId]);
    },
    async revokeInvite(roomId: string, id: string) {
      const result = await sql.run('UPDATE room_invites SET revoked_at = COALESCE(revoked_at, UTC_TIMESTAMP(3)) WHERE id = ? AND room_id = ?', [id, roomId]);
      return result.affectedRows;
    },
    async close(roomId: string) {
      await sql.run("UPDATE rooms SET status = 'CLOSED', updated_at = UTC_TIMESTAMP(3) WHERE id = ?", [roomId]);
      await sql.run('UPDATE room_invites SET revoked_at = COALESCE(revoked_at, UTC_TIMESTAMP(3)) WHERE room_id = ?', [roomId]);
    },
    async remove(roomId: string, userId: string) {
      await sql.run('DELETE FROM room_members WHERE room_id = ? AND user_id = ?', [roomId, userId]);
    },
  };
}
