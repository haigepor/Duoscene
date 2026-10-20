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
