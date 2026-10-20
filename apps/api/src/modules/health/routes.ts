import type { FastifyInstance } from 'fastify';
import type { ProbeDatabase } from '../../plugins/database.ts';
import { failure, success } from '../../shared/response.ts';

export async function healthRoutes(app: FastifyInstance, probeDatabase: ProbeDatabase) {
  app.get('/health/live', async (request) => success({ status: 'alive' }, request.id));
  app.get('/health/ready', async (request, reply) => {
    const status = await probeDatabase();
    if (status === 'ready') return success({ status: 'ready' }, request.id);
    return reply.code(503).send(failure(
      status === 'disabled' ? 'DATABASE_NOT_CONFIGURED' : 'DATABASE_UNAVAILABLE',
      'Service is not ready',
      request.id,
    ));
  });
}
