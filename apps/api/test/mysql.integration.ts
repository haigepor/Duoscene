import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import { loadConfig } from '../src/config/env.ts';
import { Database } from '../src/shared/database.ts';
import { migrate } from '../src/commands/migrate.ts';
import { createPrivateUser, disablePrivateUser } from '../src/commands/accounts.ts';
import { createAuthService } from '../src/modules/auth/service.ts';
import { createRoomService } from '../src/modules/rooms/service.ts';
import { hashToken } from '../src/modules/auth/security.ts';
import { buildApp } from '../src/app.ts';
import type { RowDataPacket } from 'mysql2/promise';

test('real MySQL migrations, sessions and concurrent room membership', async (t) => {
  const base = loadConfig();
  const database = process.env.DUOSCENE_TEST_DATABASE;
  assert.ok(database && /^duoscene_test_[a-z0-9_]{1,40}$/.test(database), 'Set DUOSCENE_TEST_DATABASE to an isolated duoscene_test_* database');
  assert.equal(base.database.mode, 'mysql', 'DATABASE_MODE=mysql and MYSQL_* are required');
  if (base.database.mode !== 'mysql') throw new Error('MySQL configuration required');
  const config = { ...base, database: { ...base.database, database } };
  const db = new Database(config.database);
  const userIds: string[] = [];
  const roomIds: string[] = [];
  t.after(async () => {
    try {
      for (const roomId of roomIds) await db.run('DELETE FROM rooms WHERE id = ?', [roomId]);
      for (const userId of userIds) await db.run('DELETE FROM users WHERE id = ?', [userId]);
    } finally { await db.close(); }
  });
  await migrate(db);
  assert.deepEqual(await migrate(db), []);
  const suffix = randomUUID().slice(0, 8);
  const password = 'integration-only-password';
  const owner = await createPrivateUser(db, `owner_${suffix}`, '房主', password); userIds.push(owner.id);
  const alice = await createPrivateUser(db, `alice_${suffix}`, '成员 A', password); userIds.push(alice.id);
  const bob = await createPrivateUser(db, `bob_${suffix}`, '成员 B', password); userIds.push(bob.id);
  const auth = createAuthService(db);
  const rooms = createRoomService(db);
  const room = await rooms.create(owner.id, '事务测试'); roomIds.push(room.id);
  assert.equal(room.members[0]?.userId, owner.id);
  assert.equal(room.members[0]?.seatNo, 1);

  await t.test('two users racing for last seat cannot produce a third member', async () => {
    const invite = await rooms.invite(room.id, owner.id);
    const results = await Promise.allSettled([rooms.join(alice.id, invite.token), rooms.join(bob.id, invite.token)]);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    const state = await rooms.get(room.id, owner.id);
    assert.equal(state.members.length, 2);
    const winner = state.members.find((member) => member.userId !== owner.id)!;
    await rooms.join(winner.userId, invite.token);
    const [usage] = await db.rows<RowDataPacket & { usedCount: number }>('SELECT used_count AS usedCount FROM room_invites WHERE id = ?', [invite.id]);
    assert.equal(usage?.usedCount, 1);
    await rooms.remove(room.id, owner.id, winner.userId);
  });

  await t.test('expired/revoked invites and a rolled-back member insert do not consume usage', async () => {
    const expired = await rooms.invite(room.id, owner.id);
    await db.run('UPDATE room_invites SET expires_at = TIMESTAMPADD(SECOND, -1, UTC_TIMESTAMP(3)) WHERE id = ?', [expired.id]);
    await assert.rejects(rooms.join(alice.id, expired.token), /expired/);
    const revoked = await rooms.invite(room.id, owner.id);
    await rooms.revokeInvite(room.id, owner.id, revoked.id);
    await assert.rejects(rooms.join(alice.id, revoked.token), /revoked/);
    const active = await rooms.invite(room.id, owner.id);
    await assert.rejects(rooms.join(randomUUID(), active.token));
    const [usage] = await db.rows<RowDataPacket & { usedCount: number }>('SELECT used_count AS usedCount FROM room_invites WHERE id = ?', [active.id]);
    assert.equal(usage?.usedCount, 0);
    await rooms.join(alice.id, active.token);
    await assert.rejects(rooms.close(room.id, alice.id));
    await assert.rejects(rooms.leave(room.id, owner.id), /OWNER_MUST_CLOSE/);
    await rooms.leave(room.id, alice.id);
  });

  await t.test('distinct valid invites racing for one seat preserve the unused invite', async () => {
    const first = await rooms.invite(room.id, owner.id);
    const second = await rooms.invite(room.id, owner.id);
    const results = await Promise.allSettled([rooms.join(alice.id, first.token), rooms.join(bob.id, second.token)]);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    const usage = await db.rows<RowDataPacket & { usedCount: number }>(
      'SELECT used_count AS usedCount FROM room_invites WHERE id IN (?, ?)', [first.id, second.id],
    );
    assert.deepEqual(usage.map((row) => row.usedCount).sort(), [0, 1]);
    const state = await rooms.get(room.id, owner.id);
    await rooms.remove(room.id, owner.id, state.members.find((member) => member.userId !== owner.id)!.userId);
  });

  await t.test('refresh rotates atomically and replay revocation survives the error response', async () => {
    const login = await auth.login({ username: owner.username, password, deviceLabel: 'integration' });
    const refreshed = await auth.refresh(login.refreshToken);
    assert.notEqual(login.refreshToken, refreshed.refreshToken);
    await assert.rejects(auth.authenticate(login.accessToken));
    await assert.rejects(auth.refresh(login.refreshToken), /Session revoked/);
    await assert.rejects(auth.authenticate(refreshed.accessToken));
    await assert.rejects(auth.refresh(refreshed.refreshToken));
  });

  await t.test('concurrent refresh yields one rotation and then revokes the family', async () => {
    const login = await auth.login({ username: owner.username, password, deviceLabel: 'parallel' });
    const results = await Promise.allSettled([auth.refresh(login.refreshToken), auth.refresh(login.refreshToken)]);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    const [session] = await db.rows<RowDataPacket & { revokedAt: Date | null }>(
      'SELECT s.revoked_at AS revokedAt FROM auth_sessions s JOIN auth_refresh_tokens t ON t.session_id = s.id WHERE t.token_hash = ?', [hashToken(login.refreshToken)],
    );
    assert.ok(session?.revokedAt);
  });

  await t.test('real Fastify HTTP login/room contract and immediate logout/disable', async () => {
    const app = buildApp({ config, logger: false });
    try {
      assert.equal((await app.inject('/health/ready')).statusCode, 200);
      const login = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: {
        username: bob.username, password, deviceLabel: 'http',
      } });
      assert.equal(login.statusCode, 200);
      assert.ok(!login.body.includes('passwordHash'));
      const headers = { authorization: `Bearer ${login.json().data.accessToken}` };
      assert.equal((await app.inject({ url: '/api/v1/rooms', headers })).statusCode, 200);
      assert.equal((await app.inject({ method: 'POST', url: '/api/v1/auth/logout', headers })).statusCode, 200);
      assert.equal((await app.inject({ url: '/api/v1/auth/me', headers })).statusCode, 401);
      const session = await auth.login({ username: bob.username, password, deviceLabel: 'disable' });
      await disablePrivateUser(db, bob.username);
      await assert.rejects(auth.authenticate(session.accessToken));
      await assert.rejects(auth.refresh(session.refreshToken));
      await rooms.close(room.id, owner.id);
      const invite = await rooms.invite(room.id, owner.id).catch(() => null);
      assert.equal(invite, null);
    } finally { await app.close(); }
  });
});
