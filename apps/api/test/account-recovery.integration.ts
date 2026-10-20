import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import type { RowDataPacket } from 'mysql2/promise';
import { loadConfig } from '../src/config/env.ts';
import { Database } from '../src/shared/database.ts';
import { migrate } from '../src/commands/migrate.ts';
import { buildApp } from '../src/app.ts';
import { createAuthService, validateConnection } from '../src/modules/auth/service.ts';
import { hashToken } from '../src/modules/auth/security.ts';

test('registration and single-use recovery with session revocation on real MySQL', async t => {
  const base = loadConfig(), database = process.env.DUOSCENE_TEST_DATABASE;
  assert.ok(database && /^duoscene_test_[a-z0-9_]{1,40}$/.test(database));
  assert.equal(base.database.mode, 'mysql');
  const config = {...base, database: {...base.database, database}};
  const db = new Database(config.database), app = buildApp({config, logger: false});
  const ids: string[] = [];
  t.after(async () => {
    await app.close();
    for (const id of ids) await db.run('DELETE FROM users WHERE id=?', [id]);
    await db.close();
  });
  await migrate(db);
  const auth = createAuthService(db), username = `signup_${randomUUID().slice(0,8)}`;
  const password = 'initial-integration-password', changed = 'changed-integration-password';
  const registration = await app.inject({method: 'POST',url:'/api/v1/auth/register',
    payload:{username,displayName:'新用户',password}});
  assert.equal(registration.statusCode,201);
  const created = registration.json().data; ids.push(created.user.id);
  assert.match(created.recoveryCode,/^[A-Za-z0-9_-]{43}$/);
  assert.deepEqual(Object.keys(created).sort(),['recoveryCode','user']);
  const [stored] = await db.rows<RowDataPacket>('SELECT recovery_token_hash FROM users WHERE id=?',[created.user.id]);
  assert.equal(stored?.recovery_token_hash,hashToken(created.recoveryCode));
  assert.equal((await app.inject({method:'POST',url:'/api/v1/auth/register',
    payload:{username:username.toUpperCase(),displayName:'重复',password}})).statusCode,409);
  const invalid = await app.inject({method:'POST',url:'/api/v1/auth/register',
    payload:{username:'another_user',displayName:'',password:'short',role:'admin'}});
  assert.equal(invalid.statusCode,422);
  const session = await auth.login({username,password,deviceLabel:'recovery-test'});
  const identity = await auth.authenticate(session.accessToken);
  await assert.rejects(auth.recover({username,recoveryCode:'X'.repeat(43),password:changed}));
  await auth.authenticate(session.accessToken);
  const races = await Promise.allSettled([
    auth.recover({username,recoveryCode:created.recoveryCode,password:changed}),
    auth.recover({username,recoveryCode:created.recoveryCode,password:changed}),
  ]);
  assert.equal(races.filter(v=>v.status==='fulfilled').length,1);
  const result = races.find(v=>v.status==='fulfilled');
  assert.ok(result?.status==='fulfilled');
  assert.notEqual(result.value.recoveryCode,created.recoveryCode);
  await assert.rejects(auth.authenticate(session.accessToken));
  await assert.rejects(auth.refresh(session.refreshToken));
  await assert.rejects(validateConnection(db,identity));
  await assert.rejects(auth.login({username,password,deviceLabel:'old-password'}));
  await auth.login({username,password:changed,deviceLabel:'new-password'});
  await assert.rejects(auth.recover({username,recoveryCode:created.recoveryCode,password}));
  const response = await app.inject({method:'POST',url:'/api/v1/auth/recover',
    payload:{username,recoveryCode:result.value.recoveryCode,password}});
  assert.equal(response.statusCode,200);
  assert.equal(response.headers['cache-control'],'no-store');
  await db.run("UPDATE users SET status='DISABLED' WHERE id=?",[created.user.id]);
  await assert.rejects(auth.recover({username,recoveryCode:response.json().data.recoveryCode,password}));
});
