import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config/env.ts';
import { Database } from '../src/shared/database.ts';
import { migrate } from '../src/commands/migrate.ts';
import { createPrivateUser } from '../src/commands/accounts.ts';
import { createAuthService } from '../src/modules/auth/service.ts';
import { createRoomService } from '../src/modules/rooms/service.ts';

test('real authenticated WS: two seats, playback, durable chat, reconnect and removal', async () => {
  const base = loadConfig(), database = process.env.DUOSCENE_TEST_DATABASE;
  assert.ok(database?.startsWith('duoscene_test_')); assert.equal(base.database.mode, 'mysql');
  if (base.database.mode !== 'mysql') throw Error('MySQL required');
  const config = { ...base, database: { ...base.database, database: database! } };
  const db = new Database(config.database); await migrate(db);
  const suffix = randomUUID().slice(0, 8), ids: string[] = [], roomIds: string[] = [];
  const app = buildApp({ config, logger: false });
  const sockets: WebSocket[] = [];
  try {
    const auth = createAuthService(db), rooms = createRoomService(db);
    for (const role of ['owner','guest','outsider']) ids.push((await createPrivateUser(db, `${role}_${suffix}`, role, 'test-only-password-strong')).id);
    const credentials: Awaited<ReturnType<typeof auth.login>>[] = [];
    for (const role of ['owner','guest','outsider']) credentials.push(await auth.login({ username: `${role}_${suffix}`, password: 'test-only-password-strong', deviceLabel: 'ws-test' }));
    const room = await rooms.create(ids[0]!, '双人实时测试'); roomIds.push(room.id);
    const invitation = await rooms.invite(room.id, ids[0]!); await rooms.join(ids[1]!, invitation.token);
    await app.listen({ host: '127.0.0.1', port: 0 }); const address = app.server.address(); assert.ok(address && typeof address !== 'string');
    const ticket = async (index: number) => app.inject({ method: 'POST', url: `/api/v1/rooms/${room.id}/realtime-ticket`, headers: { authorization: `Bearer ${credentials[index]!.accessToken}` } });
    assert.equal((await ticket(2)).statusCode, 404);
    const connect = async (index: number) => {
      const token = (await ticket(index)).json().data.ticket as string;
      const ws = new WebSocket(`ws://127.0.0.1:${address.port}/realtime?ticket=${token}`); sockets.push(ws);
      const events: any[] = [];
      ws.addEventListener('message', e => events.push(JSON.parse(String(e.data))));
      const wait = async (predicate: (e: any) => boolean) => {
        const until = Date.now() + 8000;
        while (Date.now() < until) { const found = events.findLast(predicate); if (found) return found; await new Promise(r => setTimeout(r, 20)); }
        throw Error('Timed out waiting for WS event');
      };
      const state = await wait(e => e.type === 'snapshot');
      const send = (data: object) => ws.send(JSON.stringify(data));
      const command = async (type: string, values = {}) => {
        const current = events.findLast(e => e.type === 'snapshot'); const id = randomUUID();
        send({ type, commandId: id, epoch: current.epoch, expectedRevision: current.revision, ...values });
        await wait(e => e.type === 'ack' && e.commandId === id);
      };
      return { ws, events, wait, send, command, state, token };
    };
    const a = await connect(0), b = await connect(1);
    await a.wait(e => e.type === 'snapshot' && e.peers.length === 2);
    // REST access 轮换不应撤销同一仍有效会话已建立的房间连接。
    credentials[0] = await auth.refresh(credentials[0]!.refreshToken);
    const reused = await app.inject({ url: `/realtime?ticket=${a.token}` }); assert.equal(reused.statusCode, 401);
    await a.command('media', { media: { uri: 'https://example.com/test.mp4', identity: 'shared-test', title: '测试视频', hls: false } });
    const selected = await b.wait(e => e.type === 'snapshot' && e.media?.identity === 'shared-test');
    for (const p of [a,b]) p.send({ type: 'ready', epoch: selected.epoch, generation: selected.generation, ready: true });
    await a.wait(e => e.type === 'snapshot' && Object.values(e.ready).every(Boolean));
    await a.command('play'); await b.wait(e => e.type === 'snapshot' && e.playing);
    await b.command('pause'); await a.wait(e => e.type === 'snapshot' && !e.playing && !e.wanted);
    await a.command('seek', { positionMs: 5000 });
    const seek = await b.wait(e => e.type === 'snapshot' && e.generation > selected.generation);
    assert.equal(seek.positionMs, 5000);
    b.send({ type: 'ready', epoch: seek.epoch, generation: selected.generation, ready: true });
    for (const p of [a,b]) p.send({ type: 'ready', epoch: seek.epoch, generation: seek.generation, ready: true });
    await a.wait(e => e.type === 'snapshot' && e.generation === seek.generation && Object.values(e.ready).every(Boolean));
    await a.command('rate', { rate: 1.5 }); await b.wait(e => e.type === 'snapshot' && e.rate === 1.5);
    const providerMedia = { provider: 'whisklet', filmId: 'whisklet:123', episode: 7, lineCode: 'main', identity: 'whisklet:123:7', title: '第七集' };
    await a.command('media', { media: providerMedia, positionMs: 123456 });
    const handoff = await b.wait(e => e.type === 'snapshot' && e.media?.identity === providerMedia.identity);
    assert.deepEqual(handoff.media, providerMedia);
    assert.equal(handoff.positionMs, 123456);
    assert.equal(handoff.playing, false);
    assert.equal(handoff.wanted, false);
    const id = randomUUID(); a.send({ type: 'chat', clientMessageId: id, text: '你好，已经同步了' });
    const message = await b.wait(e => e.type === 'chat' && e.message.clientMessageId === id);
    a.send({ type: 'chat', clientMessageId: id, text: '不会重复插入' });
    await new Promise(r => setTimeout(r, 100));
    const [count] = await db.rows<any>('SELECT COUNT(*) AS count FROM chat_messages WHERE room_id=?', [room.id]); assert.equal(count.count, 1);
    b.ws.close(); await a.wait(e => e.type === 'snapshot' && e.peers.length === 1);
    const restored = await connect(1);
    await restored.wait(e => e.type === 'history' && e.messages.some((m: any) => m.id === message.message.id));
    assert.equal(restored.state.playing, false);
    assert.deepEqual(restored.state.media, providerMedia);
    assert.equal(restored.state.positionMs, 123456);
    await app.inject({ method: 'DELETE', url: `/api/v1/rooms/${room.id}/members/${ids[1]}`, headers: { authorization: `Bearer ${credentials[0]!.accessToken}` } });
    await a.wait(e => e.type === 'snapshot' && e.peers.length === 1 && e.room.members.length === 1);
    assert.equal((await ticket(1)).statusCode, 404);
    await auth.logout(await auth.authenticate(credentials[0]!.accessToken));
    a.send({ type: 'ready', epoch: seek.epoch, generation: seek.generation, ready: true });
    await a.wait(e => e.type === 'error' && e.code === 'ROOM_UNAVAILABLE');
    console.log('PASS two-user WS playback, chat SQL dedupe/history, reconnect, membership revocation');
  } finally {
    for (const ws of sockets) ws.close(); await app.close();
    for (const id of roomIds) await db.run('DELETE FROM rooms WHERE id=?', [id]);
    for (const id of ids) await db.run('DELETE FROM users WHERE id=?', [id]);
    await db.close();
  }
});
