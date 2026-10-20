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
import type { AppConfig } from '../../config/env.ts';

type Room = Awaited<ReturnType<RoomService['get']>>;
type Peer = { socket: WebSocket; user: Identity; id: string; voice: boolean; alive: boolean; count: number; window: number };
type Runtime = { timeline: RoomTimeline; room: Room; peers: Map<string, Peer>; queue: Promise<unknown>; touched: number };
type Ticket = { roomId: string; access: string; expires: number };
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const bounded = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).every(k => keys.includes(k));

/** 单进程房间 actor。所有状态变更、换片持久化和聊天均排入同一房间队列。 */
export function createRealtimeHub(db: Database, auth: AuthService, rooms: RoomService, config: AppConfig) {
  const tickets = new Map<string, Ticket>();
  const runtimes = new Map<string, Promise<Runtime>>();
  const chat = chatRepository(db);
  const send = (peer: Peer, value: unknown) => {
    if (peer.socket.readyState !== 1) return;
    // 慢消费者不能无限累积状态或语音信令。
    if (peer.socket.bufferedAmount > 256 * 1024) { peer.socket.close(4008, 'Slow consumer'); return; }
    peer.socket.send(JSON.stringify(value));
  };
  const snapshot = (r: Runtime) => ({ type: 'snapshot', ...r.timeline.snapshot(), room: r.room, peers: [...r.peers.values()].map(p => ({ userId: p.user.id, displayName: p.user.displayName, connectionId: p.id, voice: p.voice })) });
  const broadcast = (r: Runtime, value: unknown = snapshot(r)) => { for (const p of r.peers.values()) send(p, value); };
  async function runtime(room: Room) {
    let pending = runtimes.get(room.id);
    if (!pending) {
      pending = (async () => {
        const timeline = new RoomTimeline();
        const [row] = await db.rows<RowDataPacket & { snapshot: unknown }>('SELECT snapshot FROM room_playback WHERE room_id=?', [room.id]);
        if (row) { try { timeline.restore(typeof row.snapshot === 'string' ? JSON.parse(row.snapshot) : row.snapshot); } catch { /* 损坏的旧运行态不影响房间成员。 */ } }
        return { timeline, room, peers: new Map<string, Peer>(), queue: Promise.resolve(), touched: Date.now() };
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
  async function persist(r: Runtime) {
    await db.run('INSERT INTO room_playback (room_id,snapshot) VALUES (?,?) ON DUPLICATE KEY UPDATE snapshot=VALUES(snapshot)', [r.room.id, JSON.stringify(r.timeline.snapshot())]);
  }
  function remove(r: Runtime, p: Peer) {
    if (r.peers.get(p.user.id) !== p) return;
    r.peers.delete(p.user.id); r.timeline.disconnect(p.user.id); r.touched = Date.now(); broadcast(r);
  }
  async function reconcile(roomId: string) {
    const pending = runtimes.get(roomId); if (!pending) return;
    const r = await pending;
    await serial(r, async () => {
      for (const p of [...r.peers.values()]) {
        try { const room = await rooms.get(roomId, p.user.id); if (room.status !== 'OPEN') throw Error(); r.room = room; }
        catch { remove(r, p); p.socket.close(4003, 'Room unavailable'); }
      }
      broadcast(r);
    });
  }
  const ticker = setInterval(() => {
    for (const [id, ticket] of tickets) if (ticket.expires < Date.now()) tickets.delete(id);
    for (const [id, pending] of runtimes) void pending.then(r => {
      if (!r.peers.size && Date.now() - r.touched > 60000) { runtimes.delete(id); return; }
      broadcast(r);
    }).catch(() => {});
  }, 1000);
  const heartbeat = setInterval(() => {
    for (const pending of runtimes.values()) void pending.then(r => serial(r, async () => {
      for (const p of [...r.peers.values()]) {
        try { await validateConnection(db, p.user); const room = await rooms.get(r.room.id, p.user.id); if (room.status !== 'OPEN' || !p.alive) throw Error(); r.room = room; p.alive = false; p.socket.ping(); }
        catch { remove(r, p); p.socket.close(4003, 'Session unavailable'); }
      }
    })).catch(() => {});
  }, 10000);
  ticker.unref(); heartbeat.unref();
  return {
    reconcile,
    async register(app: FastifyInstance) {
      app.post<{ Params: { roomId: string } }>('/api/v1/rooms/:roomId/realtime-ticket', async request => {
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
        const identity = accepted.get(request)!;
        const p: Peer = { socket, user: identity.user, id: randomUUID(), voice: false, alive: true, count: 0, window: Date.now() };
        const pending = runtime(identity.room);
        // 官方插件要求同步安装监听器，异步 DB 恢复通过同一 Promise 等待。
        socket.on('pong', () => { p.alive = true; });
        socket.on('error', () => {});
        void pending.then(r => serial(r, async () => {
          if (socket.readyState !== 1) return;
          const old = r.peers.get(p.user.id);
          if (old) { remove(r, old); old.socket.close(4001, 'Replaced'); }
          r.room = identity.room; r.peers.set(p.user.id, p); r.timeline.connect(p.user.id); broadcast(r);
          send(p, { type: 'history', messages: await chat.history(r.room.id), initial: true });
          const voice = config.voice;
          const username = `${Math.floor(Date.now() / 1000) + 14400}:${p.user.id}`;
          send(p, { type: 'welcome', protocolVersion: 1, connectionId: p.id, userId: p.user.id, iceServers: voice ? [{ urls: voice.urls, username, credential: createHmac('sha1', voice.secret).update(username).digest('base64') }] : [], relayOnly: voice?.relayOnly ?? false });
        })).catch(() => socket.close(1011, 'Initialization failed'));
        socket.on('close', () => { void pending.then(r => serial(r, async () => { remove(r, p); })).catch(() => {}); });
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
              const room = await rooms.get(r.room.id, p.user.id);
              if (room.status !== 'OPEN') throw Error('ROOM_CLOSED'); r.room = room;
              if (validateCommand(message)) {
                if (room.controlMode === 'OWNER_ONLY' && p.user.id !== room.ownerUserId) throw new ApiError(403, 'OWNER_REQUIRED', 'Owner control required');
                r.timeline.command(p.user.id, message); await persist(r); broadcast(r); send(p, { type: 'ack', commandId }); return;
              }
              if (!object(message)) throw Error('INVALID_MESSAGE');
              if (message.type === 'ready' && exact(message, ['type', 'epoch', 'generation', 'ready']) && message.epoch === r.timeline.epoch && Number.isInteger(message.generation) && typeof message.ready === 'boolean') {
                r.timeline.ready(p.user.id, Number(message.generation), message.ready); broadcast(r); return;
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
              if ((error instanceof ApiError && error.code !== 'OWNER_REQUIRED') || code === 'ROOM_CLOSED') { remove(r, p); socket.close(4003, 'Room unavailable'); }
            }
          })).catch(() => socket.close(1011, 'Operation failed'));
        });
      });
    },
    async close() { clearInterval(ticker); clearInterval(heartbeat); tickets.clear(); for (const pending of runtimes.values()) { try { const r = await pending; for (const p of r.peers.values()) p.socket.terminate(); await r.queue; } catch {} } runtimes.clear(); },
  };
}
