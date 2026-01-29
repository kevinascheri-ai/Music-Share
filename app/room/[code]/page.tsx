'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import { useRoom } from '@/hooks/use-room'
import { useQueue } from '@/hooks/use-queue'
import { usePlaybackSync } from '@/hooks/use-playback-sync'
import { usePresence } from '@/hooks/use-presence'
import { BottomPlayerBar } from '@/components/room/bottom-player-bar'
import { QueueList } from '@/components/room/queue-list'
import { AddTrackForm } from '@/components/room/add-track-form'
import { getRoomUrl } from '@/lib/room-url'

const BOTTOM_BAR_HEIGHT = 140

export default function RoomPage() {
  const params = useParams()
  const code = typeof params.code === 'string' ? params.code : null
  const audioRef = useRef<HTMLAudioElement>(null)

  const { room, roomState, loading: roomLoading, error: roomError } = useRoom(code)

  const queueRefetchRef = useRef<(() => Promise<void>) | null>(null)
  const queueRefetch = useCallback(() => {
    queueRefetchRef.current?.()
  }, [])

  const {
    tracks,
    loading: queueLoading,
    error: queueError,
    addTrack,
    removeTrack,
    reorderTracks,
    refetch: refetchQueue,
  } = useQueue(code, queueRefetch)
  queueRefetchRef.current = refetchQueue

  const [skipNotification, setSkipNotification] = useState<string | null>(null)
  const skipNotificationTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const playback = usePlaybackSync(
    code,
    audioRef,
    tracks,
    roomState ?? null,
    refetchQueue,
    useCallback((direction: 'next' | 'previous') => {
      setSkipNotification(direction === 'next' ? 'Someone skipped to next' : 'Someone went to previous')
      if (skipNotificationTimeoutRef.current) clearTimeout(skipNotificationTimeoutRef.current)
      skipNotificationTimeoutRef.current = setTimeout(() => {
        setSkipNotification(null)
        skipNotificationTimeoutRef.current = null
      }, 3000)
    }, [])
  )

  useEffect(() => {
    return () => {
      if (skipNotificationTimeoutRef.current) clearTimeout(skipNotificationTimeoutRef.current)
      if (linkCopiedTimeoutRef.current) clearTimeout(linkCopiedTimeoutRef.current)
    }
  }, [])

  const presenceCount = usePresence(code)

  const currentTrack = playback.currentTrackId
    ? tracks.find((t) => t.id === playback.currentTrackId) ?? null
    : null

  const [durationSec, setDurationSec] = useState(0)
  const [audioError, setAudioError] = useState<string | null>(null)
  const [linkCopied, setLinkCopied] = useState(false)
  const linkCopiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const roomUrl = code ? getRoomUrl(code) : ''
  const copyRoomLink = useCallback(() => {
    if (!roomUrl || typeof navigator?.clipboard?.writeText !== 'function') return
    navigator.clipboard.writeText(roomUrl).then(() => {
      setLinkCopied(true)
      if (linkCopiedTimeoutRef.current) clearTimeout(linkCopiedTimeoutRef.current)
      linkCopiedTimeoutRef.current = setTimeout(() => {
        setLinkCopied(false)
        linkCopiedTimeoutRef.current = null
      }, 2000)
    })
  }, [roomUrl])

  useEffect(() => {
    const audio = audioRef.current
    if (!audio) return
    const onLoadedMetadata = () => {
      setDurationSec(audio.duration)
      setAudioError(null)
    }
    const onDurationChange = () => setDurationSec(audio.duration)
    const onError = () => {
      setAudioError(
        'Could not load this track. Use a direct audio URL (e.g. .mp3 or .m4a), not a webpage link.'
      )
    }
    const onCanPlay = () => setAudioError(null)
    audio.addEventListener('loadedmetadata', onLoadedMetadata)
    audio.addEventListener('durationchange', onDurationChange)
    audio.addEventListener('error', onError)
    audio.addEventListener('canplay', onCanPlay)
    if (Number.isFinite(audio.duration)) setDurationSec(audio.duration)
    return () => {
      audio.removeEventListener('loadedmetadata', onLoadedMetadata)
      audio.removeEventListener('durationchange', onDurationChange)
      audio.removeEventListener('error', onError)
      audio.removeEventListener('canplay', onCanPlay)
    }
  }, [currentTrack?.id])

  useEffect(() => {
    setAudioError(null)
  }, [currentTrack?.id])

  const handlePlayPause = useCallback(() => {
    if (!playback.currentTrackId && tracks.length > 0) {
      playback.sendPlay(tracks[0].id, 0)
      return
    }
    if (playback.isPlaying) {
      playback.sendPause(playback.currentTimeSec)
    } else {
      playback.sendPlay(playback.currentTrackId!, playback.currentTimeSec)
    }
  }, [playback, tracks])

  const handleSeek = useCallback(
    (timeSec: number) => {
      playback.sendSeek(playback.currentTrackId, timeSec)
    },
    [playback]
  )

  const handleAddTrack = useCallback(
    async (title: string, url: string, thumbnailUrl?: string | null) => {
      await addTrack(title, url, thumbnailUrl)
      playback.broadcastQueueUpdated()
    },
    [addTrack, playback]
  )

  const handleRemoveTrack = useCallback(
    async (trackId: string) => {
      await removeTrack(trackId)
      playback.broadcastQueueUpdated()
    },
    [removeTrack, playback]
  )

  const handleReorder = useCallback(
    async (orderedIds: string[]) => {
      await reorderTracks(orderedIds)
      playback.broadcastQueueUpdated()
    },
    [reorderTracks, playback]
  )

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

  return (
    <>
      <main
        className="min-h-screen bg-[#121212] text-white"
        style={{ paddingBottom: BOTTOM_BAR_HEIGHT }}
      >
        <div className="max-w-2xl mx-auto px-4 py-6">
          {/* Hidden audio - controlled by bottom bar */}
          <audio ref={audioRef} preload="metadata" className="sr-only" />
          {audioError && (
            <p className="mb-4 text-sm text-red-400 font-medium" role="alert">
              {audioError}
            </p>
          )}

          <div className="flex items-center justify-between mb-8">
            <div className="flex items-center gap-2 min-w-0">
              <Link
                href="/"
                className="text-sm text-[#b3b3b3] hover:text-white transition flex-shrink-0"
              >
                ← Home
              </Link>
              <h1 className="text-2xl font-bold mt-1 truncate">Room {code}</h1>
              {roomUrl && (
                <button
                  type="button"
                  onClick={copyRoomLink}
                  title={linkCopied ? 'Copied!' : 'Copy room link'}
                  aria-label={linkCopied ? 'Copied!' : 'Copy room link'}
                  className="flex-shrink-0 p-1.5 rounded text-[#b3b3b3] hover:text-[var(--accent)] hover:bg-[#282828] transition"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                </button>
              )}
            </div>
            {presenceCount > 0 && (
              <span className="text-sm text-[#b3b3b3] flex-shrink-0">
                {presenceCount} listening
              </span>
            )}
          </div>

          <section className="space-y-4">
            <AddTrackForm onAdd={handleAddTrack} />
            <QueueList
              tracks={tracks}
              currentTrackId={playback.currentTrackId}
              onReorder={handleReorder}
              onRemove={handleRemoveTrack}
            />
          </section>

          {queueError && (
            <p className="mt-4 text-sm text-red-400" role="alert">
              {queueError}
            </p>
          )}
        </div>
      </main>

      {/* Snackbar above player: skip notification */}
      {skipNotification && (
        <div
          role="status"
          aria-live="polite"
          className="fixed left-4 right-4 z-50 flex justify-center"
          style={{ bottom: BOTTOM_BAR_HEIGHT + 12 }}
        >
          <div className="rounded-lg bg-[#282828] text-white text-sm font-medium px-4 py-2 shadow-lg border border-[#404040]">
            {skipNotification}
          </div>
        </div>
      )}

      <BottomPlayerBar
        currentTrack={currentTrack}
        firstTrack={tracks.length > 0 ? tracks[0] : null}
        isPlaying={playback.isPlaying}
        currentTimeSec={playback.currentTimeSec}
        durationSec={durationSec}
        audioRef={audioRef}
        onPlayPause={handlePlayPause}
        onSeek={handleSeek}
        onPrevious={playback.sendPrevious}
        onNext={playback.sendNext}
      />
    </>
  )
}
