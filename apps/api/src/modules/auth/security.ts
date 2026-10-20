import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { ApiError } from '../../shared/errors.ts';

const parameters = { N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024 };
let activeHashes = 0;

async function derive(password: string, salt: Buffer): Promise<Buffer> {
  // scrypt 使用工作线程；限制并行度，防止登录洪泛耗尽单机内存。
  if (activeHashes >= 2) throw new ApiError(429, 'AUTH_BUSY', 'Authentication is busy; retry later');
  activeHashes++;
  try {
    return await new Promise<Buffer>((resolve, reject) => {
      scrypt(password, salt, 64, parameters, (error, key) => error ? reject(error) : resolve(key));
    });
  } finally { activeHashes--; }
}

export function normalizeUsername(value: string): string {
  if (!/^[A-Za-z0-9_]{3,32}$/.test(value)) {
    throw new ApiError(422, 'INVALID_USERNAME', 'Username must contain 3-32 ASCII letters, digits or underscores');
  }
  return value.toLowerCase();
}

export async function hashPassword(password: string): Promise<string> {
  if (password.length < 12 || password.length > 128) {
    throw new ApiError(422, 'INVALID_PASSWORD', 'Password must contain 12-128 characters');
  }
  const salt = randomBytes(16);
  const key = await derive(password, salt);
  return `scrypt$131072$8$1$${salt.toString('hex')}$${key.toString('hex')}`;
}

export async function verifyPassword(password: string, encoded: string): Promise<boolean> {
  const parts = encoded.split('$');
  if (parts.length !== 6 || parts.slice(0, 4).join('$') !== 'scrypt$131072$8$1' ||
      !/^[a-f0-9]{32}$/.test(parts[4] ?? '') || !/^[a-f0-9]{128}$/.test(parts[5] ?? '')) return false;
  const actual = await derive(password, Buffer.from(parts[4]!, 'hex'));
  return timingSafeEqual(actual, Buffer.from(parts[5]!, 'hex'));
}

export function createToken(): string { return randomBytes(32).toString('base64url'); }
export function hashToken(token: string): string { return createHash('sha256').update(token).digest('hex'); }

// 用固定非秘密材料消耗与真实密码相同的工作量，避免未知账户快速返回。
export const dummyPasswordHash = `scrypt$131072$8$1$${'00'.repeat(16)}$${'00'.repeat(64)}`;
