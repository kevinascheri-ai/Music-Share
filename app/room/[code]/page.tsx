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

  const playback = usePlaybackSync(
    code,
    audioRef,
    tracks,
    roomState ?? null,
    refetchQueue
  )

  const presenceCount = usePresence(code)

  const currentTrack = playback.currentTrackId
    ? tracks.find((t) => t.id === playback.currentTrackId) ?? null
    : null

  const [durationSec, setDurationSec] = useState(0)
  const [audioError, setAudioError] = useState<string | null>(null)

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
    async (title: string, url: string) => {
      await addTrack(title, url)
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
        <Link href="/" className="text-[#1db954] hover:underline mt-2 inline-block">
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
            <Link href="/" className="text-[#1db954] hover:underline mt-2 inline-block">
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
            <div>
              <Link
                href="/"
                className="text-sm text-[#b3b3b3] hover:text-white transition"
              >
                ← Home
              </Link>
              <h1 className="text-2xl font-bold mt-1">Room {code}</h1>
            </div>
            {presenceCount > 0 && (
              <span className="text-sm text-[#b3b3b3]">
                {presenceCount} listening
              </span>
            )}
          </div>

          <section className="space-y-4">
            <QueueList
              tracks={tracks}
              currentTrackId={playback.currentTrackId}
              onReorder={handleReorder}
              onRemove={handleRemoveTrack}
            />
            <AddTrackForm onAdd={handleAddTrack} />
          </section>

          {queueError && (
            <p className="mt-4 text-sm text-red-400" role="alert">
              {queueError}
            </p>
          )}
        </div>
      </main>

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
