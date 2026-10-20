import assert from 'node:assert/strict';
import { test } from 'node:test';
import { RoomTimeline, validateCommand } from '../src/modules/realtime/timeline.ts';

test('timeline fences stale readiness and preserves manual pause after readiness/reconnect', () => {
  let now = 1000;
  const timeline = new RoomTimeline(() => now);
  timeline.connect('a'); timeline.connect('b');
  const command = (type: string, extra = {}) => ({ type, commandId: crypto.randomUUID(), epoch: timeline.epoch, expectedRevision: timeline.revision, ...extra });
  timeline.command('a', command('media', { media: { uri: 'https://example.com/a.mp4', identity: 'a', title: 'a', hls: false } }));
  const generation = timeline.generation;
  timeline.ready('a', generation, true); timeline.ready('b', generation, true);
  const play = command('play'); timeline.command('a', play); now += 500;
  assert.equal(timeline.snapshot().positionMs, 500);
  timeline.command('a', play); // 去重先于旧 revision 冲突。
  timeline.command('b', command('pause'));
  timeline.disconnect('b'); timeline.connect('b'); timeline.ready('b', generation, true);
  assert.equal(timeline.snapshot().playing, false);
  timeline.command('a', command('seek', { positionMs: 5000 }));
  timeline.ready('b', generation, true);
  assert.equal(timeline.snapshot().playing, false);
  assert.equal(timeline.snapshot().generation, generation + 1);
  assert.throws(() => timeline.command('a', { ...command('play'), expectedRevision: 0 }), /CONFLICT/);
  assert.throws(() => timeline.command('a', { ...command('play'), epoch: 'old' }), /EPOCH/);
});

test('commands reject extra fields, invalid media, unbounded payload and stale epochs', () => {
  assert.equal(validateCommand({ type: 'play', commandId: 'x', epoch: 'e', expectedRevision: 1, admin: true }), false);
  assert.equal(validateCommand({ type: 'media', commandId: 'x', epoch: 'e', expectedRevision: 1, media: { uri: 'file:///secret', identity: 'a', title: 'a', hls: false } }), false);
  assert.equal(validateCommand({ type: 'rate', commandId: 'x', epoch: 'e', expectedRevision: 1, rate: -1 }), false);
});
