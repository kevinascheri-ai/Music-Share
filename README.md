# Suno Jam

Listen to Suno music together, in sync. Create a room, paste a Suno playlist, and send the link to a friend. Whoever presses play, pause, skip or seek does it for everyone in the room. Each person keeps their own volume. There are no accounts.

## Using it

1. Open the app and press **Create Room**.
2. On Suno, open a playlist and choose **Share → Copy link**, then paste it into **Add music**. Every song in the playlist is added to the queue. Single song links work too.
3. Send the room link (the link icon next to the room name copies it).
4. Your friend opens the link, types a name and presses **Join**. That one tap is what browsers require before a page can play audio.

After that:

- **Play, pause, next and previous** apply to everyone. A small toast says who did what, such as "Alex paused".
- **Tap a song in the queue** to play it for everyone. You can drag to reorder, remove songs, **Shuffle**, or **Clear** the queue.
- **Seek bar:** dragging it moves everyone to the same spot.
- **Media keys / headset buttons / lock screen controls** also control the room, which helps when you're in a game.
- **Space bar** toggles play/pause while the tab is focused.
- **Volume is per person**, so each of you can balance it against game audio.
- When a song ends, the room moves on to the next one and wraps back to the top at the end of the queue.

Supported links:

| Link | Example |
| --- | --- |
| Suno playlist | `https://suno.com/playlist/<id>` |
| Suno song | `https://suno.com/song/<id>` |
| Suno share short link | `https://suno.com/s/<code>` |
| Direct audio file | `https://example.com/track.mp3` |

Playlists have to be **public** on Suno, because the app reads them the same way a logged-out visitor would.

## How the sync works

- Every action (play, pause, seek, skip) creates a complete **state snapshot**: which song, whether it's playing, and the position at a given moment on a shared clock. The snapshot is broadcast to the room over Supabase Realtime and saved in `room_state`.
- Each listener works out where the song should be *right now* from that snapshot. Network lag therefore doesn't shift anyone's position. Clocks are aligned with the server through `/api/time`.
- A loop corrects drift twice a second. Small drift is fixed by briefly speeding up or slowing down playback (pitch is preserved), and large drift by jumping to the right spot.
- If two people press buttons at the same instant, a sequence number decides which action wins, so everyone ends up on the same state.
- People who join late, or who reconnect after a dropped connection, ask the room for its current state and land mid-song in sync.
- If you reopen a room that was left playing long ago with nobody in it, it starts paused instead of suddenly playing music.

## Stack

- **Next.js 14** (App Router) + TypeScript + Tailwind CSS
- **Supabase**: Postgres (`rooms`, `tracks`, `room_state`) + Realtime (broadcast + presence on one channel per room)
- **@dnd-kit** for drag-and-drop queue reordering
- `/api/resolve` turns Suno links into playable tracks on the server. It only ever fetches Suno hosts.

## Setup

### Env vars

Create `.env.local` in the project root:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

Both values are in the [Supabase Dashboard](https://app.supabase.com) → your project → **Settings** → **API** (Project URL and the `anon` public key).

### Supabase

1. Create a project at [app.supabase.com](https://app.supabase.com).
2. In **SQL Editor**, run the contents of `APPLY_THIS_IN_SUPABASE.sql`. It creates `rooms`, `tracks` and `room_state` and enables RLS with policies that allow anonymous read/write (the app has no accounts).
3. Realtime needs no extra setup; broadcast and presence work with the defaults.

If you already ran the SQL for an earlier version, there's nothing new to apply.

### Run locally

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000), create a room, and open the same room link in a second browser (or a private window) to try the sync.

## Deploy

- **Vercel:** import the repo, add the two env vars above, and deploy.
- **Elsewhere:** run `npm run build` then `npm run start` with the same env vars.

## Notes and limits

- Suno has no official public API. The app uses the same JSON endpoints the suno.com website uses, and falls back to reading the public page if those change. If Suno changes things or blocks requests from your host, adding a playlist can fail with an error message. Audio itself streams from Suno's CDN straight to each listener's browser.
- Songs that are still generating on Suno are skipped when a playlist is imported.
- Rooms are public to anyone who has the link.
