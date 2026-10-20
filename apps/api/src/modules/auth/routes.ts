import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { AuthService, Identity, LoginInput } from './service.ts';
import { ApiError } from '../../shared/errors.ts';
import { success } from '../../shared/response.ts';
import { contract, responseContract } from '../../shared/contracts.ts';

export async function identify(request: FastifyRequest, auth: AuthService): Promise<Identity> {
  const header = request.headers.authorization;
  if (!header || !/^Bearer [A-Za-z0-9_-]{43}$/.test(header)) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required');
  return auth.authenticate(header.slice(7));
}

export async function authRoutes(app: FastifyInstance, auth: AuthService) {
  const limits = { rateLimit: { max: 10, timeWindow: '1 minute' } };
  app.post<{ Body: { username: string; displayName: string; password: string } }>('/api/v1/auth/register', {
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
    schema: { body: contract('register'), response: { 201: responseContract('registration') } },
  }, async (request, reply) => reply.code(201).send(success(await auth.register(request.body), request.id)));
  app.post<{ Body: { username: string; recoveryCode: string; password: string } }>('/api/v1/auth/recover', {
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
    schema: { body: contract('recover'), response: { 200: responseContract('recovery') } },
  }, async request => success(await auth.recover(request.body), request.id));
  app.post<{ Body: LoginInput }>('/api/v1/auth/login', {
    config: limits, schema: { body: contract('login'), response: { 200: responseContract('credentials') } },
  }, async (request) => success(await auth.login(request.body), request.id));

  app.post<{ Body: { refreshToken: string } }>('/api/v1/auth/refresh', {
    config: limits, schema: { body: contract('refresh'), response: { 200: responseContract('credentials') } },
  }, async (request) => success(await auth.refresh(request.body.refreshToken), request.id));

  app.get('/api/v1/auth/me', {
    schema: { response: { 200: responseContract('user') } },
  }, async (request) => {
    const user = await identify(request, auth);
    return success({ id: user.id, username: user.username, displayName: user.displayName }, request.id);
  });
  app.post('/api/v1/auth/logout', {
    schema: { response: { 200: responseContract('ok') } },
  }, async (request) => {
    await auth.logout(await identify(request, auth));
    return success({ ok: true }, request.id);
  });
}
