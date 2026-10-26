import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { loadConfig } from './config/env.ts';
import type { AppConfig } from './config/env.ts';
import { attachDatabase } from './plugins/database.ts';
import type { ProbeDatabase } from './plugins/database.ts';
import { healthRoutes } from './modules/health/routes.ts';
import { failure } from './shared/response.ts';
import rateLimit from '@fastify/rate-limit';
import { ApiError } from './shared/errors.ts';
import { apiSchema } from './shared/contracts.ts';
import { createAuthService } from './modules/auth/service.ts';
import type { AuthService } from './modules/auth/service.ts';
import { authRoutes } from './modules/auth/routes.ts';
import { createRoomService } from './modules/rooms/service.ts';
import type { RoomService } from './modules/rooms/service.ts';
import { roomRoutes } from './modules/rooms/routes.ts';
import websocket from '@fastify/websocket';
import { createRealtimeHub } from './modules/realtime/hub.ts';

export interface BuildAppOptions {
  config?: AppConfig;
  probeDatabase?: ProbeDatabase;
  logger?: boolean;
  services?: { auth: AuthService; rooms: RoomService };
}

// Source: https://fastify.dev/docs/latest/Guides/Testing/
export function buildApp(options: BuildAppOptions = {}) {
  const config = options.config ?? loadConfig();
  const app = Fastify({
    logger: options.logger === false ? false : {
      level: config.logLevel,
      // 不记录原始 URL，防止未来 WS 票据或媒体签名串进入访问日志。
      serializers: {
        req(request) { return { method: request.method }; },
      },
      redact: ['req.headers.authorization', 'req.headers.cookie', 'res.headers["set-cookie"]'],
    },
    genReqId: () => randomUUID(),
    requestIdHeader: false,
    bodyLimit: 64 * 1024,
    requestTimeout: 10_000,
    connectionTimeout: 10_000,
    forceCloseConnections: 'idle',
    // 是否信任代理头决定限流键；只有部署在可信反代后才应置 true（env.ts）。
    trustProxy: config.trustProxy,
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false } },
  });
  const database = attachDatabase(app, config.database);
  const probe = options.probeDatabase ?? database.probe;
  const services = options.services ?? (database.database ? {
    auth: createAuthService(database.database), rooms: createRoomService(database.database),
  } : null);
  const realtime = database.database && services ? createRealtimeHub(database.database, services.auth, services.rooms, config) : null;
  app.addSchema(apiSchema);
  // 限流必须在 realtime/业务路由之前注册：插件的 onRoute 钩子只覆盖
  // 注册时已存在的路由，晚注册会让 realtime 票据等路由绕过限流。
  app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
  app.register(websocket, { options: { maxPayload: 24 * 1024 } });
  if (realtime) {
    app.addHook('preClose', async () => { await realtime.close(); });
    app.register(async instance => { await realtime.register(instance); });
  }
  app.addHook('onSend', async (_request, reply) => {
    reply.header('cache-control', 'no-store');
    reply.header('x-content-type-options', 'nosniff');
    reply.header('referrer-policy', 'no-referrer');
  });
  app.setNotFoundHandler((request, reply) => {
    return reply.code(404).send(failure('NOT_FOUND', 'Resource not found', request.id));
  });
  app.setErrorHandler((error: unknown, request, reply) => {
    if (error instanceof ApiError) return reply.code(error.statusCode).send(failure(error.code, error.message, request.id));
    if (typeof error === 'object' && error !== null && 'validation' in error) {
      return reply.code(422).send(failure('VALIDATION_ERROR', 'Invalid request', request.id));
    }
    // 连接池队列打满时 mysql2 抛无 code 的裸错误，映射成 503 让客户端走重试。
    if (error instanceof Error && error.message === 'Queue limit reached.') {
      return reply.code(503).send(failure('DATABASE_UNAVAILABLE', 'Service is busy; retry shortly', request.id));
    }
    if (typeof error === 'object' && error !== null && 'code' in error) {
      const code = error.code;
      if (typeof code === 'string' && ['ECONNREFUSED', 'ETIMEDOUT', 'PROTOCOL_CONNECTION_LOST', 'ER_NO_SUCH_TABLE', 'ER_ACCESS_DENIED_ERROR', 'ER_BAD_DB_ERROR'].includes(code)) {
        return reply.code(503).send(failure('DATABASE_UNAVAILABLE', 'Service is not ready', request.id));
      }
      if (code === 'ER_DUP_ENTRY' || code === 'ER_LOCK_DEADLOCK' || code === 'ER_LOCK_WAIT_TIMEOUT') {
        return reply.code(409).send(failure('RESOURCE_CONFLICT', 'Resource changed; reload and retry', request.id));
      }
    }
    const statusCode = typeof error === 'object' && error !== null &&
      'statusCode' in error && typeof error.statusCode === 'number' ? error.statusCode : 500;
    const status = Number.isInteger(statusCode) && statusCode >= 400 && statusCode < 500
      ? statusCode : 500;
    // 仅保留错误分类，不把 SQL、请求体、连接参数或签名地址写入日志。
    request.log.error({ statusCode: status, requestId: request.id }, 'Request failed');
    return reply.code(status).send(failure(
      status === 429 ? 'RATE_LIMITED' : status === 500 ? 'INTERNAL_ERROR' : 'INVALID_REQUEST',
      status === 500 ? 'Internal server error' : 'Invalid request',
      request.id,
    ));
  });
  app.register(async (instance) => { await healthRoutes(instance, probe); });
  app.register(async (instance) => {
    if (services) {
      await authRoutes(instance, services.auth);
      await instance.register(async (roomApp) => { await roomRoutes(roomApp, services.auth, services.rooms, realtime?.reconcile); });
    } else {
      instance.all('/api/v1/*', async (request, reply) => reply.code(503).send(failure('DATABASE_NOT_CONFIGURED', 'Service is not ready', request.id)));
    }
  });
  return app;
}
