const STORAGE_KEY = 'suno-jam-client-id'

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`
}

export function getClientId(): string {
  if (typeof window === 'undefined') return ''
  let id = sessionStorage.getItem(STORAGE_KEY)
  if (!id) {
    id = generateId()
    sessionStorage.setItem(STORAGE_KEY, id)
  }
  return id
}

export function generateEventId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}
