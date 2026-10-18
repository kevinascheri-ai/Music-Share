import { NextResponse } from 'next/server'
import { resolveAudioUrl } from '@/lib/suno'
import { isSunoClipId } from '@/lib/audio-url'

export const dynamic = 'force-dynamic'

/**
 * GET /api/suno/audio/<clip id> → redirect to Suno's current audio file.
 *
 * Saved tracks point here instead of at Suno's file, so they keep playing when
 * Suno moves files around. The redirect is cached briefly at the edge so most
 * plays don't hit Suno's API.
 */
export async function GET(_request: Request, { params }: { params: { id: string } }) {
  const id = params.id
  if (!isSunoClipId(id)) {
    return NextResponse.json({ error: 'Not a Suno song id' }, { status: 400 })
  }

  let url: string | null = null
  try {
    url = await resolveAudioUrl(id)
  } catch (err) {
    console.error('suno audio lookup failed:', id, err)
  }
  if (!url) {
    return NextResponse.json(
      { error: 'Suno isn’t sharing audio for this song. It may be private or deleted.' },
      { status: 404, headers: { 'Cache-Control': 'no-store' } }
    )
  }

  return NextResponse.redirect(url, {
    status: 302,
    headers: { 'Cache-Control': 'public, max-age=300, s-maxage=600, stale-while-revalidate=3600' },
  })
}
