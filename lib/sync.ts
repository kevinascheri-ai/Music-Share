import type { RoomState, Track } from '@/lib/supabase'

/**
 * The shared playback state for a room. Every control action produces a new
 * snapshot and broadcasts it in full, so applying one is idempotent.
 *
 * Position is stored as "positionSec at anchorMs" (server-clock ms), so each
 * listener can compute where the song should be *right now* regardless of how
 * long the message took to arrive.
 */
export type SyncState = {
  trackId: string | null
  isPlaying: boolean
  positionSec: number
  anchorMs: number
  /** Lamport counter: a new action always gets max(seen) + 1. */
  seq: number
  /** Client that produced this state; breaks ties between equal seqs. */
  origin: string
}

export type SyncAction = 'play' | 'pause' | 'seek' | 'next' | 'previous' | 'select' | 'auto' | 'stop'

export type RoomMessage =
  | { type: 'state'; state: SyncState; action?: SyncAction; by?: string; reply?: boolean }
  | { type: 'hello'; from: string; state?: SyncState }
  | { type: 'queue'; from: string; by?: string; note?: string }

/** Where the song should be at server time `nowMs`. */
export function positionAt(state: SyncState, nowMs: number): number {
  if (!state.isPlaying) return Math.max(0, state.positionSec)
  return Math.max(0, state.positionSec + (nowMs - state.anchorMs) / 1000)
}

/**
 * Total order over states so every client converges on the same one when two
 * people press buttons at the same moment.
 */
export function isNewer(candidate: SyncState, current: SyncState | null): boolean {
  if (!current) return true
  if (candidate.seq !== current.seq) return candidate.seq > current.seq
  return candidate.origin > current.origin
}

/** States loaded from the database carry seq 0 so any live state beats them. */
export function stateFromRow(row: RoomState): SyncState {
  const anchor = Date.parse(row.updated_at)
  return {
    trackId: row.current_track_id,
    isPlaying: !!row.is_playing && !!row.current_track_id,
    positionSec: Number(row.current_time_sec) || 0,
    anchorMs: Number.isFinite(anchor) ? anchor : Date.now(),
    seq: 0,
    origin: '',
  }
}

/** Next track in queue order, wrapping to the start so the jam keeps going. */
export function nextTrackId(tracks: Track[], currentId: string | null): string | null {
  if (!tracks.length) return null
  const idx = tracks.findIndex((t) => t.id === currentId)
  if (idx < 0) return tracks[0].id
  return tracks[(idx + 1) % tracks.length].id
}

export function previousTrackId(tracks: Track[], currentId: string | null): string | null {
  if (!tracks.length) return null
  const idx = tracks.findIndex((t) => t.id === currentId)
  if (idx <= 0) return tracks[idx < 0 ? 0 : tracks.length - 1].id
  return tracks[idx - 1].id
}

/** Shuffle the queue, keeping the current track first so playback continues from it. */
export function shuffledIds(tracks: Track[], currentId: string | null, random = Math.random): string[] {
  const rest = tracks.map((t) => t.id).filter((id) => id !== currentId)
  for (let i = rest.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[rest[i], rest[j]] = [rest[j], rest[i]]
  }
  return currentId && tracks.some((t) => t.id === currentId) ? [currentId, ...rest] : rest
}

export function formatTime(sec: number): string {
  if (!Number.isFinite(sec) || sec < 0) return '0:00'
  const m = Math.floor(sec / 60)
  const s = Math.floor(sec % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}
