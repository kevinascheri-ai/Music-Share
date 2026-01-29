import { createClient, SupabaseClient } from '@supabase/supabase-js'

const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'https://placeholder.supabase.co'
const supabaseAnonKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? 'placeholder-key'

export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnonKey)

export type Room = { room_code: string; created_at: string }
export type Track = {
  id: string
  room_code: string
  title: string
  url: string
  order_index: number
  created_at: string
}
export type RoomState = {
  room_code: string
  current_track_id: string | null
  is_playing: boolean
  current_time_sec: number
  updated_at: string
}

export type PlaybackEvent = {
  type: 'PLAY' | 'PAUSE' | 'SEEK' | 'NEXT' | 'PREVIOUS' | 'QUEUE_UPDATED'
  trackId?: string | null
  timeSec?: number
  clientSentAtMs?: number
  eventId?: string
  clientId?: string
}
