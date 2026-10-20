import type { FastifyInstance } from 'fastify';
import type { DatabaseConfig } from '../config/env.ts';
import { Database } from '../shared/database.ts';
import type { RowDataPacket } from 'mysql2/promise';

export type Readiness = 'ready' | 'disabled' | 'unavailable';
export type ProbeDatabase = () => Promise<Readiness>;

export const migrationNames = [
  '0001_users.sql', '0002_auth_sessions.sql', '0003_auth_refresh_tokens.sql',
  '0004_rooms.sql', '0005_room_members.sql', '0006_room_invites.sql',
  '0007_chat_messages.sql', '0008_room_playback.sql',
];

export function attachDatabase(app: FastifyInstance, config: DatabaseConfig) {
  if (config.mode === 'disabled') return { database: null, probe: async (): Promise<Readiness> => 'disabled' };
  const database = new Database(config);
  app.addHook('onClose', async () => { await database.close(); });
  const probe: ProbeDatabase = async () => {
    try {
      const [rows] = await database.pool.query<(RowDataPacket & { name: string; state: string })[]>({
        sql: 'SELECT name, state FROM schema_migrations ORDER BY name', timeout: 2000,
      });
      return rows.every((row) => row.state === 'APPLIED') &&
        migrationNames.every((name) => rows.some((row) => row.name === name)) ? 'ready' : 'unavailable';
    } catch { return 'unavailable'; }
  };
  return { database, probe };
}
