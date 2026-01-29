'use client'

import { useState } from 'react'

type ResolveResult = {
  directUrl: string
  title?: string
  imageUrl?: string
}

type Props = {
  onAdd: (title: string, url: string, thumbnailUrl?: string | null) => Promise<void>
}

export function AddTrackForm({ onAdd }: Props) {
  const [url, setUrl] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function resolveUrl(inputUrl: string): Promise<ResolveResult> {
    const res = await fetch('/api/resolve-audio', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: inputUrl }),
    })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error ?? 'Failed to resolve URL')
    return {
      directUrl: data.directUrl,
      title: data.title ?? undefined,
      imageUrl: data.imageUrl ?? undefined,
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    const rawUrl = url.trim()
    if (!rawUrl) {
      setError('URL is required')
      return
    }
    setSubmitting(true)
    try {
      const { directUrl, title: resolvedTitle } = await resolveUrl(rawUrl)
      const displayTitle = (resolvedTitle || 'Untitled').trim()
      await onAdd(displayTitle, directUrl, null)
      setUrl('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add track')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 pt-4 border-t border-[#282828]">
      <h3 className="text-lg font-semibold">Add to queue</h3>
      <input
        type="url"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        placeholder="Paste Suno link or direct audio URL"
        required
        className="w-full py-3 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[#1db954] focus:outline-none transition"
      />
      <p className="text-xs text-[#6b6b6b]">
        Paste the link from Suno’s “Copy link” button or a direct .mp3/.m4a URL. We’ll use the song name from the link when available.
      </p>
      <button
        type="submit"
        disabled={submitting}
        className="w-full py-3 px-4 rounded-full bg-[#1db954] text-black font-semibold hover:bg-[#1ed760] disabled:opacity-50 disabled:cursor-not-allowed transition"
      >
        {submitting ? 'Resolving & adding…' : 'Add track'}
      </button>
      {error && (
        <p className="text-sm text-red-400" role="alert">
          {error}
        </p>
      )}
    </form>
  )
}
