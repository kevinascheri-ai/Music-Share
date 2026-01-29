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
  trackIndex?: number
  totalTracks: number
  isPlaying: boolean
  currentTimeSec: number
  durationSec: number
  audioRef: React.RefObject<HTMLAudioElement | null>
  onPlayPause: () => void
  onSeek: (timeSec: number) => void
  onPrevious: () => void
  onNext: () => void
}

export function NowPlaying({
  currentTrack,
  firstTrack,
  trackIndex,
  totalTracks,
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

  return (
    <div className="bg-white rounded-xl border border-slate-200 p-6 shadow-sm">
      <h2 className="text-sm font-medium text-slate-500 uppercase tracking-wide mb-2">
        Now Playing
      </h2>
      {currentTrack ? (
        <>
          {totalTracks > 1 && trackIndex != null && trackIndex >= 0 && (
            <p className="text-xs text-slate-500 mb-0.5">
              Track {trackIndex + 1} of {totalTracks}
            </p>
          )}
          <p className="text-lg font-semibold text-slate-800 truncate" title={currentTrack.title}>
            {currentTrack.title}
          </p>

          {/* Standard media controls */}
          <div className="mt-4 flex items-center justify-center gap-2">
            <button
              type="button"
              onClick={onPrevious}
              className="w-10 h-10 flex items-center justify-center rounded-full bg-slate-200 text-slate-700 hover:bg-slate-300"
              aria-label="Previous"
            >
              <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M16.464 4.464a.75.75 0 010 1.061L10.879 10.88a.75.75 0 010 1.06l5.585 5.416a.75.75 0 11-1.06 1.06l-4.885-4.884a.75.75 0 010-1.06l4.885-4.885a.75.75 0 011.06 0z" />
                <path d="M4.75 4.464a.75.75 0 01.75-.75h1.5a.75.75 0 01.75.75v11.072a.75.75 0 01-1.5 0V4.464z" />
              </svg>
            </button>
            <button
              type="button"
              onClick={onPlayPause}
              className="w-12 h-12 flex items-center justify-center rounded-full bg-slate-800 text-white hover:bg-slate-700"
              aria-label={isPlaying ? 'Pause' : 'Play'}
            >
              {isPlaying ? (
                <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M5.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75A.75.75 0 007.25 3h-1.5zM14.25 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75a.75.75 0 00-.75-.75h-1.5z" />
                </svg>
              ) : (
                <svg className="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
                </svg>
              )}
            </button>
            <button
              type="button"
              onClick={onNext}
              className="w-10 h-10 flex items-center justify-center rounded-full bg-slate-200 text-slate-700 hover:bg-slate-300"
              aria-label="Next"
            >
              <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M14.536 4.464a.75.75 0 010 1.061L9.121 10.88a.75.75 0 010 1.06l5.415 5.416a.75.75 0 01-1.06 1.06l-4.885-4.884a.75.75 0 010-1.06l4.885-4.885a.75.75 0 011.06 0z" />
                <path d="M4.75 4.464a.75.75 0 01.75-.75h1.5a.75.75 0 01.75.75v11.072a.75.75 0 01-1.5 0V4.464z" />
              </svg>
            </button>
          </div>

          {/* Progress bar and time */}
          <div className="mt-3 flex items-center gap-2">
            <span className="text-xs text-slate-500 tabular-nums w-10">
              {formatTime(currentTimeSec)}
            </span>
            <input
              type="range"
              min={0}
              max={maxSeek}
              step={0.1}
              value={currentTimeSec}
              onChange={handleSeek}
              className="flex-1 h-2 rounded-full appearance-none bg-slate-200 accent-slate-800 cursor-pointer"
            />
            <span className="text-xs text-slate-500 tabular-nums w-10 text-right">
              {displayDuration}
            </span>
          </div>

          {/* Volume */}
          <div className="mt-3 flex items-center gap-2">
            <svg className="w-4 h-4 text-slate-500 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 3.75a.75.75 0 00-1.264-.546L5.203 6H2.667a.75.75 0 00-.75.75v6.5c0 .414.336.75.75.75h2.536l3.533 2.796A.75.75 0 0010 16.25V3.75z" />
            </svg>
            <input
              type="range"
              min={0}
              max={1}
              step={0.05}
              defaultValue={1}
              onChange={handleVolume}
              className="flex-1 max-w-[100px] h-1.5 rounded-full appearance-none bg-slate-200 accent-slate-800 cursor-pointer"
            />
          </div>
        </>
      ) : firstTrack ? (
        <div>
          <p className="text-slate-600 mb-2">Up next: {firstTrack.title}</p>
          <button
            type="button"
            onClick={onPlayPause}
            className="w-12 h-12 flex items-center justify-center rounded-full bg-slate-800 text-white hover:bg-slate-700"
            aria-label="Play"
          >
            <svg className="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
            </svg>
          </button>
        </div>
      ) : (
        <p className="text-slate-500">Add a track to the queue to start.</p>
      )}
    </div>
  )
}
