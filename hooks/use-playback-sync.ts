'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { PlaybackEvent, RoomState, Track } from '@/lib/supabase'
import { getClientId, generateEventId } from '@/lib/client-id'
import { getServerTimeMs, ensureTimeSynced } from '@/lib/time-sync'

const BROADCAST_EVENT = 'playback'
const DRIFT_THRESHOLD_SEC = 0.25
const DRIFT_CHECK_MS = 2000

type PlaybackState = {
  currentTrackId: string | null
  isPlaying: boolean
  currentTimeSec: number
}

export function usePlaybackSync(
  roomCode: string | null,
  audioRef: React.RefObject<HTMLAudioElement | null>,
  tracks: Track[],
  initialRoomState: RoomState | null,
  onQueueUpdated?: () => void
) {
  const [state, setState] = useState<PlaybackState>({
    currentTrackId: initialRoomState?.current_track_id ?? null,
    isPlaying: initialRoomState?.is_playing ?? false,
    currentTimeSec: Number(initialRoomState?.current_time_sec ?? 0),
  })

  const lastSyncTimeSecRef = useRef(Number(initialRoomState?.current_time_sec ?? 0))
  const lastSyncAtMsRef = useRef(Date.now())
  const clientId = getClientId()
  const tracksRef = useRef(tracks)
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const playingTrackIdRef = useRef<string | null>(initialRoomState?.current_track_id ?? null)
  const currentTrackIdRef = useRef<string | null>(initialRoomState?.current_track_id ?? null)
  const pendingSyncRef = useRef<{ type: 'PLAY' | 'SEEK'; trackId: string; timeSec: number } | null>(null)
  currentTrackIdRef.current = state.currentTrackId
  tracksRef.current = tracks

  const applyPlay = useCallback(
    (trackId: string | null, timeSec: number) => {
      const audio = audioRef.current
      const tr = tracksRef.current.find((t) => t.id === trackId)
      if (!tr) {
        if (audio) {
          audio.pause()
          audio.removeAttribute('src')
        }
        playingTrackIdRef.current = null
        setState((s) => ({ ...s, currentTrackId: null, isPlaying: false, currentTimeSec: 0 }))
        lastSyncTimeSecRef.current = 0
        lastSyncAtMsRef.current = Date.now()
        return
      }
      if (audio) {
        audio.src = tr.url
        audio.currentTime = timeSec
        audio.play().catch(() => {})
      }
      playingTrackIdRef.current = trackId
      setState((s) => ({
        ...s,
        currentTrackId: trackId,
        isPlaying: true,
        currentTimeSec: timeSec,
      }))
      lastSyncTimeSecRef.current = timeSec
      lastSyncAtMsRef.current = Date.now()
    },
    [audioRef]
  )

  const applyPause = useCallback(
    (timeSec: number) => {
      const audio = audioRef.current
      if (audio) {
        audio.pause()
        audio.currentTime = timeSec
      }
      setState((s) => ({ ...s, isPlaying: false, currentTimeSec: timeSec }))
      lastSyncTimeSecRef.current = timeSec
      lastSyncAtMsRef.current = Date.now()
    },
    [audioRef]
  )

  const applySeek = useCallback(
    (trackId: string | null, timeSec: number) => {
      const tr = tracksRef.current.find((t) => t.id === trackId)
      const audio = audioRef.current
      if (!tr) return
      if (audio) {
        if (audio.src !== tr.url) audio.src = tr.url
        audio.currentTime = timeSec
        if (state.isPlaying) audio.play().catch(() => {})
      }
      playingTrackIdRef.current = trackId
      setState((s) => ({ ...s, currentTrackId: trackId, currentTimeSec: timeSec }))
      lastSyncTimeSecRef.current = timeSec
      lastSyncAtMsRef.current = Date.now()
    },
    [audioRef, state.isPlaying]
  )

  const getNextTrackId = useCallback(() => {
    const list = tracksRef.current
    const current = state.currentTrackId
    if (!list.length) return null
    const idx = list.findIndex((t) => t.id === current)
    if (idx < 0) return list[0]?.id ?? null
    return list[idx + 1]?.id ?? null
  }, [state.currentTrackId])

  const getPreviousTrackId = useCallback(() => {
    const list = tracksRef.current
    const current = state.currentTrackId
    if (!list.length) return null
    const idx = list.findIndex((t) => t.id === current)
    if (idx <= 0) return list[0]?.id ?? null
    return list[idx - 1]?.id ?? null
  }, [state.currentTrackId])

  const applyNext = useCallback(() => {
    const nextId = getNextTrackId()
    if (nextId) applyPlay(nextId, 0)
    else applyPause(state.currentTimeSec)
  }, [getNextTrackId, applyPlay, applyPause, state.currentTimeSec])

  const applyPrevious = useCallback(() => {
    const prevId = getPreviousTrackId()
    if (prevId) applyPlay(prevId, 0)
  }, [getPreviousTrackId, applyPlay])

  useEffect(() => {
    if (!roomCode) return
    ensureTimeSynced()
  }, [roomCode])

  useEffect(() => {
    if (!roomCode || !audioRef.current) return

    const channel = supabase.channel(`room:${roomCode}`)
    channelRef.current = channel

    ;(channel as { on: (t: string, f: { event: string }, cb: (p: { payload?: PlaybackEvent } & PlaybackEvent) => void) => typeof channel }).on(
      'broadcast',
      { event: BROADCAST_EVENT },
      (msg) => {
        const payload: PlaybackEvent = (msg as { payload?: PlaybackEvent }).payload ?? (msg as PlaybackEvent)
        if (payload.clientId === clientId) return

        const trackId = payload.trackId ?? null
        const timeSec = payload.timeSec ?? 0
        const hasTrack = trackId ? tracksRef.current.some((t) => t.id === trackId) : false

        switch (payload.type) {
          case 'PLAY':
            if (hasTrack) {
              applyPlay(trackId, timeSec)
              pendingSyncRef.current = null
            } else if (trackId) {
              pendingSyncRef.current = { type: 'PLAY', trackId, timeSec }
              onQueueUpdated?.()
            }
            break
          case 'PAUSE':
            pendingSyncRef.current = null
            applyPause(timeSec)
            break
          case 'SEEK':
            if (hasTrack) {
              applySeek(trackId, timeSec)
              pendingSyncRef.current = null
            } else if (trackId) {
              pendingSyncRef.current = { type: 'SEEK', trackId, timeSec }
              onQueueUpdated?.()
            }
            break
          case 'NEXT':
            pendingSyncRef.current = null
            applyNext()
            break
          case 'PREVIOUS':
            pendingSyncRef.current = null
            applyPrevious()
            break
          case 'QUEUE_UPDATED':
            onQueueUpdated?.()
            break
          default:
            break
        }
      }
    )

    channel.subscribe()

    return () => {
      channelRef.current = null
      supabase.removeChannel(channel)
    }
  }, [roomCode, clientId, applyPlay, applyPause, applySeek, applyNext, applyPrevious, onQueueUpdated])

  // When we receive PLAY/SEEK but didn't have the track, we refetched queue; apply pending sync once we have the track
  useEffect(() => {
    const pending = pendingSyncRef.current
    if (!pending) return
    const tr = tracks.find((t) => t.id === pending.trackId)
    if (!tr) return
    if (pending.type === 'PLAY') applyPlay(pending.trackId, pending.timeSec)
    else applySeek(pending.trackId, pending.timeSec)
    pendingSyncRef.current = null
  }, [tracks, applyPlay, applySeek])

  useEffect(() => {
    if (!roomCode || !initialRoomState) return
    const audio = audioRef.current
    const trackId = initialRoomState.current_track_id
    const timeSec = Number(initialRoomState.current_time_sec)
    const isPlaying = initialRoomState.is_playing
    const tr = tracks.find((t) => t.id === trackId)
    if (!tr) return
    if (audio) {
      audio.src = tr.url
      audio.currentTime = timeSec
      if (isPlaying) audio.play().catch(() => {})
    }
    setState({ currentTrackId: trackId, isPlaying, currentTimeSec: timeSec })
    lastSyncTimeSecRef.current = timeSec
    lastSyncAtMsRef.current = Date.now()
  }, [roomCode])

  useEffect(() => {
    const audio = audioRef.current
    if (!audio) return
    const onTimeUpdate = () => {
      setState((s) => ({ ...s, currentTimeSec: audio.currentTime }))
    }
    audio.addEventListener('timeupdate', onTimeUpdate)
    return () => audio.removeEventListener('timeupdate', onTimeUpdate)
  }, [audioRef])

  const sendNextRef = useRef<() => Promise<void>>(() => Promise.resolve())
  useEffect(() => {
    const audio = audioRef.current
    if (!audio) return
    const onEnded = () => {
      if (currentTrackIdRef.current === playingTrackIdRef.current) {
        sendNextRef.current()
      }
    }
    audio.addEventListener('ended', onEnded)
    return () => audio.removeEventListener('ended', onEnded)
  }, [audioRef])

  useEffect(() => {
    const interval = setInterval(() => {
      const audio = audioRef.current
      if (!audio || !state.isPlaying) return
      const expected =
        lastSyncTimeSecRef.current + (Date.now() - lastSyncAtMsRef.current) / 1000
      const drift = Math.abs(audio.currentTime - expected)
      if (drift > DRIFT_THRESHOLD_SEC) {
        audio.currentTime = expected
        lastSyncTimeSecRef.current = expected
        lastSyncAtMsRef.current = Date.now()
        setState((s) => ({ ...s, currentTimeSec: expected }))
      }
    }, DRIFT_CHECK_MS)
    return () => clearInterval(interval)
  }, [state.isPlaying, audioRef])

  const updateRoomState = useCallback(
    async (updates: Partial<{ current_track_id: string | null; is_playing: boolean; current_time_sec: number }>) => {
      if (!roomCode) return
      await supabase
        .from('room_state')
        .upsert({
          room_code: roomCode,
          ...updates,
          updated_at: new Date().toISOString(),
        })
    },
    [roomCode]
  )

  const broadcast = useCallback((payload: PlaybackEvent) => {
    const ch = channelRef.current
    if (!ch) return
    ch.send({
      type: 'broadcast',
      event: BROADCAST_EVENT,
      payload: { ...payload, clientId, eventId: generateEventId() },
    })
  }, [])

  const sendPlay = useCallback(
    async (trackId: string | null, timeSec: number) => {
      await updateRoomState({
        current_track_id: trackId,
        is_playing: true,
        current_time_sec: timeSec,
      })
      broadcast({ type: 'PLAY', trackId, timeSec, clientSentAtMs: getServerTimeMs() })
      applyPlay(trackId, timeSec)
    },
    [updateRoomState, broadcast, applyPlay]
  )

  const sendPause = useCallback(
    async (timeSec: number) => {
      await updateRoomState({ is_playing: false, current_time_sec: timeSec })
      broadcast({ type: 'PAUSE', timeSec, clientSentAtMs: getServerTimeMs() })
      applyPause(timeSec)
    },
    [updateRoomState, broadcast, applyPause]
  )

  const sendSeek = useCallback(
    async (trackId: string | null, timeSec: number) => {
      await updateRoomState({
        current_track_id: trackId,
        current_time_sec: timeSec,
      })
      broadcast({ type: 'SEEK', trackId, timeSec, clientSentAtMs: getServerTimeMs() })
      applySeek(trackId, timeSec)
    },
    [updateRoomState, broadcast, applySeek]
  )

  const sendNext = useCallback(async () => {
    const nextId = getNextTrackId()
    if (nextId) {
      await sendPlay(nextId, 0)
    } else {
      await sendPause(state.currentTimeSec)
    }
  }, [getNextTrackId, sendPlay, sendPause, state.currentTimeSec])

  const sendPrevious = useCallback(async () => {
    const prevId = getPreviousTrackId()
    if (prevId) await sendPlay(prevId, 0)
  }, [getPreviousTrackId, sendPlay])

  sendNextRef.current = sendNext

  const broadcastQueueUpdated = useCallback(() => {
    broadcast({ type: 'QUEUE_UPDATED' })
  }, [broadcast])

  return {
    ...state,
    sendPlay,
    sendPause,
    sendSeek,
    sendNext,
    sendPrevious,
    broadcastQueueUpdated,
  }
}
