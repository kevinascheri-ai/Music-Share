'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createRoom } from '@/hooks/use-room'
import { parseRoomCodeOrUrl } from '@/lib/room-url'

export default function HomePage() {
  const router = useRouter()
  const [joinInput, setJoinInput] = useState('')
  const [creating, setCreating] = useState(false)
  const [joining, setJoining] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleCreateRoom() {
    setError(null)
    setCreating(true)
    try {
      const code = await createRoom()
      router.push(`/room/${code}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create room')
    } finally {
      setCreating(false)
    }
  }

  function handleJoinRoom(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    const code = parseRoomCodeOrUrl(joinInput)
    if (!code) {
      setError('Paste the room link or enter the room code')
      return
    }
    setJoining(true)
    router.push(`/room/${code}`)
  }

  return (
    <main className="min-h-screen bg-[#121212] text-white flex flex-col items-center justify-center px-4 py-16">
      <div className="w-full max-w-sm text-center">
        <h1 className="text-4xl font-bold mb-2">Suno Jam</h1>
        <p className="text-[#b3b3b3] mb-10">
          Create a room and share the link. Everyone listens in sync—no account needed.
        </p>

        <div className="space-y-4">
          <button
            type="button"
            onClick={handleCreateRoom}
            disabled={creating}
            className="w-full py-4 px-6 rounded-full bg-[var(--accent)] text-black font-bold hover:bg-[var(--accent-hover)] disabled:opacity-50 transition text-lg"
          >
            {creating ? 'Creating…' : 'Create Room'}
          </button>

          <div className="relative py-4">
            <span className="absolute left-0 right-0 top-1/2 h-px bg-[#282828]" />
            <span className="relative block text-sm text-[#6b6b6b] bg-[#121212] w-fit mx-auto px-2">
              or paste room link
            </span>
          </div>

          <form onSubmit={handleJoinRoom} className="flex gap-2">
            <input
              type="text"
              value={joinInput}
              onChange={(e) => setJoinInput(e.target.value)}
              placeholder="Paste room URL or code (e.g. ABC123)"
              className="flex-1 min-w-0 py-3 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[var(--accent)] focus:outline-none"
            />
            <button
              type="submit"
              disabled={joining}
              className="py-3 px-5 rounded-full bg-[#282828] text-white font-semibold hover:bg-[#333333] disabled:opacity-50 transition"
            >
              Join
            </button>
          </form>
        </div>

        {error && (
          <p className="mt-4 text-sm text-red-400" role="alert">
            {error}
          </p>
        )}
      </div>
    </main>
  )
}
