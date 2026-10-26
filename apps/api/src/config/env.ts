export type DatabaseConfig =
  | { mode: 'disabled' }
  | {
      mode: 'mysql';
      host: string;
      port: number;
      database: string;
      user: string;
      password: string;
    };

export interface AppConfig {
  environment: 'development' | 'test' | 'production';
  host: string;
  port: number;
  logLevel: 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
  database: DatabaseConfig;
  // 仅当部署在可信反向代理之后才开启：信任 X-Forwarded-For 决定限流键，
  // 直连部署开启它会让客户端伪造头绕过限流。
  trustProxy: boolean;
  voice?: { urls: string[]; secret: string; relayOnly: boolean };
}

function port(value: string | undefined, fallback: number, name: string): number {
  if (value === undefined) return fallback;
  if (!/^\d+$/.test(value)) throw new Error(`${name} must be an integer port`);
  const result = Number(value);
  if (!Number.isInteger(result) || result < 1 || result > 65535) {
    throw new Error(`${name} must be between 1 and 65535`);
  }
  return result;
}

function required(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name];
  if (value === undefined || value.trim() === '') {
    throw new Error(`${name} is required`);
  }
  return value;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const environment = env.NODE_ENV ?? 'development';
  if (environment !== 'development' && environment !== 'test' && environment !== 'production') {
    throw new Error('NODE_ENV must be development, test or production');
  }
  const logLevel = env.LOG_LEVEL ?? 'info';
  if (
    logLevel !== 'fatal' && logLevel !== 'error' && logLevel !== 'warn' &&
    logLevel !== 'info' && logLevel !== 'debug' && logLevel !== 'trace' && logLevel !== 'silent'
  ) throw new Error('LOG_LEVEL is invalid');

  const mode = env.DATABASE_MODE ?? 'disabled';
  if (mode !== 'disabled' && mode !== 'mysql') throw new Error('DATABASE_MODE is invalid');
  // 禁止生产环境通过关闭数据库伪装成可用服务。
  if (environment === 'production' && mode === 'disabled') {
    throw new Error('Production requires DATABASE_MODE=mysql');
  }
  const database: DatabaseConfig = mode === 'disabled' ? { mode } : {
    mode,
    host: required(env, 'MYSQL_HOST'),
    port: port(env.MYSQL_PORT, 3306, 'MYSQL_PORT'),
    database: required(env, 'MYSQL_DATABASE'),
    user: required(env, 'MYSQL_USER'),
    password: required(env, 'MYSQL_PASSWORD'),
  };
  if (env.TURN_URLS && (required(env, 'TURN_SECRET').length < 32 || !env.TURN_URLS.split(',').every(v => /^turns?:[^\s,]+$/.test(v.trim())))) {
    throw new Error('TURN configuration requires valid TURN URLs and a strong secret');
  }
  return {
    environment,
    host: env.API_HOST?.trim() || '127.0.0.1',
    port: port(env.API_PORT, 3000, 'API_PORT'),
    logLevel,
    database,
    trustProxy: env.API_TRUST_PROXY === 'true',
    ...(env.TURN_URLS ? { voice: { urls: env.TURN_URLS.split(',').map(v => v.trim()), secret: required(env, 'TURN_SECRET'), relayOnly: env.TURN_RELAY_ONLY === 'true' } } : {}),
  };
}
