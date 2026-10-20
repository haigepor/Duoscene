import assert from 'node:assert/strict';
import { test } from 'node:test';
import { nextSeat, assertOwnerMayLeave } from '../src/modules/rooms/policy.ts';

test('persistent seats are not released by offline presence', () => {
  assert.equal(nextSeat([1]), 2);
  assert.equal(nextSeat([2]), 1);
  assert.throws(() => nextSeat([1, 2]), /ROOM_FULL/);
});

test('owner must explicitly close the room instead of silently transferring ownership', () => {
  assert.throws(() => assertOwnerMayLeave('owner', 'owner'), /OWNER_MUST_CLOSE/);
  assert.doesNotThrow(() => assertOwnerMayLeave('owner', 'peer'));
});
