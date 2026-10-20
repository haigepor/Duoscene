import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServerClock } from '../src/shared/clock.ts';

test('wall clock changes do not affect elapsed room time', () => {
  let utc = 1_000_000;
  let monotonic = 100;
  const now = createServerClock(() => utc, () => monotonic);
  assert.equal(now(), 1_000_000);
  utc -= 60_000;
  monotonic += 125;
  assert.equal(now(), 1_000_125);
  utc += 120_000;
  monotonic += 10;
  assert.equal(now(), 1_000_135);
});
