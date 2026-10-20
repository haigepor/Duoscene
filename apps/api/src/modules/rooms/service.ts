import { randomUUID } from 'node:crypto';
import type { Database } from '../../shared/database.ts';
import { ApiError } from '../../shared/errors.ts';
import { createToken, hashToken } from '../auth/security.ts';
import { nextSeat, assertOwnerMayLeave } from './policy.ts';
import { roomRepository } from './repository.ts';
import type { RoomRow } from './repository.ts';

const notFound = () => new ApiError(404, 'ROOM_NOT_FOUND', 'Room not found');
function requireOpen(room: RoomRow) {
  if (room.status !== 'OPEN') throw new ApiError(409, 'ROOM_CLOSED', 'Room is closed');
}
function requireOwner(room: RoomRow, userId: string) {
  if (room.ownerUserId !== userId) throw new ApiError(403, 'OWNER_REQUIRED', 'Only the room owner may perform this action');
}

export function createRoomService(db: Database) {
  const repo = roomRepository(db);
  async function view(roomId: string, userId: string) {
    const room = await repo.room(roomId);
    const members = await repo.members(roomId);
    if (!room || !members.some((m) => m.userId === userId)) throw notFound();
    return { ...room, members };
  }
  return {
    async create(userId: string, name: string) {
      const id = randomUUID();
      await db.transaction((sql) => roomRepository(sql).insertRoom(id, userId, name));
      return view(id, userId);
    },
    get: view,
    async list(userId: string, afterId = '', limit = 20) {
      const items = await repo.list(userId, afterId, limit + 1);
      const hasMore = items.length > limit;
      const page = items.slice(0, limit);
      return { items: page, nextCursor: hasMore ? page.at(-1)!.id : null };
    },
    async invite(roomId: string, userId: string) {
      const id = randomUUID();
      const token = createToken();
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        requireOwner(room, userId);
        requireOpen(room);
        await tx.insertInvite(id, roomId, hashToken(token), userId);
      });
      const invite = await repo.inviteByHash(hashToken(token));
      return { id, token, expiresAt: invite!.expiresAt, maxUses: 1 };
    },
    async join(userId: string, token: string) {
      const hash = hashToken(token);
      const existing = await repo.inviteByHash(hash);
      if (!existing) throw new ApiError(404, 'INVITE_NOT_FOUND', 'Invite not found');
      const roomId = existing.roomId;
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        // 所有入房/退出/移除/关闭共用同一房间行锁；先读锁再读取持久席位。
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        requireOpen(room);
        const members = await tx.members(roomId);
        if (members.some((m) => m.userId === userId)) return;
        const invite = await tx.inviteByHash(hash, true);
        if (!invite || invite.revokedAt || invite.expiresAt.getTime() <= Date.now() || invite.usedCount >= invite.maxUses) {
          throw new ApiError(409, 'INVITE_UNAVAILABLE', 'Invite expired, revoked or already used');
        }
        const seat = nextSeat(members.map((m) => m.seatNo));
        await tx.addMember(roomId, userId, seat, invite.id);
      });
      return view(roomId, userId);
    },
    async revokeInvite(roomId: string, userId: string, inviteId: string) {
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        requireOwner(room, userId);
        if (!await tx.revokeInvite(roomId, inviteId)) throw new ApiError(404, 'INVITE_NOT_FOUND', 'Invite not found');
      });
    },
    async close(roomId: string, userId: string) {
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        requireOwner(room, userId);
        await tx.close(roomId);
      });
    },
    async leave(roomId: string, userId: string) {
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        assertOwnerMayLeave(room.ownerUserId, userId);
        await tx.remove(roomId, userId);
      });
    },
    async remove(roomId: string, ownerId: string, userId: string) {
      await db.transaction(async (sql) => {
        const tx = roomRepository(sql);
        const room = await tx.room(roomId, true);
        if (!room) throw notFound();
        requireOwner(room, ownerId);
        requireOpen(room);
        assertOwnerMayLeave(room.ownerUserId, userId);
        await tx.remove(roomId, userId);
      });
    },
  };
}

export type RoomService = ReturnType<typeof createRoomService>;
