import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import type { RowDataPacket } from 'mysql2/promise';
import type { Database } from '../shared/database.ts';

import { listMigrationNames, migrationDirectory } from '../shared/migrations.ts';
export { migrationDirectory } from '../shared/migrations.ts';

export async function migrate(db: Database) {
  const connection = await db.pool.getConnection();
  let locked = false;
  try {
    const [locks] = await connection.query<(RowDataPacket & { acquired: number })[]>(
      "SELECT GET_LOCK(CONCAT(DATABASE(), ':migrations'), 5) AS acquired",
    );
    if (locks[0]?.acquired !== 1) throw new Error('MIGRATION_LOCK_UNAVAILABLE');
    locked = true;
    await connection.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      name VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
      checksum CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
      state ENUM('APPLYING', 'APPLIED', 'FAILED') NOT NULL,
      applied_at DATETIME(3) NULL
    ) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci`);
    const names = await listMigrationNames();
    const applied: string[] = [];
    for (const name of names) {
      const sql = await readFile(new URL(name, migrationDirectory), 'utf8');
      const checksum = createHash('sha256').update(sql).digest('hex');
      const [rows] = await connection.execute<(RowDataPacket & { checksum: string; state: string })[]>(
        'SELECT checksum, state FROM schema_migrations WHERE name = ?', [name],
      );
      if (rows[0]) {
        if (rows[0].checksum !== checksum || rows[0].state !== 'APPLIED') throw new Error(`MIGRATION_REQUIRES_REVIEW: ${name}`);
        continue;
      }
      await connection.execute("INSERT INTO schema_migrations (name, checksum, state) VALUES (?, ?, 'APPLYING')", [name, checksum]);
      try {
        // 每个文件恰好一个 DDL，保持 multipleStatements=false；不承诺 MySQL DDL 事务回滚。
        await connection.query(sql);
        await connection.execute("UPDATE schema_migrations SET state = 'APPLIED', applied_at = UTC_TIMESTAMP(3) WHERE name = ?", [name]);
        applied.push(name);
      } catch (error) {
        await connection.execute("UPDATE schema_migrations SET state = 'FAILED' WHERE name = ?", [name]);
        throw error;
      }
    }
    return applied;
  } finally {
    try {
      if (locked) await connection.query("SELECT RELEASE_LOCK(CONCAT(DATABASE(), ':migrations'))");
    } finally { connection.release(); }
  }
}
