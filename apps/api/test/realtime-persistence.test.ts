import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import Fastify from 'fastify';
import websocket from '@fastify/websocket';
import { loadConfig } from '../src/config/env.ts';
import type { Database } from '../src/shared/database.ts';
import type { AuthService } from '../src/modules/auth/service.ts';
import type { RoomService } from '../src/modules/rooms/service.ts';
import { createRealtimeHub } from '../src/modules/realtime/hub.ts';

type Frame = Record<string, any>;
const pause = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
const users = ['owner', 'guest'].map((role, i) => ({ id: `00000000-0000-4000-8000-00000000000${i}`, username: role, displayName: role, sessionId: `session-${role}` }));
const room = { id: '11111111-1111-4111-8111-111111111111', name: 'Persistence', ownerUserId: users[0]!.id, status: 'OPEN', controlMode: 'BOTH', createdAt: new Date(), members: users.map((user, i) => ({ userId: user.id, displayName: user.displayName, seatNo: i + 1, joinedAt: new Date() })) };

function storage() {
  const state: { snapshot: Frame | null; writes: number; nextWrite?: () => Promise<void>; nextRestore?: () => Promise<void> } = { snapshot: null, writes: 0 };
  // 只替换 SQL 存储边界，HTTP 票据、真实 WS、actor、时钟与定时器均走生产代码。
  const db = {
    async rows(sql: string) {
      if (sql.includes('FROM room_playback')) {
        const delayed = state.nextRestore; delete state.nextRestore;
        if (delayed) await delayed();
        return state.snapshot ? [{ snapshot: state.snapshot }] : [];
      }
      if (sql.includes('FROM auth_sessions')) return [{ id: 'active-session' }];
      if (sql.includes('FROM chat_messages')) return [];
      throw Error('Unexpected query');
    },
    async run(_sql: string, values: unknown[]) {
      state.writes++;
      const delayed = state.nextWrite; delete state.nextWrite;
      if (delayed) await delayed();
      state.snapshot = JSON.parse(String(values[1]));
      return { affectedRows: 1 };
    },
  } as unknown as Database;
  return { state, db };
}

async function server(db: Database) {
  const auth = { authenticate: async (token: string) => users[token[0] === 'A' ? 0 : 1]! } as AuthService;
  const rooms = { get: async () => room } as unknown as RoomService;
  const app = Fastify({ logger: false });
  await app.register(websocket);
  const hub = createRealtimeHub(db, auth, rooms, loadConfig({}));
  app.addHook('preClose', async () => { await hub.close(); });
  await hub.register(app);
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address(); assert.ok(address && typeof address !== 'string');
  const port = address.port;
  const sockets: WebSocket[] = [];
  async function connect(index: number, opened?: () => void) {
    const ticket = (await app.inject({ method: 'POST', url: `/api/v1/rooms/${room.id}/realtime-ticket`, headers: { authorization: `Bearer ${index === 0 ? 'A'.repeat(43) : 'B'.repeat(43)}` } })).json().data.ticket;
    const socket = new WebSocket(`ws://127.0.0.1:${port}/realtime?ticket=${ticket}`);
    sockets.push(socket);
    socket.addEventListener('open', () => { opened?.(); });
    const events: Frame[] = [];
    socket.addEventListener('message', event => { events.push(JSON.parse(String(event.data))); });
    async function wait(predicate: (frame: Frame) => boolean, offset = 0): Promise<Frame> {
      const until = performance.now() + 8000;
      while (performance.now() < until) {
        const found = events.slice(offset).findLast(predicate); if (found) return found;
        await pause(10);
      }
      throw Error('Timed out waiting for WS frame');
    }
    await wait(frame => frame.type === 'welcome');
    const snapshot = () => events.findLast(frame => frame.type === 'snapshot')!;
    const send = (value: object) => socket.send(JSON.stringify(value));
    async function command(type: string, extra = {}) {
      const current = snapshot(), commandId = randomUUID();
      send({ type, commandId, epoch: current.epoch, expectedRevision: current.revision, ...extra });
      const result = await wait(frame => ['ack', 'error'].includes(frame.type) && frame.commandId === commandId);
      assert.equal(result.type, 'ack', result.code);
    }
    return { socket, events, wait, snapshot, send, command };
  }
  return { app, connect, close: async () => { for (const socket of sockets) socket.close(); await app.close(); } };
}

test('WS ticker and error snapshots never publish pending or failed media; the same command can retry', async (t) => {
  const { state, db } = storage();
  const fixture = await server(db); t.after(() => fixture.close());
  const a = await fixture.connect(0), b = await fixture.connect(1);
  await a.wait(frame => frame.type === 'snapshot' && frame.peers.length === 2);
  await a.command('media', { media: { uri: 'https://example.com/old.mp4', identity: 'old', title: 'Old', hls: false } });
  const before = a.snapshot();
  let rejectWrite!: (reason: Error) => void, started!: () => void;
  const writing = new Promise<void>(resolve => { started = resolve; });
  state.nextWrite = async () => { started(); await new Promise((_resolve, reject) => { rejectWrite = reject; }); };
  const command = { type: 'media', commandId: 'handoff-retry', epoch: before.epoch, expectedRevision: before.revision, positionMs: 45000, media: { provider: 'whisklet', filmId: 'whisklet:123', episode: 4, identity: 'whisklet:123:4', title: 'Episode 4' } };
  a.send(command); await writing;
  t.after(() => { rejectWrite(Error('cleanup')); });
  const offset = b.events.length;
  const tick = await b.wait(frame => frame.type === 'snapshot', offset);
  assert.equal(tick.media.identity, 'old');
  assert.equal(tick.revision, before.revision);
  rejectWrite(Error('database offline'));
  await a.wait(frame => frame.type === 'error' && frame.commandId === command.commandId);
  assert.equal(a.snapshot().media.identity, 'old');
  assert.equal(state.snapshot!.media.identity, 'old');
  a.send(command);
  await a.wait(frame => frame.type === 'ack' && frame.commandId === command.commandId);
  assert.deepEqual(a.snapshot().media, command.media);
  assert.equal(a.snapshot().positionMs, 45000);
  assert.equal(state.snapshot!.positionMs, 45000);
});

test('WS disconnect and graceful shutdown save advanced progress and a fresh hub recovers paused', async (t) => {
  const { state, db } = storage();
  const fixture = await server(db); t.after(() => fixture.close());
  const a = await fixture.connect(0), b = await fixture.connect(1);
  await a.wait(frame => frame.type === 'snapshot' && frame.peers.length === 2);
  await a.command('media', { media: { uri: 'https://example.com/video.mp4', identity: 'video', title: 'Video', hls: false }, positionMs: 1000 });
  const selected = a.snapshot();
  for (const peer of [a, b]) peer.send({ type: 'ready', epoch: selected.epoch, generation: selected.generation, ready: true });
  await a.wait(frame => frame.type === 'snapshot' && Object.values(frame.ready).every(Boolean));
  await a.command('play'); await pause(40); b.socket.close();
  await a.wait(frame => frame.type === 'snapshot' && frame.peers.length === 1);
  const until = Date.now() + 3000;
  while (state.snapshot?.playing && Date.now() < until) await pause(10);
  assert.equal(state.snapshot!.playing, false);
  assert.ok(state.snapshot!.positionMs > 1000);
  const disconnectedPosition = state.snapshot!.positionMs;
  const reconnected = await fixture.connect(1);
  const reconnectRevision = reconnected.snapshot().revision;
  reconnected.send({ type: 'ready', epoch: selected.epoch, generation: selected.generation, ready: true });
  await a.wait(frame => frame.type === 'snapshot' && frame.revision > reconnectRevision && frame.peers.length === 2 && Object.values(frame.ready).every(Boolean));
  await a.command('play'); await pause(40);
  await fixture.app.close();
  assert.equal(state.snapshot!.playing, false);
  assert.ok(state.snapshot!.positionMs > disconnectedPosition);
  const savedPosition = state.snapshot!.positionMs;
  const restored = await server(db); t.after(() => restored.close());
  const peer = await restored.connect(0);
  assert.notEqual(peer.snapshot().epoch, selected.epoch);
  assert.equal(peer.snapshot().positionMs, savedPosition);
  assert.equal(peer.snapshot().playing, false);
  assert.equal(peer.snapshot().wanted, false);
});

test('idle checkpoint cleanup retains the room actor while an upgraded socket waits to join it', async (t) => {
  t.mock.timers.enable({ apis: ['setInterval', 'Date'], now: Date.now() });
  const { state, db } = storage();
  const fixture = await server(db);
  let release: (() => void) | undefined;
  t.after(async () => { release?.(); await fixture.close(); });
  const original = await fixture.connect(0);
  await original.command('media', { media: { uri: 'https://example.com/video.mp4', identity: 'video', title: 'Video', hls: false } });
  const epoch = original.snapshot().epoch;
  state.nextWrite = async () => { throw Error('temporary checkpoint outage'); };
  const writes = state.writes;
  original.socket.close();
  const until = performance.now() + 3000;
  while (state.writes === writes && performance.now() < until) await pause(10);
  assert.equal(state.writes, writes + 1);
  let started!: () => void;
  const writing = new Promise<void>(resolve => { started = resolve; });
  state.nextWrite = async () => { started(); await new Promise<void>(resolve => { release = resolve; }); };
  t.mock.timers.tick(61000); await writing;
  let upgraded!: () => void;
  const upgrading = new Promise<void>(resolve => { upgraded = resolve; });
  const admission = fixture.connect(0, upgraded); await upgrading;
  release!();
  const owner = await admission;
  assert.equal(owner.snapshot().epoch, epoch);
  const guest = await fixture.connect(1);
  assert.equal(guest.snapshot().epoch, epoch);
  assert.equal(guest.snapshot().peers.length, 2);
});

test('graceful shutdown cannot admit an upgraded socket after its delayed room restore finishes', async (t) => {
  const { state, db } = storage();
  const fixture = await server(db);
  let release!: () => void;
  state.nextRestore = async () => { await new Promise<void>(resolve => { release = resolve; }); };
  t.after(async () => { release?.(); await fixture.close(); });
  const ticket = (await fixture.app.inject({ method: 'POST', url: `/api/v1/rooms/${room.id}/realtime-ticket`, headers: { authorization: `Bearer ${'A'.repeat(43)}` } })).json().data.ticket;
  const address = fixture.app.server.address(); assert.ok(address && typeof address !== 'string');
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}/realtime?ticket=${ticket}`);
  const events: Frame[] = [];
  socket.addEventListener('message', event => { events.push(JSON.parse(String(event.data))); });
  await new Promise<void>(resolve => socket.addEventListener('open', () => resolve(), { once: true }));
  const closing = fixture.app.close(); await pause(20); release(); await closing;
  assert.equal(events.some(frame => frame.type === 'welcome'), false);
});
