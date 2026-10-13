'use client'

import { useState } from 'react'
import type { NewTrack } from '@/hooks/use-queue'

type ResolveResponse = {
  kind: 'song' | 'playlist' | 'direct'
  name?: string | null
  tracks: NewTrack[]
  skipped?: number
  error?: string
}

type Props = {
  /** Returns once the tracks are saved. `summary` describes what was added. */
  onAdd: (tracks: NewTrack[], summary: string) => Promise<void>
}

export function AddTrackForm({ onAdd }: Props) {
  const [url, setUrl] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setNotice(null)
    const rawUrl = url.trim()
    if (!rawUrl) {
      setError('Paste a Suno playlist or song link')
      return
    }
    setSubmitting(true)
    try {
      const res = await fetch('/api/resolve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: rawUrl }),
      })
      const data = (await res.json().catch(() => ({}))) as Partial<ResolveResponse>
      if (!res.ok || !data.tracks?.length) throw new Error(data.error ?? 'Could not load that link')

      const count = data.tracks.length
      const summary =
        data.kind === 'playlist'
          ? `${count} ${count === 1 ? 'song' : 'songs'}${data.name ? ` from “${data.name}”` : ''}`
          : `“${data.tracks[0].title}”`
      await onAdd(data.tracks, summary)
      setUrl('')
      const skipped = data.skipped ? ` (${data.skipped} still generating on Suno, skipped)` : ''
      setNotice(`Added ${summary}${skipped}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-2">
      <h3 className="text-lg font-semibold">Add music</h3>
      <div className="flex gap-2">
        <input
          type="url"
          inputMode="url"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="Paste a Suno playlist or song link"
          required
          className="flex-1 min-w-0 py-2.5 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[var(--accent)] focus:outline-none transition"
        />
        <button
          type="submit"
          disabled={submitting}
          className="flex-shrink-0 py-2.5 px-4 rounded-lg bg-[var(--accent)] text-black font-semibold hover:bg-[var(--accent-hover)] disabled:opacity-50 disabled:cursor-not-allowed transition"
        >
          {submitting ? 'Adding…' : 'Add'}
        </button>
      </div>
      <p className="text-xs text-[#6b6b6b]">
        On Suno, open a playlist (or song) → Share → Copy link. Playlists need to be public. Direct .mp3 links work too.
      </p>
      {error && (
        <p className="text-sm text-red-400" role="alert">
          {error}
        </p>
      )}
      {notice && !error && (
        <p className="text-sm text-[var(--accent)]" role="status">
          {notice}
        </p>
      )}
    </form>
  )
}
