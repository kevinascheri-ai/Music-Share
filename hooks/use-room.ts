'use client'

import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Room, RoomState } from '@/lib/supabase'

export function useRoom(code: string | null) {
  const [room, setRoom] = useState<Room | null>(null)
  const [roomState, setRoomState] = useState<RoomState | null>(null)
  const [loading, setLoading] = useState(!!code)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!code) {
      setRoom(null)
      setRoomState(null)
      setLoading(false)
      return
    }

    let mounted = true

    async function load() {
      setLoading(true)
      setError(null)
      const { data: roomData, error: roomErr } = await supabase
        .from('rooms')
        .select('*')
        .eq('room_code', code)
        .maybeSingle()

      if (!mounted) return
      if (roomErr) {
        setError(roomErr.message)
        setLoading(false)
        return
      }
      if (!roomData) {
        setError('Room not found')
        setRoom(null)
        setRoomState(null)
        setLoading(false)
        return
      }

      setRoom(roomData as Room)

      let stateData: RoomState | null = null
      const { data: stateResult, error: stateErr } = await supabase
        .from('room_state')
        .select('*')
        .eq('room_code', code)
        .maybeSingle()

      if (!mounted) return
      if (stateErr) {
        setError(stateErr.message)
      } else {
        stateData = (stateResult as RoomState) ?? null
        setRoomState(stateData)
      }

      if (!stateData && roomData) {
        await supabase.from('room_state').upsert({
          room_code: code,
          current_track_id: null,
          is_playing: false,
          current_time_sec: 0,
          updated_at: new Date().toISOString(),
        })
        const { data: refetched } = await supabase
          .from('room_state')
          .select('*')
          .eq('room_code', code)
          .single()
        if (mounted && refetched) setRoomState(refetched as RoomState)
      }
      setLoading(false)
    }

    load()
    return () => { mounted = false }
  }, [code])

  return { room, roomState, loading, error }
}

export async function createRoom(): Promise<string> {
  const code = generateRoomCode()
  const { error } = await supabase.from('rooms').insert({ room_code: code })
  if (error) throw new Error(error.message)
  await supabase.from('room_state').upsert({
    room_code: code,
    current_track_id: null,
    is_playing: false,
    current_time_sec: 0,
    updated_at: new Date().toISOString(),
  })
  return code
}

function generateRoomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let s = ''
  for (let i = 0; i < 6; i++) s += chars[Math.floor(Math.random() * chars.length)]
  return s
}
