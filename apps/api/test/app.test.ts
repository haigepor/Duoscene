import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config/env.ts';
import { readdir } from 'node:fs/promises';
import { attachDatabase, migrationNames } from '../src/plugins/database.ts';
import Fastify from 'fastify';

test('readiness requires every migration shipped with the application', async () => {
  const files = (await readdir(new URL('../migrations/', import.meta.url)))
    .filter(name => /^\d{4}_[a-z_]+\.sql$/.test(name)).sort();
  assert.deepEqual(migrationNames, files);
});

test('a reachable database missing account recovery stays unready until the migration is applied', async (t) => {
  const app = Fastify({ logger: false });
  const attached = attachDatabase(app, { mode: 'mysql', host: '127.0.0.1', port: 1, database: 'unused', user: 'unused', password: 'unused' });
  t.after(async () => { await app.close(); });
  const rows = migrationNames.filter(name => name !== '0009_account_recovery.sql').map(name => ({ name, state: 'APPLIED' }));
  // 仅替换连接池查询，不创建真实数据库连接；探针和迁移判定仍执行生产代码。
  t.mock.method(attached.database!.pool, 'query', async () => [rows]);
  assert.equal(await attached.probe(), 'unavailable');
  rows.push({ name: '0009_account_recovery.sql', state: 'APPLIED' });
  assert.equal(await attached.probe(), 'ready');
  rows[0]!.state = 'FAILED';
  assert.equal(await attached.probe(), 'unavailable');
});

test('liveness works while an unconfigured database fails readiness', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false });
  t.after(() => app.close());
  const live = await app.inject({ method: 'GET', url: '/health/live' });
  assert.equal(live.statusCode, 200);
  assert.equal(live.json().data.status, 'alive');
  assert.equal(typeof live.json().requestId, 'string');
  const ready = await app.inject({ method: 'GET', url: '/health/ready' });
  assert.equal(ready.statusCode, 503);
  assert.equal(ready.json().error.code, 'DATABASE_NOT_CONFIGURED');
});

test('readiness distinguishes a reachable database from an outage', async (t) => {
  let online = true;
  const app = buildApp({
    config: loadConfig({}), logger: false,
    probeDatabase: async () => online ? 'ready' : 'unavailable',
  });
  t.after(() => app.close());
  assert.equal((await app.inject('/health/ready')).statusCode, 200);
  online = false;
  const result = await app.inject('/health/ready');
  assert.equal(result.statusCode, 503);
  assert.equal(result.json().error.code, 'DATABASE_UNAVAILABLE');
});

test('unknown routes use the safe error envelope and reject caller request IDs', async (t) => {
  const app = buildApp({ config: loadConfig({}), logger: false });
  t.after(() => app.close());
  const result = await app.inject({
    method: 'GET', url: '/unknown?token=must-not-be-echoed',
    headers: { 'request-id': 'caller-controlled' },
  });
  assert.equal(result.statusCode, 404);
  assert.equal(result.json().error.code, 'NOT_FOUND');
  assert.notEqual(result.json().requestId, 'caller-controlled');
  assert.ok(!result.body.includes('must-not-be-echoed'));
});
