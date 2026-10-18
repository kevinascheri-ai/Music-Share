import { NextResponse } from 'next/server'
import { lookupAudio } from '@/lib/suno'
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

  const found = await lookupAudio(id)
  if (found.url === null) {
    // 404 tells the player to skip this song; 502 means "try again later".
    const unreachable = found.reason === 'unreachable'
    if (unreachable) console.error('suno audio lookup: Suno unreachable for', id)
    return NextResponse.json(
      {
        error: unreachable
          ? 'Couldn’t reach Suno right now. Try again in a moment.'
          : 'Suno isn’t sharing playable audio for this song.',
      },
      { status: unreachable ? 502 : 404, headers: { 'Cache-Control': 'no-store' } }
    )
  }

  return NextResponse.redirect(found.url, {
    status: 302,
    headers: { 'Cache-Control': 'public, max-age=60, s-maxage=600, stale-while-revalidate=3600' },
  })
}
