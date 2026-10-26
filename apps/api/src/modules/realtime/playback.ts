import { RoomTimeline } from './timeline.ts';
import type { Command } from './timeline.ts';

type Snapshot = ReturnType<RoomTimeline['snapshot']>;

/** 由房间 actor 串行调用；仅成功落库的控制命令可替换权威时间线。 */
export class RoomPlayback {
  private current: RoomTimeline;
  private needsSave = false;
  private lastAttempt: number;
  private readonly save: (snapshot: Snapshot) => Promise<void>;
  private readonly now: () => number;
  constructor(timeline: RoomTimeline, save: (snapshot: Snapshot) => Promise<void>, now: () => number = Date.now) {
    this.current = timeline; this.save = save; this.now = now; this.lastAttempt = now();
  }
  get timeline() { return this.current; }
  get dirty() { return this.needsSave; }
  get checkpointDue() {
    return (this.needsSave || this.current.snapshot().playing) && this.now() - this.lastAttempt >= 5000;
  }
  connect(userId: string) { this.current.connect(userId); this.needsSave = true; }
  disconnect(userId: string) { this.current.disconnect(userId); this.needsSave = true; }
  ready(userId: string, generation: number, ready: boolean) {
    const revision = this.current.revision;
    this.current.ready(userId, generation, ready);
    if (revision !== this.current.revision) this.needsSave = true;
  }
  async command(userId: string, command: Command) {
    const candidate = this.current.candidate(userId, command);
    await this.save(candidate.snapshot());
    this.current = candidate; this.needsSave = false; this.lastAttempt = this.now();
  }
  async checkpoint(force = false) {
    if (!force && !this.checkpointDue) return;
    const snapshot = this.current.snapshot();
    this.lastAttempt = this.now();
    try {
      // 重试时重新取最新快照；不能缓存失败快照，否则会覆盖后续成功的 seek/换片。
      await this.save(snapshot);
      this.needsSave = this.current.epoch !== snapshot.epoch || this.current.revision !== snapshot.revision;
    } catch (error) { this.needsSave = true; throw error; }
  }
}
