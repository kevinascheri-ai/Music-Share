const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
const UUID_RE = new RegExp(`^${UUID}$`, 'i')
// Old imports saved Suno's bare CDN file, which Suno now refuses (403).
const LEGACY_SUNO_CDN_RE = new RegExp(`^https?://cdn\\d*\\.suno\\.ai/(${UUID})\\.mp3(?:[?#].*)?$`, 'i')

export function isSunoClipId(id: string): boolean {
  return UUID_RE.test(id)
}

/**
 * Our own endpoint for a Suno song. It looks up Suno's current audio file when
 * the song is played and redirects there, so saved songs keep working even when
 * Suno moves or re-signs its files.
 */
export function sunoAudioPath(clipId: string): string {
  return `/api/suno/audio/${clipId.toLowerCase()}`
}

/** The URL to give the audio element for a saved track. */
export function playableUrl(url: string): string {
  const legacy = url.match(LEGACY_SUNO_CDN_RE)
  return legacy ? sunoAudioPath(legacy[1]) : url
}
