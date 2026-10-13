'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Track } from '@/lib/supabase'

const TRACK_COLUMNS = 'id, room_code, title, url, order_index, created_at'

export type NewTrack = { title: string; url: string }

export function useQueue(roomCode: string | null) {
  const [tracks, setTracks] = useState<Track[]>([])
  const [loading, setLoading] = useState(!!roomCode)
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const tracksRef = useRef<Track[]>([])
  tracksRef.current = tracks
  const fetchIdRef = useRef(0)

  const fetchTracks = useCallback(async () => {
    if (!roomCode) return
    const fetchId = ++fetchIdRef.current
    const { data, error: err } = await supabase
      .from('tracks')
      .select(TRACK_COLUMNS)
      .eq('room_code', roomCode)
      .order('order_index', { ascending: true })
      .order('created_at', { ascending: true })
    // Ignore responses that arrive after a newer fetch started.
    if (fetchId !== fetchIdRef.current) return
    if (err) {
      setError(err.message)
      return
    }
    setError(null)
    setTracks((data as Track[]) ?? [])
    setLoaded(true)
  }, [roomCode])

  useEffect(() => {
    if (!roomCode) {
      setTracks([])
      setLoading(false)
      return
    }
    setLoading(true)
    fetchTracks().finally(() => setLoading(false))
  }, [roomCode, fetchTracks])

  /** Append tracks (one song or a whole playlist) in a single insert. */
  const addTracks = useCallback(
    async (items: NewTrack[]) => {
      if (!roomCode || !items.length) return
      const { data: last } = await supabase
        .from('tracks')
        .select('order_index')
        .eq('room_code', roomCode)
        .order('order_index', { ascending: false })
        .limit(1)
        .maybeSingle()
      const start = last?.order_index != null ? (last.order_index as number) + 1 : 0
      const { error: err } = await supabase.from('tracks').insert(
        items.map((item, i) => ({
          room_code: roomCode,
          title: item.title.trim() || 'Untitled',
          url: item.url.trim(),
          order_index: start + i,
        }))
      )
      if (err) throw new Error(err.message)
      await fetchTracks()
    },
    [roomCode, fetchTracks]
  )

  const removeTrack = useCallback(
    async (trackId: string) => {
      if (!roomCode) return
      setTracks((list) => list.filter((t) => t.id !== trackId))
      const { error: err } = await supabase.from('tracks').delete().eq('id', trackId)
      await fetchTracks()
      if (err) throw new Error(err.message)
    },
    [roomCode, fetchTracks]
  )

  const clearTracks = useCallback(async () => {
    if (!roomCode) return
    setTracks([])
    const { error: err } = await supabase.from('tracks').delete().eq('room_code', roomCode)
    await fetchTracks()
    if (err) throw new Error(err.message)
  }, [roomCode, fetchTracks])

  /** Save a new order in one request. Updates the list immediately so drags feel instant. */
  const reorderTracks = useCallback(
    async (orderedIds: string[]) => {
      if (!roomCode) return
      const byId = new Map(tracksRef.current.map((t) => [t.id, t]))
      const ordered = orderedIds
        .map((id) => byId.get(id))
        .filter((t): t is Track => !!t)
        .map((t, i) => ({ ...t, order_index: i }))
      setTracks(ordered)
      const { error: err } = await supabase.from('tracks').upsert(
        ordered.map(({ id, room_code, title, url, order_index }) => ({ id, room_code, title, url, order_index }))
      )
      await fetchTracks()
      if (err) throw new Error(err.message)
    },
    [roomCode, fetchTracks]
  )

  return {
    tracks,
    loading,
    loaded,
    error,
    addTracks,
    removeTrack,
    clearTracks,
    reorderTracks,
    refetch: fetchTracks,
  }
}
