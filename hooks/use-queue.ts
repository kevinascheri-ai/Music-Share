'use client'

import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Track } from '@/lib/supabase'

export function useQueue(roomCode: string | null, onQueueUpdated?: () => void) {
  const [tracks, setTracks] = useState<Track[]>([])
  const [loading, setLoading] = useState(!!roomCode)
  const [error, setError] = useState<string | null>(null)

  const fetchTracks = useCallback(async () => {
    if (!roomCode) return
    const { data, error: err } = await supabase
      .from('tracks')
      .select('*')
      .eq('room_code', roomCode)
      .order('order_index', { ascending: true })
    if (err) {
      setError(err.message)
      return
    }
    setTracks((data as Track[]) ?? [])
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

  const addTrack = useCallback(
    async (title: string, url: string, thumbnailUrl?: string | null) => {
      if (!roomCode) return
      const { data: existing } = await supabase
        .from('tracks')
        .select('order_index')
        .eq('room_code', roomCode)
        .order('order_index', { ascending: false })
        .limit(1)
        .maybeSingle()
      const nextIndex = existing?.order_index != null ? (existing.order_index as number) + 1 : 0
      const { error: err } = await supabase.from('tracks').insert({
        room_code: roomCode,
        title: title.trim() || 'Untitled',
        url: url.trim(),
        order_index: nextIndex,
        ...(thumbnailUrl != null && thumbnailUrl !== '' && { thumbnail_url: thumbnailUrl }),
      })
      if (err) throw new Error(err.message)
      await fetchTracks()
      onQueueUpdated?.()
    },
    [roomCode, fetchTracks, onQueueUpdated]
  )

  const removeTrack = useCallback(
    async (trackId: string) => {
      if (!roomCode) return
      const { error: err } = await supabase.from('tracks').delete().eq('id', trackId)
      if (err) throw new Error(err.message)
      await fetchTracks()
      onQueueUpdated?.()
    },
    [roomCode, fetchTracks, onQueueUpdated]
  )

  const reorderTracks = useCallback(
    async (orderedIds: string[]) => {
      if (!roomCode) return
      for (let i = 0; i < orderedIds.length; i++) {
        await supabase.from('tracks').update({ order_index: i }).eq('id', orderedIds[i])
      }
      await fetchTracks()
      onQueueUpdated?.()
    },
    [roomCode, fetchTracks, onQueueUpdated]
  )

  return { tracks, loading, error, addTrack, removeTrack, reorderTracks, refetch: fetchTracks }
}
