import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import Ajv from 'ajv';

async function json(path) {
  return JSON.parse(await readFile(new URL(path, import.meta.url), 'utf8'));
}

for (const kind of ['health', 'error']) {
  test(`${kind} schema accepts valid fixture and rejects invalid fixture`, async () => {
    const validate = new Ajv({ strict: true }).compile(
      await json(`../openapi/${kind}-response.schema.json`),
    );
    assert.equal(validate(await json(`../fixtures/${kind}.valid.json`)), true);
    assert.equal(validate(await json(`../fixtures/${kind}.invalid.json`)), false);
  });
}

test('business contracts reject extra request properties and non-string credentials', async () => {
  const ajv = new Ajv({ strict: true });
  ajv.addSchema(await json('../openapi/api-v1.schema.json'));
  const login = ajv.compile({ $ref: 'urn:duoscene:api:v1#/definitions/login' });
  assert.equal(login(await json('../fixtures/login.valid.json')), true);
  assert.equal(login(await json('../fixtures/login.invalid.json')), false);
  const join = ajv.compile({ $ref: 'urn:duoscene:api:v1#/definitions/joinRoom' });
  assert.equal(join(await json('../fixtures/join.valid.json')), true);
  assert.equal(join(await json('../fixtures/join.invalid.json')), false);
});

test('room media accepts provider selections and preserves legacy URL commands', async () => {
  const validate = new Ajv({ strict: true }).compile(await json('../websocket/commands.schema.json'));
  assert.equal(validate(await json('../fixtures/media-provider.valid.json')), true);
  assert.equal(validate(await json('../fixtures/media-url.valid.json')), true);
  assert.equal(validate(await json('../fixtures/media-provider.invalid.json')), false);
});

test('room handoff rejects invalid episodes, offsets and private transport data', async () => {
  const validate = new Ajv({ strict: true }).compile(await json('../websocket/commands.schema.json'));
  const valid = await json('../fixtures/media-provider.valid.json');
  for (const media of [
    { ...valid.media, episode: 0 },
    { ...valid.media, episode: 1.5 },
    { ...valid.media, filmId: 'whisklet:0' },
    { ...valid.media, filmId: 'whisklet:0123' },
    { ...valid.media, filmId: `whisklet:${'1'.repeat(81)}` },
    { ...valid.media, provider: 'unknown' },
    { ...valid.media, lineCode: '' },
    { ...valid.media, lineCode: 'with space' },
    { ...valid.media, lineCode: '\u0000' },
    { ...valid.media, lineCode: '\u007f' },
    { ...valid.media, headers: { authorization: 'private' } },
    { ...valid.media, uri: 'https://example.invalid/private.mp4' },
  ]) assert.equal(validate({ ...valid, media }), false);
  for (const positionMs of [-1, 86400001, 1.5, '1000']) {
    assert.equal(validate({ ...valid, positionMs }), false);
  }
  assert.equal(validate({ ...valid, type: 'play' }), false);
});

test('published WebSocket command schemas match the server validators', async () => {
  const { commandSchemas } = await import('../../../apps/api/src/modules/realtime/timeline.ts');
  const published = await json('../websocket/commands.schema.json');
  assert.deepEqual(published.definitions, commandSchemas);
});
