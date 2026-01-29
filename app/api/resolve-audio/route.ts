import { NextRequest, NextResponse } from 'next/server'

const SUNO_DOMAIN = 'suno.com'
const DIRECT_EXTENSIONS = ['.mp3', '.m4a', '.wav', '.ogg', '.aac', '.webm']
const MAX_BODY_SIZE = 2 * 1024 * 1024 // 2MB for HTML

function isLikelyDirectAudioUrl(url: string): boolean {
  try {
    const lower = url.toLowerCase()
    if (DIRECT_EXTENSIONS.some((ext) => lower.includes(ext))) return true
    if (lower.includes('/audio/') || lower.includes('/stream/')) return true
    return false
  } catch {
    return false
  }
}

function isSunoUrl(url: string): boolean {
  try {
    const u = new URL(url)
    return u.hostname === SUNO_DOMAIN || u.hostname.endsWith('.' + SUNO_DOMAIN)
  } catch {
    return false
  }
}

function extractAudioFromHtml(html: string, pageUrl: string): string | null {
  // 1. og:audio
  const ogAudio = html.match(/<meta[^>]+property=["']og:audio["'][^>]+content=["']([^"']+)["']/i)
  if (ogAudio?.[1]) return ogAudio[1].trim()

  // 2. twitter:player:stream
  const twitterStream = html.match(
    /<meta[^>]+name=["']twitter:player:stream["'][^>]+content=["']([^"']+)["']/i
  )
  if (twitterStream?.[1]) return twitterStream[1].trim()

  // 3. __NEXT_DATA__ (Next.js) - look for audio_url, audioUrl, stream_url, etc.
  const nextDataMatch = html.match(/<script id="__NEXT_DATA__"[^>]*>([^<]+)<\/script>/i)
  if (nextDataMatch?.[1]) {
    try {
      const data = JSON.parse(nextDataMatch[1])
      const search = (obj: unknown): string | null => {
        if (!obj || typeof obj !== 'object') return null
        const o = obj as Record<string, unknown>
        const keys = [
          'audio_url',
          'audioUrl',
          'stream_url',
          'streamUrl',
          'audio',
          'url',
          'src',
          'playback_url',
          'playbackUrl',
        ]
        for (const k of keys) {
          const v = o[k]
          if (typeof v === 'string' && (v.startsWith('http') || v.startsWith('//')))
            return v.startsWith('//') ? 'https:' + v : v
          if (v && typeof v === 'object') {
            const found = search(v)
            if (found) return found
          }
        }
        return null
      }
      const found = search(data)
      if (found) return found
    } catch {
      // ignore parse error
    }
  }

  // 4. <audio src="...">
  const audioSrc = html.match(/<audio[^>]+src=["']([^"']+)["']/i)
  if (audioSrc?.[1]) return audioSrc[1].trim()

  // 5. Any quoted URL that looks like audio (mp3, cdn, stream)
  const urlCandidates = html.match(/https?:\/\/[^\s"']+\.(mp3|m4a|aac)/gi)
  if (urlCandidates?.[0]) return urlCandidates[0].trim()

  // 6. Suno CDN / storage patterns (common patterns for music hosts)
  const cdnMatch = html.match(
    /(https?:\/\/[a-zA-Z0-9.-]*(?:cdn|storage|media|audio|stream)[a-zA-Z0-9.-]*\/[^\s"']+)/gi
  )
  if (cdnMatch?.[0]) return cdnMatch[0].trim()

  // 7. Any "audio_url" or "stream_url" style key with a quoted URL (for API-like JSON in script)
  const keyUrlMatch = html.match(
    /"(?:audio_url|stream_url|playback_url|audioUrl|streamUrl)"\s*:\s*"([^"]+)"/i
  )
  if (keyUrlMatch?.[1]) {
    const u = keyUrlMatch[1].trim()
    if (u.startsWith('http')) return u
  }

  // 8. Generic: first URL containing /audio/ or .mp3 in the page
  const genericAudio = html.match(
    /(https?:\/\/[^\s"']*(?:\/audio\/|\.mp3)[^\s"']*)/i
  )
  if (genericAudio?.[1]) return genericAudio[1].trim()

  return null
}

function extractMetadataFromHtml(html: string): { title?: string; imageUrl?: string } {
  const out: { title?: string; imageUrl?: string } = {}
  const ogTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
  if (ogTitle?.[1]) out.title = ogTitle[1].trim()
  const ogImage = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)
  if (ogImage?.[1]) out.imageUrl = ogImage[1].trim()
  const twitterTitle = html.match(/<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']/i)
  if (twitterTitle?.[1] && !out.title) out.title = twitterTitle[1].trim()
  const twitterImage = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i)
  if (twitterImage?.[1] && !out.imageUrl) out.imageUrl = twitterImage[1].trim()
  return out
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const url = typeof body?.url === 'string' ? body.url.trim() : ''
    if (!url) {
      return NextResponse.json({ error: 'Missing url' }, { status: 400 })
    }

    let parsed: URL
    try {
      parsed = new URL(url)
    } catch {
      return NextResponse.json({ error: 'Invalid URL' }, { status: 400 })
    }

    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return NextResponse.json({ error: 'URL must be http or https' }, { status: 400 })
    }

    // Already a direct audio URL - return as-is (no metadata)
    if (isLikelyDirectAudioUrl(url)) {
      return NextResponse.json({ directUrl: url })
    }

    // Not a Suno link - return as-is
    if (!isSunoUrl(url)) {
      return NextResponse.json({
        directUrl: url,
        message: 'Not a Suno link; using URL as-is (must be direct audio for playback).',
      })
    }

    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 10000)

    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/119.0',
        Accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      },
      signal: controller.signal,
    })
    clearTimeout(timeout)

    if (!res.ok) {
      return NextResponse.json(
        { error: `Page returned ${res.status}. Suno may be blocking requests.` },
        { status: 502 }
      )
    }

    const contentType = res.headers.get('content-type') || ''
    if (!contentType.includes('text/html')) {
      return NextResponse.json(
        { error: 'URL did not return HTML; cannot extract audio.' },
        { status: 400 }
      )
    }

    const html = await res.text()
    if (html.length > MAX_BODY_SIZE) {
      return NextResponse.json(
        { error: 'Page too large to parse.' },
        { status: 502 }
      )
    }

    const directUrl = extractAudioFromHtml(html, url)
    if (!directUrl) {
      return NextResponse.json(
        {
          error:
            'Could not find a direct audio URL on this Suno page. Suno may have changed their page structure.',
        },
        { status: 404 }
      )
    }

    const metadata = extractMetadataFromHtml(html)
    return NextResponse.json({
      directUrl,
      title: metadata.title,
      imageUrl: metadata.imageUrl,
    })
  } catch (err) {
    if (err instanceof SyntaxError) {
      return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
    }
    if (err instanceof Error && err.name === 'AbortError') {
      return NextResponse.json(
        { error: 'Request to Suno timed out. Try again.' },
        { status: 504 }
      )
    }
    console.error('resolve-audio error:', err)
    return NextResponse.json(
      { error: 'Failed to resolve audio URL' },
      { status: 500 }
    )
  }
}
