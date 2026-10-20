import { randomUUID } from 'node:crypto';
import { Ajv } from 'ajv';

export type Media = { uri: string; identity: string; title: string; hls: boolean };
export type Command = { type: string; commandId: string; epoch: string; expectedRevision: number; media?: Media; positionMs?: number; rate?: number };
const text = (maxLength: number) => ({ type: 'string', minLength: 1, maxLength });
const common = { commandId: text(80), epoch: text(80), expectedRevision: { type: 'integer', minimum: 0 } };
export const commandSchemas = Object.fromEntries(['play', 'pause', 'seek', 'rate', 'media'].map(type => {
  const extra = type === 'seek' ? { positionMs: { type: 'integer', minimum: 0, maximum: 86400000 } }
    : type === 'rate' ? { rate: { type: 'number', minimum: .25, maximum: 8 } }
    : type === 'media' ? { media: { type: 'object', additionalProperties: false, required: ['uri', 'identity', 'title', 'hls'], properties: { uri: text(4096), identity: text(1024), title: text(160), hls: { type: 'boolean' } } } } : {};
  return [type, { type: 'object', additionalProperties: false, required: ['type', ...Object.keys(common), ...Object.keys(extra)], properties: { type: { const: type }, ...common, ...extra } }];
}));
const ajv = new Ajv({ strict: false });
const validators = Object.fromEntries(Object.entries(commandSchemas).map(([key, schema]) => [key, ajv.compile(schema)]));
export function validateCommand(value: unknown): value is Command {
  if (!value || typeof value !== 'object' || !('type' in value) || typeof value.type !== 'string' || !validators[value.type]?.(value)) return false;
  if (value.type === 'media') {
    try {
      const uri = new URL((value as Command).media!.uri);
      if (!['http:', 'https:'].includes(uri.protocol) || uri.username || uri.password || uri.hash) return false;
    } catch { return false; }
  }
  return true;
}

export class RoomTimeline {
  readonly epoch = randomUUID();
  revision = 0;
  generation = 0;
  media: Media | null = null;
  rate = 1;
  wanted = false;
  private position = 0;
  private anchor = 0;
  private readonly peers = new Map<string, boolean>();
  private readonly seen = new Set<string>();
  private readonly now: () => number;
  constructor(now: () => number = () => performance.timeOrigin + performance.now()) { this.now = now; this.anchor = now(); }
  private get playing() { return this.wanted && this.media !== null && this.peers.size === 2 && [...this.peers.values()].every(Boolean); }
  private freeze() { this.position = this.snapshot().positionMs; this.anchor = this.now(); }
  snapshot() { return { epoch: this.epoch, revision: this.revision, generation: this.generation, media: this.media, rate: this.rate, playing: this.playing, wanted: this.wanted, positionMs: Math.min(86400000, Math.round(this.position + (this.playing ? (this.now() - this.anchor) * this.rate : 0))), serverTime: this.now(), ready: Object.fromEntries(this.peers) }; }
  connect(userId: string) { this.freeze(); this.peers.set(userId, false); this.revision++; }
  disconnect(userId: string) { this.freeze(); this.peers.delete(userId); this.wanted = false; this.revision++; }
  ready(userId: string, generation: number, ready: boolean) {
    if (generation !== this.generation || !this.peers.has(userId) || this.peers.get(userId) === ready) return;
    this.freeze(); this.peers.set(userId, ready); this.revision++;
  }
  restore(value: { media?: Media | null; positionMs?: number; rate?: number }) {
    if (value.media && validateCommand({ type: 'media', commandId: 'restore', epoch: this.epoch, expectedRevision: 0, media: value.media })) this.media = value.media;
    this.position = Math.max(0, Math.min(86400000, Number(value.positionMs) || 0));
    this.rate = Number(value.rate) >= .25 && Number(value.rate) <= 8 ? Number(value.rate) : 1;
  }
  command(userId: string, command: Command) {
    if (!this.peers.has(userId)) throw Error('NOT_CONNECTED');
    if (command.epoch !== this.epoch) throw Error('EPOCH_CHANGED');
    const key = `${userId}:${command.commandId}`;
    // 同一命令的重发先去重，再检查 revision，不能重复 seek 或换片。
    if (this.seen.has(key)) return this.snapshot();
    if (command.expectedRevision !== this.revision) throw Error('REVISION_CONFLICT');
    if (command.type !== 'media' && !this.media) throw Error('NO_MEDIA');
    this.freeze();
    switch (command.type) {
      case 'media': this.media = command.media!; this.position = 0; this.wanted = false; this.invalidate(); break;
      case 'seek': this.position = command.positionMs!; this.invalidate(); break;
      case 'rate': this.rate = command.rate!; break;
      case 'play': this.wanted = true; break;
      case 'pause': this.wanted = false; break;
      default: throw Error('INVALID_COMMAND');
    }
    this.seen.add(key);
    if (this.seen.size > 512) this.seen.delete(this.seen.values().next().value!);
    this.revision++;
    return this.snapshot();
  }
  private invalidate() { this.generation++; for (const id of this.peers.keys()) this.peers.set(id, false); }
}
