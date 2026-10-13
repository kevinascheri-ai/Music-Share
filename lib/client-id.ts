const NAME_KEY = 'suno-jam-name'
const VOLUME_KEY = 'suno-jam-volume'

let clientId = ''

/**
 * A fresh id per page load, so two tabs (even duplicated ones) count as two
 * listeners and never mistake each other's messages for their own.
 */
export function getClientId(): string {
  if (typeof window === 'undefined') return ''
  if (!clientId) clientId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
  return clientId
}

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

function write(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value)
  } catch {
    // storage unavailable (private mode); the value just won't persist
  }
}

export function getSavedName(): string {
  if (typeof window === 'undefined') return ''
  return (read(NAME_KEY) ?? '').slice(0, 24)
}

export function saveName(name: string) {
  write(NAME_KEY, name.trim().slice(0, 24))
}

export function getSavedVolume(): number {
  if (typeof window === 'undefined') return 1
  const v = Number(read(VOLUME_KEY))
  return read(VOLUME_KEY) != null && Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 1
}

export function saveVolume(volume: number) {
  write(VOLUME_KEY, String(volume))
}
