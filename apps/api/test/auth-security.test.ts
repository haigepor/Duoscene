import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hashPassword, verifyPassword, createToken, hashToken, normalizeUsername } from '../src/modules/auth/security.ts';

test('password hash is salted and verifies only the original password', async () => {
  const first = await hashPassword('correct horse battery staple');
  const second = await hashPassword('correct horse battery staple');
  assert.notEqual(first, second);
  assert.ok(!first.includes('correct horse'));
  assert.equal(await verifyPassword('correct horse battery staple', first), true);
  assert.equal(await verifyPassword('wrong-password', first), false);
  assert.equal(await verifyPassword('irrelevant', 'malformed'), false);
});

test('private account policy rejects weak passwords and normalizes ASCII usernames', async () => {
  await assert.rejects(hashPassword('short'));
  await assert.rejects(hashPassword('x'.repeat(129)));
  assert.equal(normalizeUsername('Alice_01'), 'alice_01');
  for (const name of ['a', 'with space', '\u4e2d\u6587', 'x'.repeat(33)]) {
    assert.throws(() => normalizeUsername(name));
  }
});

test('tokens have 256 bits of randomness and only hashes are persisted', () => {
  const token = createToken();
  assert.match(token, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(token, createToken());
  assert.match(hashToken(token), /^[a-f0-9]{64}$/);
  assert.equal(hashToken(token), hashToken(token));
});
