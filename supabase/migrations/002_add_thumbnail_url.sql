-- Add optional thumbnail_url to tracks (for Suno art)
ALTER TABLE public.tracks
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT NULL;
