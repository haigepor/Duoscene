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
      // 12 个连接覆盖 realtime 心跳 + 消息校验 + checkpoint + REST 的并发峰值；
      // 队列等 250 个请求，超出的由 app.ts 错误处理映射为 503。
      connectionLimit: 12, waitForConnections: true, queueLimit: 250,
      maxIdle: 6, idleTimeout: 60_000,
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
