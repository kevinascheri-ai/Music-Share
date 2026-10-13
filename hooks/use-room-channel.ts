'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { RoomMessage } from '@/lib/sync'

const MESSAGE_EVENT = 'msg'

export type Listener = { id: string; name: string }
export type ChannelStatus = 'connecting' | 'connected' | 'reconnecting'

type Options = {
  roomCode: string | null
  clientId: string
  name: string
  onMessage: (msg: RoomMessage) => void
  /** Called on every successful (re)subscribe. */
  onSubscribed?: (isReconnect: boolean) => void
  /** Called after each presence sync with everyone else in the room. */
  onPresence?: (others: Listener[]) => void
}

/**
 * One realtime channel per room, carrying both presence (who's listening) and
 * broadcast messages (playback state, queue changes).
 */
export function useRoomChannel({ roomCode, clientId, name, onMessage, onSubscribed, onPresence }: Options) {
  const [listeners, setListeners] = useState<Listener[]>([])
  const [status, setStatus] = useState<ChannelStatus>('connecting')
  const channelRef = useRef<RealtimeChannel | null>(null)
  const subscribedRef = useRef(false)

  // Latest callbacks without resubscribing when they change.
  const handlers = useRef({ onMessage, onSubscribed, onPresence, name })
  handlers.current = { onMessage, onSubscribed, onPresence, name }

  useEffect(() => {
    if (!roomCode || !clientId) return
    let everSubscribed = false
    const channel = supabase.channel(`room:${roomCode}`, {
      config: { presence: { key: clientId }, broadcast: { self: false } },
    })
    channelRef.current = channel

    channel
      .on('broadcast', { event: MESSAGE_EVENT }, ({ payload }) => {
        if (payload && typeof payload === 'object') handlers.current.onMessage(payload as RoomMessage)
      })
      .on('presence', { event: 'sync' }, () => {
        const state = channel.presenceState<{ name?: string }>()
        const all: Listener[] = Object.entries(state).map(([id, metas]) => ({
          id,
          name: metas[metas.length - 1]?.name?.trim() || 'Listener',
        }))
        all.sort((a, b) => (a.id === clientId ? -1 : b.id === clientId ? 1 : a.name.localeCompare(b.name)))
        setListeners(all)
        handlers.current.onPresence?.(all.filter((l) => l.id !== clientId))
      })
      .subscribe((s) => {
        if (s === 'SUBSCRIBED') {
          subscribedRef.current = true
          setStatus('connected')
          channel.track({ name: handlers.current.name || 'Listener' }).catch(() => {})
          handlers.current.onSubscribed?.(everSubscribed)
          everSubscribed = true
        } else {
          subscribedRef.current = false
          setStatus(everSubscribed ? 'reconnecting' : 'connecting')
        }
      })

    return () => {
      subscribedRef.current = false
      channelRef.current = null
      supabase.removeChannel(channel)
    }
  }, [roomCode, clientId])

  // Update our presence when the display name changes.
  useEffect(() => {
    const channel = channelRef.current
    if (channel && subscribedRef.current) channel.track({ name: name || 'Listener' }).catch(() => {})
  }, [name])

  const send = useCallback((msg: RoomMessage) => {
    const channel = channelRef.current
    if (!channel) return
    channel.send({ type: 'broadcast', event: MESSAGE_EVENT, payload: msg }).catch(() => {})
  }, [])

  return { send, listeners, status }
}
