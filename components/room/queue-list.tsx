'use client'

import { useEffect, useState } from 'react'
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core'
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import type { Track } from '@/lib/supabase'

function NowPlayingBars({ animate }: { animate: boolean }) {
  return (
    <span className="flex items-end gap-[2px] h-3.5 w-4" aria-hidden>
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className={`w-[3px] rounded-sm bg-[var(--accent)] ${animate ? 'eq-bar' : ''}`}
          style={{ height: animate ? undefined : '40%', animationDelay: `${i * 0.18}s` }}
        />
      ))}
    </span>
  )
}

function SortableTrack({
  track,
  index,
  isCurrent,
  isPlaying,
  onPlay,
  onRemove,
}: {
  track: Track
  index: number
  isCurrent: boolean
  isPlaying: boolean
  onPlay: (id: string) => void
  onRemove: (id: string) => void
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: track.id,
  })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`group flex items-center gap-2 py-2 pl-1 pr-2 rounded-lg transition-colors ${
        isCurrent ? 'bg-[#282828] text-white' : 'bg-[#181818] text-[#b3b3b3] hover:bg-[#282828] hover:text-white'
      } ${isDragging ? 'opacity-60' : ''}`}
    >
      <button
        type="button"
        className="touch-none cursor-grab active:cursor-grabbing p-1.5 rounded text-[#6b6b6b] hover:text-[#b3b3b3]"
        {...attributes}
        {...listeners}
        aria-label="Drag to reorder"
      >
        <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20" aria-hidden>
          <path d="M7 4a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm0 6a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm-1.5 7.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM16 4a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm-1.5 7.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM16 16a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z" />
        </svg>
      </button>
      <button
        type="button"
        onClick={() => onPlay(track.id)}
        className="flex flex-1 min-w-0 items-center gap-3 py-1 text-left"
        title={`Play “${track.title}” for everyone`}
      >
        <span className="relative flex-shrink-0 w-6 flex justify-center text-sm tabular-nums text-[#6b6b6b]">
          {isCurrent ? (
            <NowPlayingBars animate={isPlaying} />
          ) : (
            <>
              <span className="group-hover:invisible">{index + 1}</span>
              <svg className="absolute w-4 h-4 top-0.5 invisible group-hover:visible text-white" fill="currentColor" viewBox="0 0 24 24" aria-hidden>
                <path d="M8 5v14l11-7z" />
              </svg>
            </>
          )}
        </span>
        <span
          className={`flex-1 min-w-0 text-base truncate ${
            isCurrent ? 'text-[var(--accent)] font-medium' : 'text-[#e5e5e5]'
          }`}
        >
          {track.title}
        </span>
      </button>
      <button
        type="button"
        onClick={() => onRemove(track.id)}
        className="flex-shrink-0 p-2 rounded-full text-[#6b6b6b] opacity-60 group-hover:opacity-100 hover:bg-[#333333] hover:text-white transition"
        aria-label={`Remove ${track.title}`}
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  )
}

type Props = {
  tracks: Track[]
  currentTrackId: string | null
  isPlaying: boolean
  onPlay: (trackId: string) => void
  onReorder: (orderedIds: string[]) => void
  onRemove: (trackId: string) => void
  onShuffle: () => void
  onClear: () => void
}

export function QueueList({
  tracks,
  currentTrackId,
  isPlaying,
  onPlay,
  onReorder,
  onRemove,
  onShuffle,
  onClear,
}: Props) {
  const [confirmClear, setConfirmClear] = useState(false)
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
  )

  useEffect(() => {
    if (!confirmClear) return
    const t = setTimeout(() => setConfirmClear(false), 3000)
    return () => clearTimeout(t)
  }, [confirmClear])

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) return
    const oldIndex = tracks.findIndex((t) => t.id === active.id)
    const newIndex = tracks.findIndex((t) => t.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return
    onReorder(arrayMove(tracks, oldIndex, newIndex).map((t) => t.id))
  }

  return (
    <div className="space-y-3">
      <div className="flex items-end justify-between gap-2">
        <div>
          <h2 className="text-xl font-bold">Queue</h2>
          <p className="text-sm text-[#b3b3b3]">
            {tracks.length} {tracks.length === 1 ? 'song' : 'songs'}
            {tracks.length > 0 && ' · tap a song to play it for everyone'}
          </p>
        </div>
        {tracks.length > 1 && (
          <div className="flex gap-1 flex-shrink-0">
            <button
              type="button"
              onClick={onShuffle}
              className="px-3 py-1.5 rounded-full text-sm text-[#b3b3b3] hover:text-white hover:bg-[#282828] transition"
            >
              Shuffle
            </button>
            <button
              type="button"
              onClick={() => {
                if (confirmClear) {
                  setConfirmClear(false)
                  onClear()
                } else setConfirmClear(true)
              }}
              className={`px-3 py-1.5 rounded-full text-sm transition ${
                confirmClear ? 'bg-red-500/20 text-red-300' : 'text-[#b3b3b3] hover:text-white hover:bg-[#282828]'
              }`}
            >
              {confirmClear ? 'Tap to confirm' : 'Clear'}
            </button>
          </div>
        )}
      </div>
      {tracks.length === 0 ? (
        <div className="py-12 px-6 rounded-xl bg-[#181818] border border-[#282828] text-center">
          <p className="text-[#b3b3b3] mb-2">No songs yet</p>
          <p className="text-sm text-[#6b6b6b]">Paste a Suno playlist link above to load it up.</p>
        </div>
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={tracks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
            <ul className="space-y-1">
              {tracks.map((track, index) => (
                <li key={track.id}>
                  <SortableTrack
                    track={track}
                    index={index}
                    isCurrent={track.id === currentTrackId}
                    isPlaying={isPlaying}
                    onPlay={onPlay}
                    onRemove={onRemove}
                  />
                </li>
              ))}
            </ul>
          </SortableContext>
        </DndContext>
      )}
    </div>
  )
}
