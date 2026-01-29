'use client'

import { useState } from 'react'

type Props = {
  onAdd: (title: string, url: string) => Promise<void>
}

export function AddTrackForm({ onAdd }: Props) {
  const [title, setTitle] = useState('')
  const [url, setUrl] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function resolveToDirectUrl(inputUrl: string): Promise<string> {
    const res = await fetch('/api/resolve-audio', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: inputUrl }),
    })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error ?? 'Failed to resolve URL')
    return data.directUrl
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
      const directUrl = await resolveToDirectUrl(rawUrl)
      await onAdd(title.trim() || 'Untitled', directUrl)
      setTitle('')
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
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Track title (optional)"
        className="w-full py-3 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[#1db954] focus:outline-none transition"
      />
      <input
        type="url"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        placeholder="Paste Suno link (e.g. suno.com/s/...) or direct audio URL"
        required
        className="w-full py-3 px-4 rounded-lg bg-[#282828] text-white placeholder-[#6b6b6b] border border-transparent focus:border-[#1db954] focus:outline-none transition"
      />
      <p className="text-xs text-[#6b6b6b]">
        Paste the link from Suno’s “Copy link” button—we’ll resolve it to the playable track. Direct .mp3/.m4a URLs also work.
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
