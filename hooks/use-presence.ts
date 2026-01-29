'use client'

import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { getClientId } from '@/lib/client-id'

export function usePresence(roomCode: string | null) {
  const [count, setCount] = useState(0)

  useEffect(() => {
    if (!roomCode || typeof window === 'undefined') {
      setCount(0)
      return
    }

    const channel = supabase.channel(`room:${roomCode}`, {
      config: { presence: { key: getClientId() } },
    })

    channel
      .on('presence', { event: 'sync' }, () => {
        const state = channel.presenceState()
        const keys = Object.keys(state)
        let total = 0
        keys.forEach((k) => {
          total += (state[k]?.length ?? 0)
        })
        setCount(total)
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await channel.track({ joined_at: new Date().toISOString() })
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [roomCode])

  return count
}
