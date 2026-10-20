/** UTC 基点只采样一次；间隔使用单调时钟，避免系统校时造成房间时间回退。 */
export function createServerClock(
  utcNow: () => number = Date.now,
  monotonicNow: () => number = () => performance.now(),
): () => number {
  const utcBase = utcNow();
  const monotonicBase = monotonicNow();
  return () => utcBase + monotonicNow() - monotonicBase;
}
