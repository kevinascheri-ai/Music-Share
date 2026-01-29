/**
 * Extract room code from pasted input: full room URL or plain code.
 * Jira-style: accept https://example.com/room/ABC123 or just ABC123.
 */
export function parseRoomCodeOrUrl(input: string): string | null {
  const raw = input.trim()
  if (!raw) return null

  // Full URL: .../room/CODE or .../room/CODE/
  const urlMatch = raw.match(/\/room\/([A-Za-z0-9]+)(?:\/|$|\?|#)/)
  if (urlMatch) return urlMatch[1].toUpperCase()

  // Try parsing as URL (e.g. https://host/room/ABC123)
  try {
    const url = new URL(raw)
    const path = url.pathname
    const pathMatch = path.match(/\/room\/([A-Za-z0-9]+)(?:\/|$)/)
    if (pathMatch) return pathMatch[1].toUpperCase()
  } catch {
    // Not a valid URL, treat as plain code
  }

  // Plain code: alphanumeric only (existing codes are 6 chars A-Z0-9)
  const code = raw.replace(/\s/g, '').toUpperCase()
  if (/^[A-Z0-9]+$/.test(code) && code.length >= 1) return code

  return null
}

/** Build full room URL for the current origin (for copy/share). */
export function getRoomUrl(code: string, origin?: string): string {
  const base = typeof origin === 'string' ? origin : (typeof window !== 'undefined' ? window.location.origin : '')
  return `${base}/room/${code}`
}
