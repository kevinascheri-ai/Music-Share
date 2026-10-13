'use client'

import { useEffect, useRef, useState } from 'react'

type Props = {
  roomCode: string
  /** Show the name field (first visit) or just a button to start audio. */
  askName: boolean
  initialName: string
  nowPlaying: string | null
  listenerNames: string[]
  onJoin: (name: string) => void
}

/**
 * Browsers won't start audio until you interact with the page, so joining a
 * room takes one tap. We use it to ask for a name too.
 */
export function JoinOverlay({ roomCode, askName, initialName, nowPlaying, listenerNames, onJoin }: Props) {
  const [name, setName] = useState(initialName)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (askName) inputRef.current?.focus()
  }, [askName])

  const others = listenerNames.filter(Boolean)

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm px-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="join-title"
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          onJoin(name.trim())
        }}
        className="w-full max-w-sm rounded-2xl bg-[#181818] border border-[#282828] p-6 text-center shadow-2xl"
      >
        <p className="text-xs uppercase tracking-widest text-[#6b6b6b]">Room {roomCode}</p>
        <h2 id="join-title" className="mt-1 text-2xl font-bold">
          {askName ? 'Join the jam' : 'Tap to start audio'}
        </h2>
        <p className="mt-2 text-sm text-[#b3b3b3]">
          {nowPlaying ? (
            <>
              Now playing <span className="text-white">{nowPlaying}</span>
            </>
          ) : others.length ? (
            `${others.join(', ')} ${others.length === 1 ? 'is' : 'are'} here`
          ) : (
            'Everyone in this room hears the same thing.'
          )}
        </p>
        {askName && (
          <input
            ref={inputRef}
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={24}
            placeholder="Your name"
            autoComplete="nickname"
            className="mt-5 w-full py-3 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[var(--accent)] focus:outline-none text-center"
          />
        )}
        <button
          type="submit"
          className="mt-4 w-full py-3 rounded-full bg-[var(--accent)] text-black font-bold hover:bg-[var(--accent-hover)] transition"
        >
          {askName ? 'Join' : 'Start listening'}
        </button>
      </form>
    </div>
  )
}
