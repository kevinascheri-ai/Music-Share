/**
 * Server-side helpers for turning a pasted link into playable tracks.
 *
 * Suno has no official public API, so this uses the same JSON endpoints the
 * suno.com web app uses (studio-api.prod.suno.com). Every fetch is restricted to
 * Suno hosts so the resolver can't be used to make requests to arbitrary sites.
 */

export type ResolvedTrack = {
  title: string
  url: string
  artist?: string | null
}

export type ResolveResult = {
  kind: 'song' | 'playlist' | 'direct'
  /** Playlist name (playlists only). */
  name?: string | null
  tracks: ResolvedTrack[]
  /** Clips skipped because they were still generating or failed. */
  skipped?: number
}

export class ResolveError extends Error {
  constructor(
    message: string,
    public status = 400
  ) {
    super(message)
  }
}

const SUNO_API_BASE = 'https://studio-api.prod.suno.com'
const SUNO_CDN_AUDIO = 'https://cdn1.suno.ai'
const FETCH_TIMEOUT_MS = 10_000
const MAX_PLAYLIST_PAGES = 20
const MAX_TRACKS = 500
const MAX_REDIRECTS = 5
const MAX_HTML_BYTES = 3 * 1024 * 1024
const BROWSER_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

export function isSunoHost(hostname: string): boolean {
  const h = hostname.toLowerCase()
  return h === 'suno.com' || h.endsWith('.suno.com') || h === 'suno.ai' || h.endsWith('.suno.ai')
}

export type SunoLink =
  | { type: 'song'; id: string }
  | { type: 'playlist'; id: string }
  | { type: 'short'; url: string }
  | { type: 'profile'; handle: string }
  | { type: 'unknown' }

/** Work out what a Suno URL points at from its path alone (no network). */
export function parseSunoLink(url: URL): SunoLink {
  if (!isSunoHost(url.hostname)) return { type: 'unknown' }
  const segments = url.pathname.split('/').filter(Boolean)
  const [first, second] = segments

  // CDN audio file: cdn1.suno.ai/<uuid>.mp3
  if (url.hostname.toLowerCase().startsWith('cdn') && first) {
    const id = first.match(UUID_RE)?.[0]
    if (id) return { type: 'song', id: id.toLowerCase() }
  }

  if (!first) return { type: 'unknown' }
  const kind = first.toLowerCase()
  const id = second?.match(UUID_RE)?.[0]?.toLowerCase()

  if ((kind === 'song' || kind === 'embed') && id) return { type: 'song', id }
  if (kind === 'playlist' && id) return { type: 'playlist', id }
  if (kind === 's' && second) return { type: 'short', url: url.toString() }
  if (kind.startsWith('@')) return { type: 'profile', handle: kind.slice(1) }
  return { type: 'unknown' }
}

type SunoClip = {
  id?: unknown
  title?: unknown
  audio_url?: unknown
  status?: unknown
  display_name?: unknown
  handle?: unknown
}

type SunoPlaylistItem = {
  clip?: SunoClip
  relative_index?: unknown
}

type SunoPlaylist = {
  name?: unknown
  playlist_clips?: unknown
  num_total_results?: unknown
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.trim() ? v.trim() : null
}

export function cdnAudioUrl(clipId: string): string {
  return `${SUNO_CDN_AUDIO}/${clipId}.mp3`
}

/**
 * Convert a Suno clip object into a playable track, or null if it can't be
 * played yet (still generating, errored, or missing an id).
 */
export function clipToTrack(clip: SunoClip | null | undefined): ResolvedTrack | null {
  if (!clip || typeof clip !== 'object') return null
  const id = str(clip.id)
  const status = str(clip.status)
  if (status && status !== 'complete') return null

  // Prefer the permanent CDN mp3. audio_url can be a temporary streaming
  // endpoint (audiopipe) for very recent clips.
  const audioUrl = str(clip.audio_url)
  let url: string | null = null
  if (audioUrl && /^https:\/\/cdn\d*\.suno\.ai\//i.test(audioUrl)) url = audioUrl
  else if (id && UUID_RE.test(id)) url = cdnAudioUrl(id.toLowerCase())
  else if (audioUrl?.startsWith('https://')) url = audioUrl
  if (!url) return null

  return {
    title: str(clip.title) ?? 'Untitled',
    url,
    artist: str(clip.display_name) ?? str(clip.handle),
  }
}

/** Pull ordered clips out of one page of the playlist API response. */
export function parsePlaylistPage(json: unknown): {
  name: string | null
  total: number | null
  items: { clip: SunoClip; relativeIndex: number | null }[]
} {
  const data = (json && typeof json === 'object' ? json : {}) as SunoPlaylist
  const raw = Array.isArray(data.playlist_clips) ? (data.playlist_clips as SunoPlaylistItem[]) : []
  const items = raw
    .filter((it) => it && typeof it === 'object' && it.clip && typeof it.clip === 'object')
    .map((it) => ({
      clip: it.clip as SunoClip,
      relativeIndex: typeof it.relative_index === 'number' ? it.relative_index : null,
    }))
  const total = typeof data.num_total_results === 'number' ? data.num_total_results : null
  return { name: str(data.name), total, items }
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

async function sunoFetch(url: string, accept: string, redirect: RequestRedirect = 'follow') {
  const parsed = new URL(url)
  if (parsed.protocol !== 'https:' || !isSunoHost(parsed.hostname)) {
    throw new ResolveError('Refusing to fetch a non-Suno URL.')
  }
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS)
  try {
    return await fetch(url, {
      headers: { 'User-Agent': BROWSER_UA, Accept: accept },
      redirect,
      signal: controller.signal,
      cache: 'no-store',
    })
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new ResolveError('Suno took too long to respond. Try again.', 504)
    }
    throw new ResolveError('Could not reach Suno. Try again in a moment.', 502)
  } finally {
    clearTimeout(timeout)
  }
}

async function fetchSunoJson(path: string): Promise<unknown | null> {
  const res = await sunoFetch(`${SUNO_API_BASE}${path}`, 'application/json')
  if (!res.ok) return null
  try {
    return await res.json()
  } catch {
    return null
  }
}

async function fetchSunoHtml(url: string): Promise<string | null> {
  const res = await sunoFetch(url, 'text/html,application/xhtml+xml')
  if (!res.ok || !(res.headers.get('content-type') ?? '').includes('text/html')) return null
  const html = await res.text()
  return html.length > MAX_HTML_BYTES ? html.slice(0, MAX_HTML_BYTES) : html
}

function metaContent(html: string, key: string): string | null {
  const re = new RegExp(
    `<meta[^>]+(?:property|name)=["']${key}["'][^>]+content=["']([^"']+)["']|<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${key}["']`,
    'i'
  )
  const m = html.match(re)
  const v = m?.[1] ?? m?.[2]
  return v ? decodeHtmlEntities(v.trim()) : null
}

function decodeHtmlEntities(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
}

/** Strip Suno's " | Suno" style suffix from page titles. */
function cleanPageTitle(title: string | null): string | null {
  if (!title) return null
  return title.replace(/\s*[|\-–]\s*Suno\s*$/i, '').trim() || null
}

/** Extract unique song ids from a Suno page, in document order. */
export function extractSongIdsFromHtml(html: string): string[] {
  const ids: string[] = []
  const seen = new Set<string>()
  const patterns = [
    new RegExp(`cdn\\d*\\.suno\\.ai\\\\?/(${UUID_RE.source})\\.mp3`, 'gi'),
    new RegExp(`/song/(${UUID_RE.source})`, 'gi'),
  ]
  for (const re of patterns) {
    for (const m of Array.from(html.matchAll(re))) {
      const id = m[1].toLowerCase()
      if (!seen.has(id)) {
        seen.add(id)
        ids.push(id)
      }
    }
    if (ids.length) break
  }
  return ids
}

async function resolveSong(id: string): Promise<ResolveResult> {
  const clip = await fetchSunoJson(`/api/clip/${id}/`).catch(() => null)
  const track = clipToTrack(clip as SunoClip | null)
  if (track) return { kind: 'song', tracks: [track] }

  const status = clip && typeof clip === 'object' ? str((clip as SunoClip).status) : null
  if (status && status !== 'complete') {
    throw new ResolveError('That song is still generating on Suno. Try again once it finishes.')
  }

  // API unavailable: fall back to the public page for the title and the CDN for audio.
  const html = await fetchSunoHtml(`https://suno.com/song/${id}`).catch(() => null)
  const title = cleanPageTitle(html ? metaContent(html, 'og:title') : null)
  return { kind: 'song', tracks: [{ title: title ?? 'Suno song', url: cdnAudioUrl(id) }] }
}

async function resolvePlaylist(id: string): Promise<ResolveResult> {
  type Item = { clip: SunoClip; relativeIndex: number | null; order: number }
  const items: Item[] = []
  const seen = new Set<string>()
  let name: string | null = null
  let total: number | null = null
  let fruitlessPages = 0
  let apiWorked = false

  // Page numbering isn't documented, so keep requesting pages until one adds
  // nothing new twice in a row (handles both 0- and 1-based paging).
  for (let page = 0; page < MAX_PLAYLIST_PAGES; page++) {
    const path = page === 0 ? `/api/playlist/${id}/` : `/api/playlist/${id}/?page=${page}`
    const json = await fetchSunoJson(path).catch(() => null)
    if (!json) break
    apiWorked = true
    const parsed = parsePlaylistPage(json)
    name = name ?? parsed.name
    total = total ?? parsed.total
    if (!parsed.items.length) break

    let added = 0
    for (const it of parsed.items) {
      const key = str(it.clip.id) ?? `${page}:${items.length}`
      if (seen.has(key)) continue
      seen.add(key)
      items.push({ ...it, order: items.length })
      added++
    }
    if (added === 0) {
      if (++fruitlessPages >= 2) break
    } else {
      fruitlessPages = 0
    }
    if (total != null && items.length >= total) break
    if (items.length >= MAX_TRACKS) break
  }

  if (apiWorked) {
    if (!items.length) {
      throw new ResolveError('That playlist is empty, or it is private. Make it public on Suno and try again.', 404)
    }
    const allIndexed = items.every((it) => it.relativeIndex != null)
    items.sort((a, b) =>
      allIndexed ? (a.relativeIndex as number) - (b.relativeIndex as number) : a.order - b.order
    )
    const tracks: ResolvedTrack[] = []
    let skipped = 0
    for (const it of items.slice(0, MAX_TRACKS)) {
      const t = clipToTrack(it.clip)
      if (t) tracks.push(t)
      else skipped++
    }
    if (!tracks.length) {
      throw new ResolveError('None of the songs in that playlist are ready to play yet.', 404)
    }
    return { kind: 'playlist', name, tracks, skipped }
  }

  // API unavailable: scrape the public playlist page for song ids.
  const html = await fetchSunoHtml(`https://suno.com/playlist/${id}`).catch(() => null)
  const ids = html ? extractSongIdsFromHtml(html) : []
  if (!ids.length) {
    throw new ResolveError(
      'Could not load that playlist from Suno. Make sure it is public, then try again.',
      502
    )
  }
  return {
    kind: 'playlist',
    name: cleanPageTitle(metaContent(html as string, 'og:title')),
    tracks: ids.slice(0, MAX_TRACKS).map((songId, i) => ({
      title: `Track ${i + 1}`,
      url: cdnAudioUrl(songId),
    })),
  }
}

/** Follow a suno.com/s/<code> share link to the song or playlist it points at. */
async function expandShortLink(url: string): Promise<SunoLink> {
  let current = url
  for (let hop = 0; hop < MAX_REDIRECTS; hop++) {
    const res = await sunoFetch(current, 'text/html,application/xhtml+xml', 'manual')
    const location = res.headers.get('location')
    if (res.status >= 300 && res.status < 400 && location) {
      const next = new URL(location, current)
      const link = parseSunoLink(next)
      if (link.type === 'song' || link.type === 'playlist') return link
      if (!isSunoHost(next.hostname)) break
      current = next.toString()
      continue
    }
    if (res.ok) {
      const html = (await res.text()).slice(0, MAX_HTML_BYTES)
      const canonical = metaContent(html, 'og:url') ?? html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']/i)?.[1]
      if (canonical) {
        try {
          const link = parseSunoLink(new URL(canonical, current))
          if (link.type === 'song' || link.type === 'playlist') return link
        } catch {
          // ignore malformed canonical
        }
      }
      const playlistId = html.match(new RegExp(`/playlist/(${UUID_RE.source})`, 'i'))?.[1]
      if (playlistId) return { type: 'playlist', id: playlistId.toLowerCase() }
      const songId = html.match(new RegExp(`/song/(${UUID_RE.source})`, 'i'))?.[1]
      if (songId) return { type: 'song', id: songId.toLowerCase() }
    }
    break
  }
  return { type: 'unknown' }
}

function titleFromUrl(url: URL): string {
  const last = decodeURIComponent(url.pathname.split('/').filter(Boolean).pop() ?? '')
  const base = last.replace(/\.[a-z0-9]+$/i, '').replace(/[-_]+/g, ' ').trim()
  return base || 'Untitled'
}

/** Resolve any pasted link into one or more playable tracks. */
export async function resolveLink(input: string): Promise<ResolveResult> {
  let url: URL
  try {
    url = new URL(input.trim())
  } catch {
    throw new ResolveError('That doesn’t look like a link. Paste a Suno song or playlist URL.')
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new ResolveError('Links must start with http:// or https://')
  }

  if (!isSunoHost(url.hostname)) {
    // Any other host: we can only play it if it's a direct audio file.
    return { kind: 'direct', tracks: [{ title: titleFromUrl(url), url: url.toString() }] }
  }

  let link = parseSunoLink(url)
  if (link.type === 'short') link = await expandShortLink(link.url)

  switch (link.type) {
    case 'song':
      return resolveSong(link.id)
    case 'playlist':
      return resolvePlaylist(link.id)
    case 'profile':
      throw new ResolveError('That’s a profile link. Open one of their playlists or songs and paste that link instead.')
    default:
      throw new ResolveError('Couldn’t find a song or playlist at that Suno link.', 404)
  }
}
