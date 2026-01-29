'use client'

import type { Track } from '@/lib/supabase'

function formatTime(sec: number): string {
  if (!Number.isFinite(sec) || sec < 0) return '0:00'
  const m = Math.floor(sec / 60)
  const s = Math.floor(sec % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}

type Props = {
  currentTrack: Track | null
  firstTrack: Track | null
  isPlaying: boolean
  currentTimeSec: number
  durationSec: number
  audioRef: React.RefObject<HTMLAudioElement | null>
  onPlayPause: () => void
  onSeek: (timeSec: number) => void
  onPrevious: () => void
  onNext: () => void
}

export function BottomPlayerBar({
  currentTrack,
  firstTrack,
  isPlaying,
  currentTimeSec,
  durationSec,
  audioRef,
  onPlayPause,
  onSeek,
  onPrevious,
  onNext,
}: Props) {
  const duration = Number.isFinite(durationSec) && durationSec > 0 ? durationSec : 0
  const maxSeek = Math.max(duration, currentTimeSec + 10, 60)
  const displayDuration = duration > 0 ? formatTime(duration) : '--:--'

  const handleSeek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value)
    if (!Number.isNaN(val)) onSeek(val)
  }

  const handleVolume = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value)
    if (audioRef.current && !Number.isNaN(val)) audioRef.current.volume = val
  }

  const trackTitle = currentTrack?.title ?? (firstTrack ? 'Tap play to start' : 'No track selected')

  return (
    <footer
      className="fixed bottom-0 left-0 right-0 z-50 bg-[#181818] border-t border-[#282828]"
      style={{ paddingBottom: 'env(safe-area-inset-bottom, 0)' }}
    >
      {/* Progress bar - full width above controls */}
      <div className="px-4 pt-1">
        <input
          type="range"
          min={0}
          max={maxSeek}
          step={0.1}
          value={currentTimeSec}
          onChange={handleSeek}
          className="w-full h-1 cursor-pointer accent-[#1db954]"
        />
        <div className="flex justify-between text-xs text-[#b3b3b3] -mt-0.5 px-0.5">
          <span className="tabular-nums">{formatTime(currentTimeSec)}</span>
          <span className="tabular-nums">{displayDuration}</span>
        </div>
      </div>

      <div className="flex items-center justify-between gap-4 px-4 py-3 max-w-7xl mx-auto">
        {/* Left: track info + art */}
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="w-14 h-14 flex-shrink-0 rounded bg-[#282828] flex items-center justify-center">
            <svg
              className="w-8 h-8 text-[#535353]"
              fill="currentColor"
              viewBox="0 0 24 24"
              aria-hidden
            >
              <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
            </svg>
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-white truncate">{trackTitle}</p>
            <p className="text-xs text-[#b3b3b3] truncate">
              {currentTrack ? 'Suno Jam' : 'Add tracks to the queue'}
            </p>
          </div>
        </div>

        {/* Center: playback controls */}
        <div className="flex items-center justify-center gap-2 flex-shrink-0">
          <button
            type="button"
            onClick={onPrevious}
            className="w-8 h-8 flex items-center justify-center rounded-full text-[#b3b3b3] hover:text-white hover:scale-110 transition"
            aria-label="Previous"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" />
            </svg>
          </button>
          <button
            type="button"
            onClick={onPlayPause}
            className="w-12 h-12 flex items-center justify-center rounded-full bg-white text-black hover:scale-105 transition shadow-lg"
            aria-label={isPlaying ? 'Pause' : 'Play'}
          >
            {isPlaying ? (
              <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
              </svg>
            ) : (
              <svg className="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>
          <button
            type="button"
            onClick={onNext}
            className="w-8 h-8 flex items-center justify-center rounded-full text-[#b3b3b3] hover:text-white hover:scale-110 transition"
            aria-label="Next"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" />
            </svg>
          </button>
        </div>

        {/* Right: volume */}
        <div className="flex items-center gap-2 w-32 flex-shrink-0">
          <svg
            className="w-5 h-5 text-[#b3b3b3] flex-shrink-0"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z" />
          </svg>
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            defaultValue={1}
            onChange={handleVolume}
            className="flex-1 h-1 cursor-pointer accent-[#1db954]"
          />
        </div>
      </div>
    </footer>
  )
}
