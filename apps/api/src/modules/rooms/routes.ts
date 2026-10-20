import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { AuthService } from '../auth/service.ts';
import { identify } from '../auth/routes.ts';
import type { RoomService } from './service.ts';
import { contract, responseContract } from '../../shared/contracts.ts';
import { success } from '../../shared/response.ts';

type Params = { roomId: string };

export async function roomRoutes(app: FastifyInstance, auth: AuthService, rooms: RoomService, reconcile?: (roomId: string) => Promise<void>) {
  // preValidation 在业务 schema 校验前拒绝未授权请求；身份仅保留在本次请求的 WeakMap 中。
  const identities = new WeakMap<FastifyRequest, string>();
  app.addHook('preValidation', async (request) => { identities.set(request, (await identify(request, auth)).id); });
  const user = (request: FastifyRequest) => identities.get(request)!;

  app.post<{ Body: { name: string } }>('/api/v1/rooms', {
    schema: { body: contract('createRoom'), response: { 201: responseContract('room') } },
  }, async (request, reply) => reply.code(201).send(success(await rooms.create(user(request), request.body.name.trim()), request.id)));

  app.get<{ Querystring: { after?: string; limit?: string } }>('/api/v1/rooms', {
    schema: { querystring: contract('roomListQuery'), response: { 200: responseContract('roomList') } },
  }, async (request) => success(await rooms.list(user(request), request.query.after ?? '', Number(request.query.limit ?? '20')), request.id));

  app.post<{ Body: { token: string } }>('/api/v1/rooms/join', {
    schema: { body: contract('joinRoom'), response: { 200: responseContract('room') } },
  }, async (request) => {
    const room = await rooms.join(user(request), request.body.token);
    await reconcile?.(room.id);
    return success(room, request.id);
  });

  app.get<{ Params: Params }>('/api/v1/rooms/:roomId', {
    schema: { params: contract('roomParams'), response: { 200: responseContract('room') } },
  }, async (request) => success(await rooms.get(request.params.roomId, user(request)), request.id));

  app.post<{ Params: Params }>('/api/v1/rooms/:roomId/invites', {
    schema: { params: contract('roomParams'), response: { 201: responseContract('invite') } },
  }, async (request, reply) => reply.code(201).send(success(await rooms.invite(request.params.roomId, user(request)), request.id)));

  app.delete<{ Params: Params & { inviteId: string } }>('/api/v1/rooms/:roomId/invites/:inviteId', {
    schema: { params: contract('inviteParams'), response: { 200: responseContract('ok') } },
  }, async (request) => {
    await rooms.revokeInvite(request.params.roomId, user(request), request.params.inviteId);
    return success({ ok: true }, request.id);
  });

  app.post<{ Params: Params }>('/api/v1/rooms/:roomId/close', {
    schema: { params: contract('roomParams'), response: { 200: responseContract('ok') } },
  }, async (request) => {
    await rooms.close(request.params.roomId, user(request));
    await reconcile?.(request.params.roomId);
    return success({ ok: true }, request.id);
  });

  app.post<{ Params: Params }>('/api/v1/rooms/:roomId/leave', {
    schema: { params: contract('roomParams'), response: { 200: responseContract('ok') } },
  }, async (request) => {
    await rooms.leave(request.params.roomId, user(request));
    await reconcile?.(request.params.roomId);
    return success({ ok: true }, request.id);
  });

  app.delete<{ Params: Params & { userId: string } }>('/api/v1/rooms/:roomId/members/:userId', {
    schema: { params: contract('memberParams'), response: { 200: responseContract('ok') } },
  }, async (request) => {
    await rooms.remove(request.params.roomId, user(request), request.params.userId);
    await reconcile?.(request.params.roomId);
    return success({ ok: true }, request.id);
  });
}
