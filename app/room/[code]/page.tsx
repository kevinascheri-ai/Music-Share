'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import { useRoom } from '@/hooks/use-room'
import { useQueue, type NewTrack } from '@/hooks/use-queue'
import { usePlaybackSync, type Activity } from '@/hooks/use-playback-sync'
import { BottomPlayerBar } from '@/components/room/bottom-player-bar'
import { QueueList } from '@/components/room/queue-list'
import { AddTrackForm } from '@/components/room/add-track-form'
import { JoinOverlay } from '@/components/room/join-overlay'
import { getRoomUrl } from '@/lib/room-url'
import { getClientId, getSavedName, saveName } from '@/lib/client-id'
import { formatTime, shuffledIds } from '@/lib/sync'

const BOTTOM_BAR_HEIGHT = 128
const TOAST_MS = 3500

function hasUserActivation(): boolean {
  const ua = (navigator as Navigator & { userActivation?: { hasBeenActive: boolean } }).userActivation
  return !!ua?.hasBeenActive
}

function isTypingTarget(el: EventTarget | null): boolean {
  if (!(el instanceof HTMLElement)) return false
  return el.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT', 'BUTTON'].includes(el.tagName)
}

export default function RoomPage() {
  const params = useParams()
  const code = typeof params.code === 'string' ? params.code.toUpperCase() : null

  // Client-only identity (avoids hydration mismatches).
  const [clientId, setClientId] = useState('')
  const [name, setName] = useState('')
  const [joined, setJoined] = useState(false)
  useEffect(() => {
    const saved = getSavedName()
    setClientId(getClientId())
    setName(saved)
    // Someone who just created the room has already clicked, so audio can start.
    setJoined(!!saved && hasUserActivation())
  }, [])

  const { roomState, loading: roomLoading, error: roomError } = useRoom(code)
  const {
    tracks,
    loaded: tracksLoaded,
    error: queueError,
    addTracks,
    removeTrack,
    clearTracks,
    reorderTracks,
    refetch: refetchQueue,
  } = useQueue(code)

  const [toast, setToast] = useState<string | null>(null)
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const showToast = useCallback((text: string) => {
    setToast(text)
    if (toastTimer.current) clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast(null), TOAST_MS)
  }, [])

  const tracksRef = useRef(tracks)
  tracksRef.current = tracks
  const handleActivity = useCallback(
    (a: Activity) => {
      const title = (id?: string | null) => {
        const t = tracksRef.current.find((tr) => tr.id === id)
        return t ? `“${t.title}”` : 'a song'
      }
      const text: Record<Activity['action'], string> = {
        play: 'pressed play',
        pause: 'paused',
        seek: `jumped to ${formatTime(a.positionSec ?? 0)}`,
        next: `skipped to ${title(a.trackId)}`,
        previous: `went back to ${title(a.trackId)}`,
        select: `picked ${title(a.trackId)}`,
        stop: 'stopped the music',
        auto: '',
        queue: a.note ?? 'updated the queue',
      }
      if (text[a.action]) showToast(`${a.by} ${text[a.action]}`)
    },
    [showToast]
  )

  const playback = usePlaybackSync({
    roomCode: code,
    clientId,
    name,
    tracks,
    tracksLoaded,
    initialRoomState: roomState,
    onQueueChanged: refetchQueue,
    onActivity: handleActivity,
  })
  const { currentTrack, togglePlay, notifyQueue } = playback

  const [actionError, setActionError] = useState<string | null>(null)
  const run = useCallback(async (fn: () => Promise<void>) => {
    setActionError(null)
    try {
      await fn()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Something went wrong')
    }
  }, [])

  const handleJoin = useCallback(
    (newName: string) => {
      const finalName = newName || name || 'Listener'
      saveName(finalName)
      setName(finalName)
      setJoined(true)
      playback.unlock()
    },
    [name, playback]
  )

  const handleAdd = useCallback(
    async (newTracks: NewTrack[], summary: string) => {
      await addTracks(newTracks)
      notifyQueue(`added ${summary}`)
    },
    [addTracks, notifyQueue]
  )

  const handleRemove = useCallback(
    (trackId: string) =>
      run(async () => {
        const track = tracks.find((t) => t.id === trackId)
        if (trackId === playback.state?.trackId) {
          if (tracks.length > 1) playback.next()
          else playback.stop()
        }
        await removeTrack(trackId)
        notifyQueue(track ? `removed “${track.title}”` : undefined)
      }),
    [run, tracks, playback, removeTrack, notifyQueue]
  )

  const handleReorder = useCallback(
    (ids: string[]) =>
      run(async () => {
        await reorderTracks(ids)
        notifyQueue()
      }),
    [run, reorderTracks, notifyQueue]
  )

  const handleShuffle = useCallback(
    () =>
      run(async () => {
        await reorderTracks(shuffledIds(tracks, playback.state?.trackId ?? null))
        notifyQueue('shuffled the queue')
      }),
    [run, reorderTracks, tracks, playback.state?.trackId, notifyQueue]
  )

  const handleClear = useCallback(
    () =>
      run(async () => {
        playback.stop()
        await clearTracks()
        notifyQueue('cleared the queue')
      }),
    [run, playback, clearTracks, notifyQueue]
  )

  // Space bar toggles play/pause for the room.
  useEffect(() => {
    if (!joined) return
    const onKey = (e: KeyboardEvent) => {
      if (e.code !== 'Space' || e.repeat || isTypingTarget(e.target)) return
      e.preventDefault()
      togglePlay()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [joined, togglePlay])

  const [linkCopied, setLinkCopied] = useState(false)
  const roomUrl = code && clientId ? getRoomUrl(code) : ''
  const copyRoomLink = useCallback(() => {
    if (!roomUrl || typeof navigator?.clipboard?.writeText !== 'function') return
    navigator.clipboard.writeText(roomUrl).then(() => {
      setLinkCopied(true)
      setTimeout(() => setLinkCopied(false), 2000)
    })
  }, [roomUrl])

  useEffect(() => {
    return () => {
      if (toastTimer.current) clearTimeout(toastTimer.current)
    }
  }, [])

  if (!code) {
    return (
      <main className="min-h-screen bg-[#121212] text-white px-4 py-8">
        <p className="text-[#b3b3b3]">Invalid room.</p>
        <Link href="/" className="text-[var(--accent)] hover:underline mt-2 inline-block">
          Back home
        </Link>
      </main>
    )
  }

  if (roomLoading || roomError) {
    return (
      <main className="min-h-screen bg-[#121212] text-white px-4 py-8">
        {roomLoading && <p className="text-[#b3b3b3]">Loading room…</p>}
        {roomError && (
          <>
            <p className="text-red-400">{roomError}</p>
            <Link href="/" className="text-[var(--accent)] hover:underline mt-2 inline-block">
              Back home
            </Link>
          </>
        )}
      </main>
    )
  }

  const others = playback.listeners.filter((l) => l.id !== clientId)
  const showOverlay = clientId !== '' && (!joined || playback.needsUnlock)

  return (
    <>
      <main className="min-h-screen bg-[#121212] text-white" style={{ paddingBottom: BOTTOM_BAR_HEIGHT + 16 }}>
        <div className="max-w-2xl mx-auto px-4 py-6">
          <header className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-3 mb-6">
            <div className="min-w-0">
              <Link href="/" className="text-sm text-[#b3b3b3] hover:text-white transition">
                ← Home
              </Link>
              <div className="flex items-center gap-1 mt-1">
                <h1 className="text-2xl font-bold truncate">Room {code}</h1>
                {roomUrl && (
                  <button
                    type="button"
                    onClick={copyRoomLink}
                    title={linkCopied ? 'Copied!' : 'Copy room link'}
                    aria-label={linkCopied ? 'Copied!' : 'Copy room link'}
                    className="flex-shrink-0 p-1.5 rounded text-[#b3b3b3] hover:text-[var(--accent)] hover:bg-[#282828] transition"
                  >
                    {linkCopied ? (
                      <svg className="w-5 h-5 text-[var(--accent)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                      </svg>
                    ) : (
                      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                      </svg>
                    )}
                  </button>
                )}
              </div>
            </div>
            <div className="flex flex-col sm:items-end gap-1 sm:pt-6 text-sm">
              {playback.status === 'connected' ? (
                <div className="flex flex-wrap sm:justify-end gap-1.5" aria-label="Listening now">
                  {playback.listeners.map((l) => (
                    <span key={l.id} className="inline-flex items-center gap-1.5 rounded-full bg-[#282828] px-2.5 py-1 text-xs">
                      <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)]" aria-hidden />
                      {l.id === clientId ? `${name || 'You'} (you)` : l.name}
                    </span>
                  ))}
                </div>
              ) : (
                <span className="text-xs text-[#b3b3b3]">
                  {playback.status === 'reconnecting' ? 'Reconnecting…' : 'Connecting…'}
                </span>
              )}
            </div>
          </header>

          {playback.status === 'connected' && others.length === 0 && roomUrl && (
            <div className="mb-6 rounded-xl border border-[#282828] bg-[#181818] p-4">
              <p className="text-sm text-[#b3b3b3]">Send this link so they can listen along:</p>
              <div className="mt-2 flex gap-2">
                <input
                  readOnly
                  value={roomUrl}
                  onFocus={(e) => e.currentTarget.select()}
                  className="flex-1 min-w-0 py-2 px-3 rounded-lg bg-[#282828] text-sm text-white"
                  aria-label="Room link"
                />
                <button
                  type="button"
                  onClick={copyRoomLink}
                  className="flex-shrink-0 py-2 px-4 rounded-lg bg-[#333333] text-sm font-semibold hover:bg-[#404040] transition"
                >
                  {linkCopied ? 'Copied!' : 'Copy'}
                </button>
              </div>
            </div>
          )}

          {playback.audioError && (
            <div className="mb-4 flex items-center justify-between gap-3 rounded-lg bg-red-500/10 border border-red-500/30 px-4 py-3" role="alert">
              <p className="text-sm text-red-300">{playback.audioError}</p>
              <button
                type="button"
                onClick={playback.next}
                className="flex-shrink-0 rounded-full bg-white/10 px-3 py-1 text-sm font-semibold hover:bg-white/20"
              >
                Skip
              </button>
            </div>
          )}

          <section className="space-y-8">
            <AddTrackForm onAdd={handleAdd} />
            <QueueList
              tracks={tracks}
              currentTrackId={playback.state?.trackId ?? null}
              isPlaying={playback.isPlaying}
              onPlay={playback.playTrack}
              onReorder={handleReorder}
              onRemove={handleRemove}
              onShuffle={handleShuffle}
              onClear={handleClear}
            />
          </section>

          {(queueError || actionError) && (
            <p className="mt-4 text-sm text-red-400" role="alert">
              {actionError ?? queueError}
            </p>
          )}
        </div>
      </main>

      {toast && (
        <div
          role="status"
          aria-live="polite"
          className="fixed left-4 right-4 z-40 flex justify-center pointer-events-none"
          style={{ bottom: BOTTOM_BAR_HEIGHT + 12 }}
        >
          <div className="rounded-lg bg-[#282828] text-white text-sm font-medium px-4 py-2 shadow-lg border border-[#404040]">
            {toast}
          </div>
        </div>
      )}

      <BottomPlayerBar
        currentTrack={currentTrack}
        hasTracks={tracks.length > 0}
        isPlaying={playback.isPlaying}
        durationSec={playback.durationSec}
        getPosition={playback.getPosition}
        volume={playback.volume}
        onVolumeChange={playback.setVolume}
        onPlayPause={playback.togglePlay}
        onSeek={playback.seek}
        onPrevious={playback.previous}
        onNext={playback.next}
      />

      {showOverlay && (
        <JoinOverlay
          roomCode={code}
          askName={!joined}
          initialName={name}
          nowPlaying={playback.isPlaying && currentTrack ? currentTrack.title : null}
          listenerNames={others.map((l) => l.name)}
          onJoin={handleJoin}
        />
      )}
    </>
  )
}
