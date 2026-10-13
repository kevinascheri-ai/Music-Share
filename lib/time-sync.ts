/**
 * Estimates the offset between this device's clock and the server's, so every
 * listener computes song positions against the same clock.
 * serverTime ≈ Date.now() + offset
 */

const TIME_API = '/api/time'
const SAMPLES = 4
const RESYNC_MS = 5 * 60_000

let cachedOffset = 0
let lastSyncAt = 0
let inflight: Promise<number> | null = null

/** Current estimated server time (ms). */
export function getServerTimeMs(): number {
  return Date.now() + cachedOffset
}

async function sample(): Promise<{ offset: number; rtt: number } | null> {
  const t0 = Date.now()
  try {
    const res = await fetch(TIME_API, { cache: 'no-store' })
    if (!res.ok) return null
    const { now } = (await res.json()) as { now: number }
    const t1 = Date.now()
    if (typeof now !== 'number') return null
    return { offset: now - (t0 + (t1 - t0) / 2), rtt: t1 - t0 }
  } catch {
    return null
  }
}

/** Take a few samples and keep the one with the lowest round trip (least error). */
export async function syncTime(): Promise<number> {
  let best: { offset: number; rtt: number } | null = null
  for (let i = 0; i < SAMPLES; i++) {
    const s = await sample()
    if (s && (!best || s.rtt < best.rtt)) best = s
  }
  if (best) {
    cachedOffset = best.offset
    lastSyncAt = Date.now()
  }
  return cachedOffset
}

/** Sync if we never have, or the last sync is stale. Concurrent callers share one sync. */
export function ensureTimeSynced(): Promise<number> {
  if (lastSyncAt && Date.now() - lastSyncAt < RESYNC_MS) return Promise.resolve(cachedOffset)
  if (!inflight) inflight = syncTime().finally(() => (inflight = null))
  return inflight
}
