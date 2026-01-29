# Suno Jam

A minimal MVP for listening to Suno songs in sync with others in a shared room. No accounts—create a room, share the link, and control playback together.

## Stack

- **Next.js 14** (App Router) + TypeScript + Tailwind CSS
- **Supabase**: Postgres (rooms, tracks, room_state) + Realtime (broadcast play/pause/seek/next, queue updates)
- **@dnd-kit** for drag-and-drop queue reorder

## Env vars

Create `.env.local` in the project root:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

Copy from [Supabase Dashboard](https://app.supabase.com) → your project → **Settings** → **API**: Project URL and `anon` public key.

## Run locally

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Create a room, add a track (any public Suno song URL), and open the same room in another tab or device to see sync.

## Supabase setup

1. **Create a project** at [app.supabase.com](https://app.supabase.com).
2. **Apply the schema**  
   In the Supabase Dashboard go to **SQL Editor**, then run the contents of:

   `supabase/migrations/001_initial_schema.sql`

   That creates:

   - `rooms(room_code, created_at)`
   - `tracks(id, room_code, title, url, order_index, created_at)`
   - `room_state(room_code, current_track_id, is_playing, current_time_sec, updated_at)`
   - RLS enabled with policies that allow **anon** read/write on all three tables (public MVP, no auth).

3. **Realtime**  
   No extra config needed; broadcast works with the default Realtime setup.

## Deploy

- **Vercel**  
  1. Push the repo to GitHub.  
  2. [Vercel](https://vercel.com) → New Project → Import the repo.  
  3. Add env vars: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.  
  4. Deploy.

- **Other**  
  Run `npm run build` then `npm run start`. Set the same env vars in your host.

## Flow

- **Home** (`/`): Create room (gets a 6-character code and redirects to `/room/[code]`) or join with a code.
- **Room** (`/room/[code]`):  
  - Left: Now Playing (title, play/pause, seek, next, time).  
  - Right: Up Next queue (drag-and-drop reorder, remove, add track form).  
  - Connected count via Realtime presence (optional).
- Playback is synced via Supabase Realtime: one `<audio>` per client; play/pause/seek/next are broadcast so everyone stays in sync. Drift is corrected every 2s if offset &gt; 0.25s. Time sync uses `/api/time` to estimate server offset and reduce skew.
