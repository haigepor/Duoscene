import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadConfig } from '../src/config/env.ts';

test('scaffold defaults bind locally and do not pretend to configure MySQL', () => {
  const config = loadConfig({});
  assert.equal(config.host, '127.0.0.1');
  assert.equal(config.port, 3000);
  assert.deepEqual(config.database, { mode: 'disabled' });
});

test('invalid ports, database modes and production without MySQL fail closed', () => {
  for (const API_PORT of ['0', '-1', '65536', '30x', '', '3.5']) {
    assert.throws(() => loadConfig({ API_PORT }));
  }
  assert.throws(() => loadConfig({ DATABASE_MODE: 'sqlite' }));
  assert.throws(() => loadConfig({ NODE_ENV: 'production' }));
  assert.throws(() => loadConfig({ DATABASE_MODE: 'mysql' }), /MYSQL_HOST/);
});

test('MySQL requires an explicit password without echoing its value', () => {
  const env = {
    DATABASE_MODE: 'mysql', MYSQL_HOST: 'localhost', MYSQL_DATABASE: 'duoscene',
    MYSQL_USER: 'duoscene', MYSQL_PASSWORD: ' ',
  };
  assert.throws(() => loadConfig(env), /MYSQL_PASSWORD is required/);
  assert.equal(loadConfig({ ...env, MYSQL_PASSWORD: 'test-only-not-a-real-secret' }).database.mode, 'mysql');
});
