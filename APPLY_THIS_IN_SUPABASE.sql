-- Suno Jam MVP: rooms, tracks, room_state
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run

-- Rooms: one row per room, keyed by invite code
CREATE TABLE IF NOT EXISTS public.rooms (
  room_code TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tracks: queue items per room (order_index for ordering)
CREATE TABLE IF NOT EXISTS public.tracks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code TEXT NOT NULL REFERENCES public.rooms(room_code) ON DELETE CASCADE,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  order_index INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tracks_room_code ON public.tracks(room_code);
CREATE INDEX IF NOT EXISTS idx_tracks_room_order ON public.tracks(room_code, order_index);

-- Room state: current playback (current track, play/pause, time)
CREATE TABLE IF NOT EXISTS public.room_state (
  room_code TEXT PRIMARY KEY REFERENCES public.rooms(room_code) ON DELETE CASCADE,
  current_track_id UUID NULL,
  is_playing BOOLEAN NOT NULL DEFAULT false,
  current_time_sec NUMERIC NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_state ENABLE ROW LEVEL SECURITY;

-- Policies: allow anonymous read/write for MVP (public, no auth)
-- rooms
CREATE POLICY "Allow anon read rooms"
  ON public.rooms FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "Allow anon insert rooms"
  ON public.rooms FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow anon delete rooms"
  ON public.rooms FOR DELETE
  TO anon
  USING (true);

-- tracks
CREATE POLICY "Allow anon read tracks"
  ON public.tracks FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "Allow anon insert tracks"
  ON public.tracks FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow anon update tracks"
  ON public.tracks FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow anon delete tracks"
  ON public.tracks FOR DELETE
  TO anon
  USING (true);

-- room_state
CREATE POLICY "Allow anon read room_state"
  ON public.room_state FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "Allow anon insert room_state"
  ON public.room_state FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow anon update room_state"
  ON public.room_state FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow anon delete room_state"
  ON public.room_state FOR DELETE
  TO anon
  USING (true);
