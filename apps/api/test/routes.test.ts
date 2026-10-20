import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config/env.ts';
import type { AuthService } from '../src/modules/auth/service.ts';
import type { RoomService } from '../src/modules/rooms/service.ts';
import { ApiError } from '../src/shared/errors.ts';

const id = '11111111-1111-4111-8111-111111111111';
const token = 'A'.repeat(43);
const identity = { id, username: 'fixture_user', displayName: '测试用户', sessionId: id };

// 此处替身只验证 HTTP 边界，数据库事务由独立真实 MySQL 套件验证。
function services(): { auth: AuthService; rooms: RoomService } {
  const noCall = async (): Promise<never> => { throw new Error('Unexpected service call'); };
  return {
    auth: {
      register: noCall, recover: noCall,
      login: async () => ({ accessToken: token, refreshToken: 'B'.repeat(43), tokenType: 'Bearer', expiresIn: 900, user: identity }),
      authenticate: async (value) => { if (value !== token) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required'); return identity; },
      refresh: noCall, logout: async () => {},
    },
    rooms: { create: noCall, get: noCall, list: async () => ({ items: [], nextCursor: null }), invite: noCall,
      join: noCall, revokeInvite: noCall, close: noCall, leave: noCall, remove: noCall },
  };
}

test('protected routes reject unauthenticated calls before exposing resource or validation details', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false, services: services() });
  t.after(() => app.close());
  for (const url of ['/api/v1/auth/me', '/api/v1/rooms', '/api/v1/rooms/not-a-uuid']) {
    const result = await app.inject(url);
    assert.equal(result.statusCode, 401);
    assert.equal(result.json().error.code, 'UNAUTHORIZED');
  }
});

test('public registration and recovery validate input and limit each route to five attempts', async (t) => {
  const supplied = services();
  let calls = 0;
  supplied.auth.register = async () => { calls++; return {user: {...identity, id}, recoveryCode: token}; };
  supplied.auth.recover = async () => { calls++; return {recoveryCode: token}; };
  const app = buildApp({config: loadConfig({}), logger: false, services: supplied});
  t.after(() => app.close());
  for (const route of ['register', 'recover']) {
    const payload = route === 'register'
      ? {username: 'new_user', displayName: '新用户', password: 'long-enough-password'}
      : {username: 'new_user', recoveryCode: token, password: 'long-enough-password'};
    const url = `/api/v1/auth/${route}`;
    const invalid = await app.inject({method: 'POST', url, payload: {...payload, role: 'admin'}});
    assert.equal(invalid.statusCode, 422);
    const before = calls;
    for (let i = 0; i < 4; i++) {
      const result = await app.inject({method: 'POST', url, payload});
      assert.equal(result.statusCode, route === 'register' ? 201 : 200);
      assert.equal(result.headers['cache-control'], 'no-store');
      assert.equal(result.json().data.user?.sessionId, undefined);
    }
    assert.equal(calls, before + 4);
    const limited = await app.inject({method: 'POST', url, payload});
    assert.equal(limited.statusCode, 429);
    assert.equal(limited.json().error.code, 'RATE_LIMITED');
    assert.equal(calls, before + 4);
  }
});

test('JSON Schema rejects extra fields, whitespace names, invalid pagination and wrong token types', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false, services: services() });
  t.after(() => app.close());
  const headers = { authorization: `Bearer ${token}` };
  for (const payload of [{ name: 'valid', ownerUserId: id }, { name: '  ' }, { name: 123 }]) {
    const result = await app.inject({ method: 'POST', url: '/api/v1/rooms', headers, payload });
    assert.equal(result.statusCode, 422);
    assert.equal(result.json().error.code, 'VALIDATION_ERROR');
  }
  assert.equal((await app.inject({ url: '/api/v1/rooms?limit=999', headers })).statusCode, 422);
  assert.equal((await app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: 123 } })).statusCode, 422);
});

test('responses serialize only public fields and use no-store and safe headers', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false, services: services() });
  t.after(() => app.close());
  const result = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: {
    username: 'fixture_user', password: 'fixture-password', deviceLabel: 'test',
  } });
  assert.equal(result.statusCode, 200);
  assert.equal(result.json().data.user.sessionId, undefined);
  assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.headers['x-content-type-options'], 'nosniff');
  assert.equal((await app.inject({ url: '/api/v1/rooms', headers: { authorization: `Bearer ${token}` } })).statusCode, 200);
});

test('authentication attempts are rate limited with the standard error envelope', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false, services: services() });
  t.after(() => app.close());
  for (let count = 0; count < 10; count++) {
    assert.equal((await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: {
      username: 'fixture_user', password: 'fixture-password', deviceLabel: 'test',
    } })).statusCode, 200);
  }
  const limited = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: {
    username: 'fixture_user', password: 'fixture-password', deviceLabel: 'test',
  } });
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.json().error.code, 'RATE_LIMITED');
});

test('unconfigured database fails business requests closed', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false });
  t.after(() => app.close());
  const result = await app.inject('/api/v1/rooms');
  assert.equal(result.statusCode, 503);
  assert.equal(result.json().error.code, 'DATABASE_NOT_CONFIGURED');
});
