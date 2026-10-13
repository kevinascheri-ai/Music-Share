import { NextRequest, NextResponse } from 'next/server'
import { resolveLink, ResolveError } from '@/lib/suno'

export const dynamic = 'force-dynamic'

/** POST { url } → { kind, name?, tracks: [{ title, url, artist? }], skipped? } */
export async function POST(request: NextRequest) {
  let url = ''
  try {
    const body = await request.json()
    url = typeof body?.url === 'string' ? body.url.trim() : ''
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }
  if (!url) {
    return NextResponse.json({ error: 'Paste a Suno song or playlist link.' }, { status: 400 })
  }

  try {
    return NextResponse.json(await resolveLink(url))
  } catch (err) {
    if (err instanceof ResolveError) {
      return NextResponse.json({ error: err.message }, { status: err.status })
    }
    console.error('resolve error:', err)
    return NextResponse.json({ error: 'Failed to load that link.' }, { status: 500 })
  }
}
