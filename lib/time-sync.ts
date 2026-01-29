/**
 * Estimates server time offset by pinging /api/time and measuring RTT.
 * serverTime ≈ clientTime + offset (so offset = serverTime - clientTime at round-trip midpoint).
 */

const TIME_API = '/api/time'
const DEFAULT_OFFSET = 0

let cachedOffset: number = DEFAULT_OFFSET
let lastSyncAt = 0
const SYNC_INTERVAL_MS = 30_000

export function getTimeSyncOffset(): number {
  return cachedOffset
}

/** Get current estimated server time (ms). */
export function getServerTimeMs(): number {
  return Date.now() + cachedOffset
}

/**
 * Ping the time API and update cached offset.
 * Uses single round-trip: offset = serverTime - clientTime (at receive time).
 * For better accuracy you could do multiple samples and use median; single sample is fine for MVP.
 */
export async function syncTime(): Promise<number> {
  const t0 = Date.now()
  try {
    const res = await fetch(TIME_API, { cache: 'no-store' })
    if (!res.ok) return cachedOffset
    const data = await res.json()
    const serverTime = data.now as number
    const t1 = Date.now()
    const rtt = t1 - t0
    const clientTimeAtReceive = t0 + rtt / 2
    cachedOffset = serverTime - clientTimeAtReceive
    lastSyncAt = t1
    return cachedOffset
  } catch {
    return cachedOffset
  }
}

/** Sync if stale (older than SYNC_INTERVAL_MS). */
export async function ensureTimeSynced(): Promise<number> {
  if (Date.now() - lastSyncAt > SYNC_INTERVAL_MS) {
    return syncTime()
  }
  return cachedOffset
}
