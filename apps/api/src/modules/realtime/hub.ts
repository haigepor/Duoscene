import { createHmac, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { WebSocket } from 'ws';
import type { RowDataPacket } from 'mysql2/promise';
import type { Database } from '../../shared/database.ts';
import type { AuthService, Identity } from '../auth/service.ts';
import { validateConnection } from '../auth/service.ts';
import { identify } from '../auth/routes.ts';
import type { RoomService } from '../rooms/service.ts';
import { chatRepository } from '../chat/repository.ts';
import { createToken } from '../auth/security.ts';
import { success } from '../../shared/response.ts';
import { ApiError } from '../../shared/errors.ts';
import { RoomTimeline, validateCommand } from './timeline.ts';
import { RoomPlayback } from './playback.ts';
import type { AppConfig } from '../../config/env.ts';

type Room = Awaited<ReturnType<RoomService['get']>>;
type Peer = { socket: WebSocket; user: Identity; id: string; voice: boolean; alive: boolean; count: number; window: number };
type Runtime = { playback: RoomPlayback; room: Room; peers: Map<string, Peer>; queue: Promise<unknown>; touched: number; checkpointQueued: boolean };
type Ticket = { roomId: string; access: string; expires: number };
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const bounded = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).every(k => keys.includes(k));

/** 单进程房间 actor。所有状态变更、换片持久化和聊天均排入同一房间队列。 */
export function createRealtimeHub(db: Database, auth: AuthService, rooms: RoomService, config: AppConfig) {
  const tickets = new Map<string, Ticket>();
  const runtimes = new Map<string, Promise<Runtime>>();
  const admissions = new Map<string, number>();
  let closing = false;
  const chat = chatRepository(db);
  // 消息循环与心跳对每个 peer 每次都要 rooms.get（2 条 SQL）。房间状态/成员
  // 不会逐消息变化，用 3s TTL 缓存把热路径的查库压到最多 1 次/3s/房间成员；
  // 票据签发与握手仍走实时查询，保证入房时的状态是新鲜的。
  const roomCache = new Map<string, { room: Room; expires: number }>();
  const ROOM_CACHE_TTL = 3000;
  async function cachedRoom(roomId: string, userId: string): Promise<Room> {
    const key = `${roomId}:${userId}`;
    const cached = roomCache.get(key);
    if (cached && cached.expires > Date.now()) return cached.room;
    const room = await rooms.get(roomId, userId);
    roomCache.set(key, { room, expires: Date.now() + ROOM_CACHE_TTL });
    if (roomCache.size > 1024) {
      const now = Date.now();
      for (const [k, v] of roomCache) if (v.expires <= now) roomCache.delete(k);
    }
    return room;
  }
  let checkpointWarning = (_roomId: string) => {};
  const send = (peer: Peer, value: unknown) => {
    if (peer.socket.readyState !== 1) return;
    // 慢消费者不能无限累积状态或语音信令。
    if (peer.socket.bufferedAmount > 256 * 1024) { peer.socket.close(4008, 'Slow consumer'); return; }
    peer.socket.send(JSON.stringify(value));
  };
  const snapshot = (r: Runtime) => ({ type: 'snapshot', ...r.playback.timeline.snapshot(), room: r.room, peers: [...r.peers.values()].map(p => ({ userId: p.user.id, displayName: p.user.displayName, connectionId: p.id, voice: p.voice })) });
  const broadcast = (r: Runtime, value: unknown = snapshot(r)) => { for (const p of r.peers.values()) send(p, value); };
  async function runtime(room: Room) {
    let pending = runtimes.get(room.id);
    if (!pending) {
      pending = (async () => {
        const timeline = new RoomTimeline();
        const [row] = await db.rows<RowDataPacket & { snapshot: unknown }>('SELECT snapshot FROM room_playback WHERE room_id=?', [room.id]);
        if (row) { try { timeline.restore(typeof row.snapshot === 'string' ? JSON.parse(row.snapshot) : row.snapshot); } catch { /* 损坏的旧运行态不影响房间成员。 */ } }
        const playback = new RoomPlayback(timeline, async state => {
          await db.run('INSERT INTO room_playback (room_id,snapshot) VALUES (?,?) ON DUPLICATE KEY UPDATE snapshot=VALUES(snapshot)', [room.id, JSON.stringify(state)]);
        });
        return { playback, room, peers: new Map<string, Peer>(), queue: Promise.resolve(), touched: Date.now(), checkpointQueued: false };
      })();
      runtimes.set(room.id, pending);
      pending.catch(() => { if (runtimes.get(room.id) === pending) runtimes.delete(room.id); });
    }
    return pending;
  }
  function serial(r: Runtime, work: () => Promise<void>) {
    r.queue = r.queue.catch(() => {}).then(work).catch(() => { /* 每个操作自行反馈错误；保持 actor 可用。 */ });
    return r.queue;
  }
  async function checkpoint(r: Runtime, force = false) {
    try { await r.playback.checkpoint(force); }
    catch { checkpointWarning(r.room.id); }
  }
  async function remove(r: Runtime, p: Peer) {
    if (r.peers.get(p.user.id) !== p) return;
    r.peers.delete(p.user.id); r.playback.disconnect(p.user.id); r.touched = Date.now(); broadcast(r);
    await checkpoint(r, true);
  }
  async function reconcile(roomId: string) {
    const pending = runtimes.get(roomId); if (!pending) return;
    const r = await pending;
    await serial(r, async () => {
      for (const p of [...r.peers.values()]) {
        try { const room = await rooms.get(roomId, p.user.id); if (room.status !== 'OPEN') throw Error(); r.room = room; }
        catch { await remove(r, p); p.socket.close(4003, 'Room unavailable'); }
      }
      broadcast(r);
    });
  }
  const ticker = setInterval(() => {
    for (const [id, ticket] of tickets) if (ticket.expires < Date.now()) tickets.delete(id);
    for (const [id, pending] of runtimes) void pending.then(r => {
      broadcast(r);
      const expired = () => !r.peers.size && !admissions.get(id) && Date.now() - r.touched > 60000;
      if (r.checkpointQueued || (!expired() && !r.playback.checkpointDue)) return;
      // 慢写入期间至多保留一个检查点任务，且始终在 actor 内保存最新状态。
      r.checkpointQueued = true;
      void serial(r, async () => {
        try {
          await checkpoint(r);
          if (expired() && !r.playback.dirty && runtimes.get(id) === pending) runtimes.delete(id);
        } finally { r.checkpointQueued = false; }
      });
    }).catch(() => {});
  }, 1000);
  const heartbeat = setInterval(() => {
    for (const pending of runtimes.values()) void pending.then(r => serial(r, async () => {
      for (const p of [...r.peers.values()]) {
        try { await validateConnection(db, p.user); const room = await cachedRoom(r.room.id, p.user.id); if (room.status !== 'OPEN' || !p.alive) throw Error(); r.room = room; p.alive = false; p.socket.ping(); }
        catch { await remove(r, p); p.socket.close(4003, 'Session unavailable'); }
      }
    })).catch(() => {});
  }, 10000);
  ticker.unref(); heartbeat.unref();
  return {
    reconcile,
    async register(app: FastifyInstance) {
      checkpointWarning = roomId => { app.log.warn({ roomId }, 'Room checkpoint failed; pending retry'); };
      app.post<{ Params: { roomId: string } }>('/api/v1/rooms/:roomId/realtime-ticket', async request => {
        if (closing) throw new ApiError(503, 'SHUTTING_DOWN', 'Service is shutting down');
        const identity = await identify(request, auth);
        const room = await rooms.get(request.params.roomId, identity.id);
        if (room.status !== 'OPEN') throw new ApiError(409, 'ROOM_CLOSED', 'Room closed');
        if (tickets.size > 2048) throw new ApiError(429, 'RATE_LIMITED', 'Too many tickets');
        const token = createToken();
        tickets.set(token, { roomId: room.id, access: request.headers.authorization!.slice(7), expires: Date.now() + 30000 });
        return success({ ticket: token, expiresIn: 30 }, request.id);
      });
      const accepted = new WeakMap<FastifyRequest, { user: Identity; room: Room }>();
      app.get<{ Querystring: { ticket?: string } }>('/realtime', {
        websocket: true,
        preValidation: async request => {
          if (closing) throw new ApiError(503, 'SHUTTING_DOWN', 'Service is shutting down');
          const value = request.query.ticket;
          const ticket = typeof value === 'string' ? tickets.get(value) : undefined;
          if (typeof value === 'string') tickets.delete(value);
          if (!ticket || ticket.expires < Date.now()) throw new ApiError(401, 'UNAUTHORIZED', 'Invalid ticket');
          const user = await auth.authenticate(ticket.access);
          const room = await rooms.get(ticket.roomId, user.id);
          if (room.status !== 'OPEN') throw new ApiError(409, 'ROOM_CLOSED', 'Room closed');
          accepted.set(request, { user, room });
        },
      }, (socket, request) => {
        if (closing) { socket.close(1001, 'Server shutting down'); return; }
        const identity = accepted.get(request)!;
        const p: Peer = { socket, user: identity.user, id: randomUUID(), voice: false, alive: true, count: 0, window: Date.now() };
        const roomId = identity.room.id;
        // 在异步恢复和 actor 排队前同步预留，避免空房清理删掉即将接纳连接的实例。
        admissions.set(roomId, (admissions.get(roomId) ?? 0) + 1);
        const pending = runtime(identity.room);
        // 官方插件要求同步安装监听器，异步 DB 恢复通过同一 Promise 等待。
        socket.on('pong', () => { p.alive = true; });
        socket.on('error', () => {});
        void pending.then(r => serial(r, async () => {
          if (socket.readyState !== 1) return;
          const old = r.peers.get(p.user.id);
          if (old) { await remove(r, old); old.socket.close(4001, 'Replaced'); }
          r.room = identity.room; r.touched = Date.now(); r.peers.set(p.user.id, p); r.playback.connect(p.user.id); broadcast(r);
          send(p, { type: 'history', messages: await chat.history(r.room.id), initial: true });
          const voice = config.voice;
          const username = `${Math.floor(Date.now() / 1000) + 14400}:${p.user.id}`;
          send(p, { type: 'welcome', protocolVersion: 1, connectionId: p.id, userId: p.user.id, iceServers: voice ? [{ urls: voice.urls, username, credential: createHmac('sha1', voice.secret).update(username).digest('base64') }] : [], relayOnly: voice?.relayOnly ?? false });
        })).catch(() => socket.close(1011, 'Initialization failed')).finally(() => {
          const count = (admissions.get(roomId) ?? 1) - 1;
          if (count) admissions.set(roomId, count); else admissions.delete(roomId);
        });
        socket.on('close', () => { void pending.then(r => serial(r, async () => { await remove(r, p); })).catch(() => {}); });
        socket.on('message', (bytes, binary) => {
          if (binary) { socket.close(1003, 'JSON required'); return; }
          if (Date.now() - p.window > 1000) { p.count = 0; p.window = Date.now(); }
          if (++p.count > 80) { socket.close(4008, 'Rate limited'); return; }
          let message: unknown;
          try { message = JSON.parse(bytes.toString()); } catch { socket.close(1007, 'Invalid JSON'); return; }
          void pending.then(r => serial(r, async () => {
            if (r.peers.get(p.user.id) !== p || socket.readyState !== 1) return;
            const commandId = object(message) && typeof message.commandId === 'string' ? message.commandId : undefined;
            try {
              await validateConnection(db, p.user);
              const room = await cachedRoom(r.room.id, p.user.id);
              if (room.status !== 'OPEN') throw Error('ROOM_CLOSED'); r.room = room;
              if (validateCommand(message)) {
                if (room.controlMode === 'OWNER_ONLY' && p.user.id !== room.ownerUserId) throw new ApiError(403, 'OWNER_REQUIRED', 'Owner control required');
                await r.playback.command(p.user.id, message); broadcast(r); send(p, { type: 'ack', commandId }); return;
              }
              if (!object(message)) throw Error('INVALID_MESSAGE');
              if (message.type === 'ready' && exact(message, ['type', 'epoch', 'generation', 'ready']) && message.epoch === r.playback.timeline.epoch && Number.isInteger(message.generation) && typeof message.ready === 'boolean') {
                const revision = r.playback.timeline.revision;
                r.playback.ready(p.user.id, Number(message.generation), message.ready); broadcast(r);
                if (r.playback.timeline.revision !== revision) await checkpoint(r, true);
                return;
              }
              if (message.type === 'chat' && exact(message, ['type', 'clientMessageId', 'text']) && typeof message.clientMessageId === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(message.clientMessageId) && bounded(message.text, 2000) && message.text.trim()) {
                broadcast(r, { type: 'chat', message: await chat.send(r.room.id, p.user.id, message.clientMessageId, message.text.trim()) }); return;
              }
              if (message.type === 'history' && exact(message, ['type', 'before']) && typeof message.before === 'string' && /^\d{1,20}$/.test(message.before)) { send(p, { type: 'history', messages: await chat.history(r.room.id, message.before), initial: false }); return; }
              if (message.type === 'voice' && exact(message, ['type', 'enabled']) && typeof message.enabled === 'boolean') { p.voice = message.enabled; broadcast(r); return; }
              if (message.type === 'signal' && exact(message, ['type', 'target', 'callId', 'kind', 'data']) && bounded(message.target, 80) && bounded(message.callId, 80) && ['offer', 'answer', 'ice', 'hangup'].includes(String(message.kind)) && object(message.data) && JSON.stringify(message.data).length < 20000) {
                const target = [...r.peers.values()].find(peer => peer.id === message.target && peer.user.id !== p.user.id);
                if (!p.voice || !target?.voice) throw Error('VOICE_NOT_READY');
                if (message.kind === 'offer' && p.user.id !== r.room.ownerUserId) throw Error('OWNER_OFFER_REQUIRED');
                send(target, { ...message, from: p.id }); return;
              }
              throw Error('INVALID_MESSAGE');
            } catch (error) {
              const code = error instanceof ApiError ? error.code : error instanceof Error ? error.message : 'SERVER_ERROR';
              send(p, { type: 'error', commandId, code: ['REVISION_CONFLICT','EPOCH_CHANGED','NO_MEDIA','INVALID_MESSAGE','VOICE_NOT_READY','OWNER_OFFER_REQUIRED','OWNER_REQUIRED'].includes(code) ? code : 'ROOM_UNAVAILABLE' });
              send(p, snapshot(r));
              if ((error instanceof ApiError && error.code !== 'OWNER_REQUIRED') || code === 'ROOM_CLOSED') { await remove(r, p); socket.close(4003, 'Room unavailable'); }
            }
          })).catch(() => socket.close(1011, 'Operation failed'));
        });
      });
    },
    async close() {
      closing = true;
      clearInterval(ticker); clearInterval(heartbeat); tickets.clear();
      let failed = false;
      for (const pending of runtimes.values()) {
        try {
          const r = await pending;
          await serial(r, async () => {
            for (const p of r.peers.values()) {
              r.playback.disconnect(p.user.id); p.socket.terminate();
            }
            r.peers.clear();
            try { await r.playback.checkpoint(true); }
            catch { failed = true; checkpointWarning(r.room.id); }
          });
          // terminate 的 close 事件可能继续排队；最终退出前等待这些清理完成。
          await r.queue;
        } catch { failed = true; }
      }
      if (failed) throw Error('Room checkpoint failed during shutdown');
      runtimes.clear(); admissions.clear();
    },
  };
}
