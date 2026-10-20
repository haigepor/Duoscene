import { createPool } from 'mysql2/promise';
import type { Pool, PoolConnection, ResultSetHeader, RowDataPacket } from 'mysql2/promise';
import type { DatabaseConfig } from '../config/env.ts';

type Value = string | number | boolean | Date | Buffer | null;

export class SqlSession {
  readonly connection: Pool | PoolConnection;
  constructor(connection: Pool | PoolConnection) { this.connection = connection; }
  async rows<T extends RowDataPacket>(sql: string, values: Value[] = []): Promise<T[]> {
    const [rows] = await this.connection.execute<T[]>(sql, values);
    return rows;
  }
  async run(sql: string, values: Value[] = []): Promise<ResultSetHeader> {
    const [result] = await this.connection.execute<ResultSetHeader>(sql, values);
    return result;
  }
}

export class Database extends SqlSession {
  readonly pool: Pool;
  constructor(config: Extract<DatabaseConfig, { mode: 'mysql' }>) {
    const pool = createPool({
      host: config.host, port: config.port, database: config.database,
      user: config.user, password: config.password,
      connectionLimit: 4, waitForConnections: true, queueLimit: 16,
      connectTimeout: 2000, timezone: 'Z', charset: 'utf8mb4',
      multipleStatements: false,
    });
    super(pool);
    this.pool = pool;
  }
  async transaction<T>(work: (sql: SqlSession) => Promise<T>): Promise<T> {
    const connection = await this.pool.getConnection();
    try {
      await connection.beginTransaction();
      const result = await work(new SqlSession(connection));
      await connection.commit();
      return result;
    } catch (error) {
      try { await connection.rollback(); } catch { connection.destroy(); }
      throw error;
    } finally {
      connection.release();
    }
  }
  async close() { await this.pool.end(); }
}
