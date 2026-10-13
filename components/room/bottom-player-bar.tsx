'use client'

import { useEffect, useRef, useState } from 'react'
import type { Track } from '@/lib/supabase'
import { formatTime } from '@/lib/sync'

type Props = {
  currentTrack: Track | null
  hasTracks: boolean
  isPlaying: boolean
  durationSec: number
  /** Current position, polled while the bar is visible. */
  getPosition: () => number
  volume: number
  onVolumeChange: (volume: number) => void
  onPlayPause: () => void
  onSeek: (timeSec: number) => void
  onPrevious: () => void
  onNext: () => void
}

export function BottomPlayerBar({
  currentTrack,
  hasTracks,
  isPlaying,
  durationSec,
  getPosition,
  volume,
  onVolumeChange,
  onPlayPause,
  onSeek,
  onPrevious,
  onNext,
}: Props) {
  const [position, setPosition] = useState(0)
  // While dragging the seek bar we show the drag position and only seek on release,
  // so the room gets one seek instead of dozens.
  const [scrub, setScrub] = useState<number | null>(null)
  const scrubRef = useRef<number | null>(null)
  const draggingRef = useRef(false)
  const commitTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [lastVolume, setLastVolume] = useState(1)

  useEffect(() => {
    const tick = () => setPosition(getPosition())
    tick()
    const id = setInterval(tick, 250)
    return () => clearInterval(id)
  }, [getPosition, currentTrack?.id, isPlaying])

  useEffect(() => () => {
    if (commitTimerRef.current) clearTimeout(commitTimerRef.current)
  }, [])

  const duration = durationSec > 0 ? durationSec : 0
  const shown = scrub ?? position
  const max = Math.max(duration, shown, 1)

  const commitScrub = () => {
    if (commitTimerRef.current) clearTimeout(commitTimerRef.current)
    commitTimerRef.current = null
    draggingRef.current = false
    const v = scrubRef.current
    if (v == null) return
    scrubRef.current = null
    setPosition(v)
    setScrub(null)
    onSeek(v)
  }

  const handleScrub = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = parseFloat(e.target.value)
    if (Number.isNaN(v)) return
    scrubRef.current = v
    setScrub(v)
    // Keyboard / click changes have no pointer-up, so commit after a short pause.
    if (!draggingRef.current) {
      if (commitTimerRef.current) clearTimeout(commitTimerRef.current)
      commitTimerRef.current = setTimeout(commitScrub, 250)
    }
  }

  const title = currentTrack?.title ?? (hasTracks ? 'Press play to start the jam' : 'Nothing queued')
  const subtitle = currentTrack ? (isPlaying ? 'Playing for everyone' : 'Paused for everyone') : hasTracks ? '' : 'Paste a Suno playlist to get going'
  const muted = volume === 0

  return (
    <footer
      className="fixed bottom-0 left-0 right-0 z-40 bg-[#181818] border-t border-[#282828]"
      style={{ paddingBottom: 'env(safe-area-inset-bottom, 0)' }}
    >
      <div className="px-4 pt-1">
        <input
          type="range"
          min={0}
          max={max}
          step={0.1}
          value={Math.min(shown, max)}
          disabled={!currentTrack}
          onChange={handleScrub}
          onPointerDown={() => (draggingRef.current = true)}
          onPointerUp={commitScrub}
          onPointerCancel={commitScrub}
          aria-label="Seek"
          className="range-accent w-full h-1 cursor-pointer disabled:cursor-default"
          style={{ ['--progress' as string]: `${(Math.min(shown, max) / max) * 100}%` }}
        />
        <div className="flex justify-between text-xs text-[#b3b3b3] -mt-0.5 px-0.5">
          <span className="tabular-nums">{formatTime(shown)}</span>
          <span className="tabular-nums">{duration > 0 ? formatTime(duration) : '--:--'}</span>
        </div>
      </div>

      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3 px-4 pb-3 pt-1 max-w-7xl mx-auto">
        <div className="min-w-0">
          <p className="text-sm font-medium text-white truncate">{title}</p>
          {subtitle && <p className="text-xs text-[#b3b3b3] truncate">{subtitle}</p>}
        </div>

        <div className="flex items-center justify-center gap-2">
          <button
            type="button"
            onClick={onPrevious}
            disabled={!hasTracks}
            className="w-9 h-9 flex items-center justify-center rounded-full text-[#b3b3b3] hover:text-white hover:scale-110 disabled:opacity-40 transition"
            aria-label="Previous"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
              <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" />
            </svg>
          </button>
          <button
            type="button"
            onClick={onPlayPause}
            disabled={!hasTracks}
            className="w-12 h-12 flex items-center justify-center rounded-full bg-white text-black hover:scale-105 disabled:opacity-40 disabled:hover:scale-100 transition shadow-lg"
            aria-label={isPlaying ? 'Pause' : 'Play'}
          >
            {isPlaying ? (
              <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
                <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
              </svg>
            ) : (
              <svg className="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>
          <button
            type="button"
            onClick={onNext}
            disabled={!hasTracks}
            className="w-9 h-9 flex items-center justify-center rounded-full text-[#b3b3b3] hover:text-white hover:scale-110 disabled:opacity-40 transition"
            aria-label="Next"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
              <path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" />
            </svg>
          </button>
        </div>

        {/* Volume is per person, so you can each set your own level under game audio. */}
        <div className="flex items-center gap-2 justify-self-end w-full max-w-[9rem]">
          <button
            type="button"
            onClick={() => {
              if (muted) onVolumeChange(lastVolume || 1)
              else {
                setLastVolume(volume)
                onVolumeChange(0)
              }
            }}
            className="text-[#b3b3b3] hover:text-white flex-shrink-0"
            aria-label={muted ? 'Unmute' : 'Mute'}
            title="Your volume (only affects you)"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
              {muted ? (
                <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z" />
              ) : (
                <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z" />
              )}
            </svg>
          </button>
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={volume}
            onChange={(e) => {
              const v = parseFloat(e.target.value)
              if (!Number.isNaN(v)) onVolumeChange(v)
            }}
            aria-label="Your volume"
            className="range-accent hidden sm:block flex-1 min-w-0 h-1 cursor-pointer"
            style={{ ['--progress' as string]: `${volume * 100}%` }}
          />
        </div>
      </div>
    </footer>
  )
}
