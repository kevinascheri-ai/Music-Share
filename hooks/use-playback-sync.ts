'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { RoomState, Track } from '@/lib/supabase'
import { ensureTimeSynced, getServerTimeMs } from '@/lib/time-sync'
import { getSavedVolume, saveVolume } from '@/lib/client-id'
import {
  isNewer,
  nextTrackId,
  positionAt,
  previousTrackId,
  stateFromRow,
  type RoomMessage,
  type SyncAction,
  type SyncState,
} from '@/lib/sync'
import { useRoomChannel, type Listener } from '@/hooks/use-room-channel'

const TICK_MS = 500
/** Within this, play at normal speed. */
const SOFT_DRIFT_SEC = 0.05
/** Beyond this, jump straight to the right spot instead of speeding up/slowing down. */
const HARD_DRIFT_SEC = 0.75
/** When a new state arrives, seek if we're further off than this. */
const APPLY_SEEK_SEC = 0.25
const HARD_SEEK_COOLDOWN_MS = 2500
const MAX_RATE_NUDGE = 0.08
/** A room left "playing" with nobody in it for this long is paused on rejoin. */
const ORPHAN_AFTER_MS = 10 * 60_000
/** Pressing previous after this many seconds restarts the song instead. */
const RESTART_THRESHOLD_SEC = 3
const MAX_LOAD_RETRIES = 2

// 10ms of silence, used to unlock audio on browsers (iOS) that require a play() inside a tap.
const SILENT_WAV =
  'data:audio/wav;base64,UklGRnQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YVAAAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA=='

export type Activity = {
  by: string
  action: SyncAction | 'queue'
  trackId?: string | null
  positionSec?: number
  note?: string
}

type Options = {
  roomCode: string | null
  clientId: string
  name: string
  tracks: Track[]
  tracksLoaded: boolean
  initialRoomState: RoomState | null
  /** Someone changed the queue (or we're missing a track): refetch it. */
  onQueueChanged: () => void
  /** Something another listener did, for the activity toast. */
  onActivity: (activity: Activity) => void
}

function finiteDuration(audio: HTMLAudioElement | null): number {
  const d = audio?.duration
  return d != null && Number.isFinite(d) && d > 0 ? d : 0
}

export function usePlaybackSync({
  roomCode,
  clientId,
  name,
  tracks,
  tracksLoaded,
  initialRoomState,
  onQueueChanged,
  onActivity,
}: Options) {
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const stateRef = useRef<SyncState | null>(null)
  const [state, setState] = useState<SyncState | null>(null)
  const [needsUnlock, setNeedsUnlockState] = useState(false)
  const [durationSec, setDurationSec] = useState(0)
  const [audioError, setAudioError] = useState<string | null>(null)
  const [volume, setVolumeState] = useState(1)

  // Mutable mirrors so callbacks can stay stable.
  const seqRef = useRef(0)
  const tracksRef = useRef(tracks)
  tracksRef.current = tracks
  const tracksLoadedRef = useRef(tracksLoaded)
  tracksLoadedRef.current = tracksLoaded
  const ctx = useRef({ roomCode, clientId, name, onQueueChanged, onActivity })
  ctx.current = { roomCode, clientId, name, onQueueChanged, onActivity }
  const loadedTrackIdRef = useRef<string | null>(null)
  const loadRetriesRef = useRef<{ trackId: string | null; count: number }>({ trackId: null, count: 0 })
  const lastHardSeekRef = useRef(0)
  const missingTrackRefetchRef = useRef<string | null>(null)
  const needsUnlockRef = useRef(false)
  const presenceRef = useRef<{ synced: boolean; others: number }>({ synced: false, others: 0 })
  const orphanCheckedRef = useRef(false)
  const sendRef = useRef<(msg: RoomMessage) => void>(() => {})

  const setNeedsUnlock = useCallback((v: boolean) => {
    needsUnlockRef.current = v
    setNeedsUnlockState(v)
  }, [])

  // ---------------------------------------------------------------------------
  // Driving the audio element toward the shared state
  // ---------------------------------------------------------------------------

  const playAudio = useCallback(() => {
    const audio = audioRef.current
    if (!audio) return
    audio
      .play()
      .then(() => setNeedsUnlock(false))
      .catch((err: unknown) => {
        if (err instanceof Error && err.name === 'NotAllowedError') setNeedsUnlock(true)
      })
  }, [setNeedsUnlock])

  /** Where the shared timeline is right now, clamped to the song length once known. */
  const sharedPosition = useCallback((): number => {
    const s = stateRef.current
    if (!s) return 0
    const pos = positionAt(s, getServerTimeMs())
    const dur = loadedTrackIdRef.current === s.trackId ? finiteDuration(audioRef.current) : 0
    return dur ? Math.min(pos, dur) : pos
  }, [])

  const reconcile = useCallback(() => {
    const audio = audioRef.current
    const s = stateRef.current
    if (!audio || !s) return

    if (!s.trackId) {
      if (loadedTrackIdRef.current) {
        audio.pause()
        audio.removeAttribute('src')
        audio.load()
        loadedTrackIdRef.current = null
        setDurationSec(0)
      }
      return
    }

    const track = tracksRef.current.find((t) => t.id === s.trackId)
    if (!track) {
      // Probably just added by someone else: refetch the queue once for this id.
      if (tracksLoadedRef.current && missingTrackRefetchRef.current !== s.trackId) {
        missingTrackRefetchRef.current = s.trackId
        ctx.current.onQueueChanged()
      }
      return
    }

    // (Re)load on a song change, or retry a song that failed to load.
    if (loadedTrackIdRef.current !== track.id || (audio.error && s.isPlaying)) {
      audio.src = track.url
      audio.playbackRate = 1
      loadedTrackIdRef.current = track.id
      setDurationSec(0)
      setAudioError(null)
    }

    const target = sharedPosition()
    if (Math.abs(audio.currentTime - target) > (s.isPlaying ? APPLY_SEEK_SEC : 0.05)) {
      audio.currentTime = target
    }
    if (s.isPlaying) {
      if (audio.paused && !audio.error) playAudio()
    } else {
      audio.playbackRate = 1
      if (!audio.paused) audio.pause()
    }
  }, [playAudio, sharedPosition])

  /** Save the state so people who join later (or an empty room) pick it up. Writes go out in order. */
  const persistChainRef = useRef<Promise<void>>(Promise.resolve())
  const persist = useCallback((s: SyncState) => {
    persistChainRef.current = persistChainRef.current.then(async () => {
      const code = ctx.current.roomCode
      if (!code) return
      const { error } = await supabase.from('room_state').upsert({
        room_code: code,
        current_track_id: s.trackId,
        is_playing: s.isPlaying,
        current_time_sec: Math.round(s.positionSec * 1000) / 1000,
        updated_at: new Date(s.anchorMs).toISOString(),
      })
      if (error) console.error('Failed to save room state:', error.message)
    })
  }, [])

  /** Take a state if it's newer than ours (or forced, for our own actions). */
  const adopt = useCallback(
    (next: SyncState, force = false): boolean => {
      seqRef.current = Math.max(seqRef.current, next.seq)
      const prev = stateRef.current
      if (!force && !isNewer(next, prev)) return false
      stateRef.current = next
      setState(next)
      reconcile()
      // Our own action just lost a tie with someone else's: our save may have
      // landed after theirs, so save the winner to keep the database in step.
      if (!force && prev?.origin === ctx.current.clientId && next.origin !== ctx.current.clientId) persist(next)
      return true
    },
    [reconcile, persist]
  )

  /** Apply one of our own actions locally, tell everyone, and save it for late joiners. */
  const commit = useCallback(
    (next: Pick<SyncState, 'trackId' | 'isPlaying' | 'positionSec'>, action: SyncAction) => {
      const s: SyncState = {
        trackId: next.trackId,
        isPlaying: next.isPlaying && !!next.trackId,
        positionSec: Math.max(0, next.positionSec),
        anchorMs: getServerTimeMs(),
        seq: seqRef.current + 1,
        origin: ctx.current.clientId,
      }
      adopt(s, true)
      sendRef.current({ type: 'state', state: s, action, by: ctx.current.name })
      persist(s)
    },
    [adopt, persist]
  )

  // ---------------------------------------------------------------------------
  // Controls (each is a user gesture, which also lets the browser start audio)
  // ---------------------------------------------------------------------------

  const playTrack = useCallback(
    (trackId: string) => commit({ trackId, isPlaying: true, positionSec: 0 }, 'select'),
    [commit]
  )

  const play = useCallback(() => {
    const s = stateRef.current
    const list = tracksRef.current
    if (!s?.trackId || !list.some((t) => t.id === s.trackId)) {
      if (list[0]) commit({ trackId: list[0].id, isPlaying: true, positionSec: 0 }, 'play')
      return
    }
    const pos = sharedPosition()
    const dur = loadedTrackIdRef.current === s.trackId ? finiteDuration(audioRef.current) : 0
    if (dur && pos >= dur - 0.5) {
      // Song already finished: start the next one instead of replaying the last second.
      commit({ trackId: nextTrackId(list, s.trackId), isPlaying: true, positionSec: 0 }, 'next')
      return
    }
    commit({ trackId: s.trackId, isPlaying: true, positionSec: pos }, 'play')
  }, [commit, sharedPosition])

  const pause = useCallback(() => {
    const s = stateRef.current
    if (!s?.trackId || !s.isPlaying) return
    commit({ trackId: s.trackId, isPlaying: false, positionSec: sharedPosition() }, 'pause')
  }, [commit, sharedPosition])

  const togglePlay = useCallback(() => {
    if (stateRef.current?.isPlaying) pause()
    else play()
  }, [play, pause])

  const seek = useCallback(
    (positionSec: number) => {
      const s = stateRef.current
      if (!s?.trackId) return
      commit({ trackId: s.trackId, isPlaying: s.isPlaying, positionSec }, 'seek')
    },
    [commit]
  )

  const next = useCallback(() => {
    const id = nextTrackId(tracksRef.current, stateRef.current?.trackId ?? null)
    if (id) commit({ trackId: id, isPlaying: true, positionSec: 0 }, 'next')
  }, [commit])

  const previous = useCallback(() => {
    const s = stateRef.current
    if (s?.trackId && sharedPosition() > RESTART_THRESHOLD_SEC) {
      commit({ trackId: s.trackId, isPlaying: true, positionSec: 0 }, 'previous')
      return
    }
    const id = previousTrackId(tracksRef.current, s?.trackId ?? null)
    if (id) commit({ trackId: id, isPlaying: true, positionSec: 0 }, 'previous')
  }, [commit, sharedPosition])

  const stop = useCallback(() => commit({ trackId: null, isPlaying: false, positionSec: 0 }, 'stop'), [commit])

  /** The current song ended (or should have): move everyone on. Safe if several clients call it. */
  const advanceFrom = useCallback(
    (trackId: string) => {
      const s = stateRef.current
      if (!s || !s.isPlaying || s.trackId !== trackId) return
      const id = nextTrackId(tracksRef.current, trackId)
      commit({ trackId: id, isPlaying: !!id, positionSec: 0 }, 'auto')
    },
    [commit]
  )

  // Refs so the audio element's event listeners always call the latest versions.
  const advanceRef = useRef(advanceFrom)
  advanceRef.current = advanceFrom
  const reconcileRef = useRef(reconcile)
  reconcileRef.current = reconcile

  /** Call from a tap/click: lets browsers with strict autoplay rules start audio. */
  const unlock = useCallback(() => {
    const audio = audioRef.current
    setNeedsUnlock(false)
    if (!audio) return
    const s = stateRef.current
    if (s?.isPlaying) {
      reconcile()
      return
    }
    const hadSrc = !!audio.getAttribute('src')
    const wasMuted = audio.muted
    audio.muted = true
    if (!hadSrc) audio.src = SILENT_WAV
    audio
      .play()
      .then(() => {
        if (!stateRef.current?.isPlaying) audio.pause()
      })
      .catch(() => {})
      .finally(() => {
        audio.muted = wasMuted
        if (!hadSrc && audio.src === SILENT_WAV) {
          audio.removeAttribute('src')
          audio.load()
        }
      })
  }, [reconcile, setNeedsUnlock])

  const setVolume = useCallback((v: number) => {
    const clamped = Math.min(1, Math.max(0, v))
    if (audioRef.current) audioRef.current.volume = clamped
    setVolumeState(clamped)
    saveVolume(clamped)
  }, [])

  /** Position for the progress bar: what you're actually hearing when playing. */
  const getPosition = useCallback((): number => {
    const s = stateRef.current
    const audio = audioRef.current
    if (!s) return 0
    if (audio && s.isPlaying && loadedTrackIdRef.current === s.trackId && !audio.paused) return audio.currentTime
    return sharedPosition()
  }, [sharedPosition])

  // ---------------------------------------------------------------------------
  // Realtime
  // ---------------------------------------------------------------------------

  /** If we rejoin an empty room that was left playing long ago, pause it rather than blasting music. */
  const checkOrphaned = useCallback(() => {
    const s = stateRef.current
    if (orphanCheckedRef.current || !presenceRef.current.synced || !s) return
    orphanCheckedRef.current = true
    if (presenceRef.current.others > 0 || s.seq !== 0 || !s.isPlaying) return
    if (getServerTimeMs() - s.anchorMs > ORPHAN_AFTER_MS) {
      commit({ trackId: s.trackId, isPlaying: false, positionSec: 0 }, 'auto')
    }
  }, [commit])

  const handleMessage = useCallback(
    (msg: RoomMessage) => {
      switch (msg.type) {
        case 'state': {
          if (!msg.state || typeof msg.state.seq !== 'number') return
          const adopted = adopt(msg.state)
          if (adopted && !msg.reply && msg.action && msg.action !== 'auto') {
            ctx.current.onActivity({
              by: msg.by || 'Someone',
              action: msg.action,
              trackId: msg.state.trackId,
              positionSec: msg.state.positionSec,
            })
          }
          break
        }
        case 'hello':
          // Someone (re)joined. Take their state if it's newer (they may have acted
          // while disconnected), then tell them where we are so both sides converge.
          if (msg.from === ctx.current.clientId) return
          if (msg.state && typeof msg.state.seq === 'number') adopt(msg.state)
          if (stateRef.current) sendRef.current({ type: 'state', state: stateRef.current, reply: true })
          break
        case 'queue':
          if (msg.from === ctx.current.clientId) return
          ctx.current.onQueueChanged()
          if (msg.note) ctx.current.onActivity({ by: msg.by || 'Someone', action: 'queue', note: msg.note })
          break
      }
    },
    [adopt]
  )

  const handleSubscribed = useCallback((isReconnect: boolean) => {
    sendRef.current({ type: 'hello', from: ctx.current.clientId, state: stateRef.current ?? undefined })
    if (isReconnect) ctx.current.onQueueChanged()
  }, [])

  const handlePresence = useCallback(
    (others: Listener[]) => {
      presenceRef.current = { synced: true, others: others.length }
      checkOrphaned()
    },
    [checkOrphaned]
  )

  const { send, listeners, status } = useRoomChannel({
    roomCode,
    clientId,
    name,
    onMessage: handleMessage,
    onSubscribed: handleSubscribed,
    onPresence: handlePresence,
  })
  sendRef.current = send

  /** Tell everyone the queue changed; `note` shows up in their activity toast. */
  const notifyQueue = useCallback((note?: string) => {
    sendRef.current({ type: 'queue', from: ctx.current.clientId, by: ctx.current.name, note })
  }, [])

  // ---------------------------------------------------------------------------
  // Effects
  // ---------------------------------------------------------------------------

  // One audio element for the whole visit; only its src changes.
  useEffect(() => {
    const audio = new Audio()
    audio.preload = 'auto'
    const v = getSavedVolume()
    audio.volume = v
    setVolumeState(v)
    audioRef.current = audio

    const isOurs = () => !!loadedTrackIdRef.current && audio.getAttribute('src') !== SILENT_WAV
    const onDuration = () => setDurationSec(finiteDuration(audio))
    const onCanPlay = () => setAudioError(null)
    const onPlaying = () => {
      setNeedsUnlock(false)
      loadRetriesRef.current = { trackId: null, count: 0 }
    }
    const onEnded = () => {
      if (loadedTrackIdRef.current) advanceRef.current(loadedTrackIdRef.current)
    }
    const onError = () => {
      if (!isOurs()) return
      const trackId = loadedTrackIdRef.current
      const prev = loadRetriesRef.current
      const count = prev.trackId === trackId ? prev.count : 0
      if (count < MAX_LOAD_RETRIES) {
        // Network blips happen; reload the same song before giving up.
        loadRetriesRef.current = { trackId, count: count + 1 }
        setTimeout(() => {
          if (loadedTrackIdRef.current !== trackId) return
          loadedTrackIdRef.current = null
          reconcileRef.current()
        }, 1500)
        return
      }
      setAudioError('This song couldn’t be loaded. It may be private on Suno or the link may have expired. Skip to keep going.')
    }
    audio.addEventListener('loadedmetadata', onDuration)
    audio.addEventListener('durationchange', onDuration)
    audio.addEventListener('canplay', onCanPlay)
    audio.addEventListener('playing', onPlaying)
    audio.addEventListener('ended', onEnded)
    audio.addEventListener('error', onError)
    reconcileRef.current()

    return () => {
      audio.removeEventListener('loadedmetadata', onDuration)
      audio.removeEventListener('durationchange', onDuration)
      audio.removeEventListener('canplay', onCanPlay)
      audio.removeEventListener('playing', onPlaying)
      audio.removeEventListener('ended', onEnded)
      audio.removeEventListener('error', onError)
      audio.pause()
      audio.removeAttribute('src')
      audio.load()
      audioRef.current = null
      loadedTrackIdRef.current = null
    }
  }, [setNeedsUnlock])

  // Adopt the saved room state once it loads (live state from others wins if newer).
  useEffect(() => {
    if (!initialRoomState) return
    adopt(stateFromRow(initialRoomState))
    checkOrphaned()
  }, [initialRoomState, adopt, checkOrphaned])

  // The queue changed: the current track may have just become available.
  useEffect(() => {
    reconcile()
  }, [tracks, reconcile])

  // Keep everyone's clocks aligned and correct drift.
  useEffect(() => {
    if (!roomCode) return
    void ensureTimeSynced()
    const timeSync = setInterval(() => void ensureTimeSynced(), 60_000)
    const tick = setInterval(() => {
      const audio = audioRef.current
      const s = stateRef.current
      if (!audio || !s?.isPlaying || !s.trackId) return
      if (loadedTrackIdRef.current !== s.trackId) {
        reconcile()
        return
      }
      const target = positionAt(s, getServerTimeMs())
      const dur = finiteDuration(audio)
      if (dur && target > dur + 1) {
        // We should be past the end (e.g. the tab was asleep): move on.
        advanceFrom(s.trackId)
        return
      }
      if (audio.error || audio.ended) return
      if (audio.paused) {
        if (!needsUnlockRef.current) playAudio()
        return
      }
      if (audio.seeking || audio.readyState < 3) return // buffering; catch up once it resumes

      const drift = audio.currentTime - target
      if (Math.abs(drift) > HARD_DRIFT_SEC) {
        audio.playbackRate = 1
        const now = Date.now()
        if (now - lastHardSeekRef.current > HARD_SEEK_COOLDOWN_MS) {
          lastHardSeekRef.current = now
          audio.currentTime = target
        }
      } else if (Math.abs(drift) > SOFT_DRIFT_SEC) {
        // Gently speed up or slow down until we line up again.
        audio.playbackRate = 1 - Math.max(-MAX_RATE_NUDGE, Math.min(MAX_RATE_NUDGE, drift * 0.25))
      } else if (audio.playbackRate !== 1) {
        audio.playbackRate = 1
      }
    }, TICK_MS)
    const onVisible = () => {
      if (document.visibilityState !== 'visible') return
      void ensureTimeSynced()
      reconcile()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      clearInterval(timeSync)
      clearInterval(tick)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [roomCode, reconcile, advanceFrom, playAudio])

  // Media keys / lock screen / headset buttons control the whole room.
  useEffect(() => {
    if (typeof navigator === 'undefined' || !('mediaSession' in navigator)) return
    const session = navigator.mediaSession
    const handlers: [MediaSessionAction, MediaSessionActionHandler][] = [
      ['play', () => play()],
      ['pause', () => pause()],
      ['nexttrack', () => next()],
      ['previoustrack', () => previous()],
      [
        'seekto',
        (d) => {
          if (d.seekTime != null) seek(d.seekTime)
        },
      ],
    ]
    for (const [action, handler] of handlers) {
      try {
        session.setActionHandler(action, handler)
      } catch {
        // action not supported by this browser
      }
    }
    return () => {
      for (const [action] of handlers) {
        try {
          session.setActionHandler(action, null)
        } catch {
          // ignore
        }
      }
    }
  }, [play, pause, next, previous, seek])

  const currentTrack = state?.trackId ? tracks.find((t) => t.id === state.trackId) ?? null : null
  useEffect(() => {
    if (typeof navigator === 'undefined' || !('mediaSession' in navigator)) return
    navigator.mediaSession.metadata = currentTrack
      ? new MediaMetadata({ title: currentTrack.title, artist: 'Suno Jam', album: roomCode ? `Room ${roomCode}` : '' })
      : null
  }, [currentTrack, roomCode])
  useEffect(() => {
    if (typeof navigator === 'undefined' || !('mediaSession' in navigator)) return
    navigator.mediaSession.playbackState = state?.trackId ? (state.isPlaying ? 'playing' : 'paused') : 'none'
  }, [state])

  return {
    state,
    currentTrack,
    isPlaying: !!state?.isPlaying,
    durationSec,
    audioError,
    needsUnlock,
    volume,
    listeners,
    status,
    getPosition,
    play,
    pause,
    togglePlay,
    seek,
    next,
    previous,
    playTrack,
    stop,
    unlock,
    setVolume,
    notifyQueue,
  }
}
