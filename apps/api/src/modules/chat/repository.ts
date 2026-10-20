import type { RowDataPacket } from 'mysql2/promise';
import type { Database } from '../../shared/database.ts';

export type Message = RowDataPacket & { id: string; userId: string; clientMessageId: string; text: string; displayName: string; createdAt: Date };
const select = 'SELECT CAST(m.id AS CHAR) AS id, m.user_id AS userId, m.client_message_id AS clientMessageId, m.body AS text, u.display_name AS displayName, m.created_at AS createdAt FROM chat_messages m JOIN users u ON u.id=m.user_id';
export function chatRepository(db: Database) {
  return {
    async history(roomId: string, before = '18446744073709551615') { return (await db.rows<Message>(`${select} WHERE m.room_id=? AND m.id < ? ORDER BY m.id DESC LIMIT 50`, [roomId, before])).reverse(); },
    async send(roomId: string, userId: string, clientMessageId: string, text: string) {
      await db.run('INSERT INTO chat_messages (room_id,user_id,client_message_id,body) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE id=id', [roomId, userId, clientMessageId, text]);
      return (await db.rows<Message>(`${select} WHERE m.room_id=? AND m.user_id=? AND m.client_message_id=?`, [roomId, userId, clientMessageId]))[0]!;
    },
  };
}
