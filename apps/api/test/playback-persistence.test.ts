import assert from 'node:assert/strict';
import { test } from 'node:test';
import { RoomTimeline } from '../src/modules/realtime/timeline.ts';
import { RoomPlayback } from '../src/modules/realtime/playback.ts';

const media = { uri: 'https://example.com/video.mp4', identity: 'video', title: 'Video', hls: false };
type Snapshot = ReturnType<RoomTimeline['snapshot']>;

function playingTimeline(now: () => number) {
  const timeline = new RoomTimeline(now);
  timeline.connect('a'); timeline.connect('b');
  timeline.command('a', { type: 'media', commandId: 'media', epoch: timeline.epoch, expectedRevision: timeline.revision, media });
  timeline.ready('a', timeline.generation, true); timeline.ready('b', timeline.generation, true);
  timeline.command('a', { type: 'play', commandId: 'play', epoch: timeline.epoch, expectedRevision: timeline.revision });
  return timeline;
}

test('a pending or failed command never changes the published timeline and can be retried', async () => {
  let finish!: (value?: unknown) => void, fail!: (error: Error) => void;
  let stored!: Snapshot;
  const timeline = playingTimeline(() => 1000);
  let rejectWrite = true;
  const playback = new RoomPlayback(timeline, async value => {
    stored = value;
    if (rejectWrite) await new Promise((resolve, reject) => { finish = resolve; fail = reject; });
  }, () => 1000);
  const before = playback.timeline.snapshot();
  const command = { type: 'seek', commandId: 'retry-seek', epoch: timeline.epoch, expectedRevision: timeline.revision, positionMs: 9000 };
  const pending = playback.command('a', command);
  assert.equal(stored.positionMs, 9000);
  assert.deepEqual(playback.timeline.snapshot(), before);
  fail(Error('database offline'));
  await assert.rejects(pending, /database offline/);
  assert.deepEqual(playback.timeline.snapshot(), before);
  rejectWrite = false;
  await playback.command('a', command);
  assert.equal(playback.timeline.snapshot().positionMs, 9000);
  assert.equal(playback.timeline.revision, before.revision + 1);
  assert.equal(typeof finish, 'function');
});

test('successful persistence publishes the candidate while retaining its epoch and command deduplication', async () => {
  let release!: () => void;
  const timeline = playingTimeline(() => 1000);
  const playback = new RoomPlayback(timeline, async () => { await new Promise<void>(resolve => { release = resolve; }); }, () => 1000);
  const command = { type: 'pause', commandId: 'pause-once', epoch: timeline.epoch, expectedRevision: timeline.revision };
  const pending = playback.command('a', command);
  assert.equal(playback.timeline.snapshot().playing, true);
  release(); await pending;
  assert.equal(playback.timeline.snapshot().playing, false);
  assert.equal(playback.timeline.epoch, timeline.epoch);
  const revision = playback.timeline.revision;
  const retry = playback.command('a', command); release(); await retry;
  assert.equal(playback.timeline.revision, revision);
});

test('bounded checkpoints save natural progress and recovery starts paused in a new epoch', async () => {
  let now = 1000;
  let saved!: Snapshot;
  let writes = 0;
  const playback = new RoomPlayback(playingTimeline(() => now), async value => { saved = value; writes++; }, () => now);
  now += 4999; await playback.checkpoint(); assert.equal(writes, 0);
  now += 1; await playback.checkpoint(); assert.equal(writes, 1); assert.equal(saved.positionMs, 5000);
  now += 2000; playback.disconnect('b'); await playback.checkpoint(true);
  assert.equal(saved.positionMs, 7000); assert.equal(saved.playing, false);
  const recovered = new RoomTimeline(() => now); recovered.restore(saved);
  assert.notEqual(recovered.epoch, playback.timeline.epoch);
  assert.equal(recovered.snapshot().positionMs, 7000);
  assert.equal(recovered.snapshot().playing, false);
  assert.equal(recovered.snapshot().wanted, false);
});

test('failed checkpoints remain dirty and retry the current state instead of overwriting a newer command', async () => {
  let now = 1000, fail = true;
  const saved: Snapshot[] = [];
  const playback = new RoomPlayback(playingTimeline(() => now), async value => {
    if (fail) throw Error('write failed');
    saved.push(value);
  }, () => now);
  now += 7000; playback.disconnect('b');
  await assert.rejects(playback.checkpoint(true), /write failed/);
  assert.equal(playback.dirty, true);
  assert.equal(playback.checkpointDue, false);
  now += 5000; assert.equal(playback.checkpointDue, true);
  fail = false;
  await playback.command('a', { type: 'seek', commandId: 'new-seek', epoch: playback.timeline.epoch, expectedRevision: playback.timeline.revision, positionMs: 20000 });
  assert.equal(playback.dirty, false);
  now += 5000; await playback.checkpoint();
  assert.equal(saved.length, 1);
  assert.equal(saved[0]!.positionMs, 20000);
});
