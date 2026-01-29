'use client'

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

function SortableTrack({
  track,
  index,
  isCurrent,
  onRemove,
}: {
  track: Track
  index: number
  isCurrent: boolean
  onRemove: (id: string) => void
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: track.id })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`flex items-center gap-3 py-3 px-4 rounded-lg transition-colors ${
        isCurrent
          ? 'bg-[#282828] text-white'
          : 'bg-[#181818] text-[#b3b3b3] hover:bg-[#282828] hover:text-white'
      } ${isDragging ? 'opacity-60' : ''}`}
    >
      <button
        type="button"
        className="touch-none cursor-grab active:cursor-grabbing p-1.5 rounded text-[#6b6b6b] hover:text-[#b3b3b3]"
        {...attributes}
        {...listeners}
        aria-label="Drag to reorder"
      >
        <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
          <path d="M7 2a1 1 0 011 1v1h3a1 1 0 110 2H8v3a1 1 0 11-2 0V6H4a1 1 0 110-2h3V3a1 1 0 011-1zm9 5a1 1 0 01-1 1h-3v3a1 1 0 11-2 0V7H7a1 1 0 110-2h3V2a1 1 0 011 1z" />
        </svg>
      </button>
      <span
        className={`flex-shrink-0 w-6 text-sm tabular-nums ${
          isCurrent ? 'text-[#1db954] font-semibold' : 'text-[#6b6b6b]'
        }`}
      >
        {index + 1}
      </span>
      <span
        className={`flex-1 min-w-0 text-base truncate ${
          isCurrent ? 'text-white font-medium' : 'text-[#e5e5e5]'
        }`}
        title={track.title}
      >
        {track.title}
      </span>
      {isCurrent && (
        <span className="flex-shrink-0 text-xs text-[#1db954] font-medium">
          ● Now playing
        </span>
      )}
      <button
        type="button"
        onClick={() => onRemove(track.id)}
        className="flex-shrink-0 p-2 rounded-full text-[#6b6b6b] hover:bg-[#333333] hover:text-white transition"
        aria-label={`Remove ${track.title}`}
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  )
}

type Props = {
  tracks: Track[]
  currentTrackId: string | null
  onReorder: (orderedIds: string[]) => Promise<void>
  onRemove: (trackId: string) => Promise<void>
}

export function QueueList({ tracks, currentTrackId, onReorder, onRemove }: Props) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
  )

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) return
    const oldIndex = tracks.findIndex((t) => t.id === active.id)
    const newIndex = tracks.findIndex((t) => t.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return
    const reordered = arrayMove(tracks, oldIndex, newIndex)
    onReorder(reordered.map((t) => t.id))
  }

  return (
    <div className="space-y-3">
      <h2 className="text-xl font-bold">Queue</h2>
      <p className="text-sm text-[#b3b3b3]">
        {tracks.length} {tracks.length === 1 ? 'track' : 'tracks'}
      </p>
      {tracks.length === 0 ? (
        <div className="py-12 px-6 rounded-xl bg-[#181818] border border-[#282828] text-center">
          <p className="text-[#b3b3b3] mb-2">No tracks yet</p>
          <p className="text-sm text-[#6b6b6b]">
            Add a track below using a direct audio URL (.mp3, .m4a)
          </p>
        </div>
      ) : (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEnd}
        >
          <SortableContext
            items={tracks.map((t) => t.id)}
            strategy={verticalListSortingStrategy}
          >
            <ul className="space-y-1 max-h-[60vh] overflow-y-auto pr-1">
              {tracks.map((track, index) => (
                <li key={track.id}>
                  <SortableTrack
                    track={track}
                    index={index}
                    isCurrent={track.id === currentTrackId}
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
