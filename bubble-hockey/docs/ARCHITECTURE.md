# Architecture

## Layers

```
            ┌─────────────── scripts/main.gd (menus, lobby) ───────────────┐
            │                                                              │
            ▼                                                              ▼
   GameScreen (one match)                                    Net autoload ◄──► relay server
   ├─ TableView3D    draws the table in 3D                   (WebSocket, JSON)
   ├─ TouchInput     touches → figure targets (per local team)
   ├─ AIController   figure targets for the computer
   └─ Match ── TableSim ── Figure × 12    pure logic, no nodes
```

- **Pure logic** (`scripts/sim`, `scripts/ai`, `scripts/net/net_codec.gd`)
  never touches nodes, rendering, time or randomness it wasn't given. The
  same code runs in tests, on the online host, and in the attract screen.
- **Presentation** (`scripts/game`, `scripts/ui`, `scripts/main.gd`) reads
  that state, draws it, and turns touches into inputs.
- **Autoloads:** `Settings` (save file), `Sfx` (synthesized sounds) and
  `Net` (relay connection).

## Simulation

- Fixed 60 Hz tick, with 5 physics substeps per tick so a fast puck can't
  pass through a stick.
- **Figures** work like the real table. Each side has a goalie and five
  skaters. A skater rides a straight slot running the length of the ice
  (the rod's push and pull) and spins a full 360 degrees (the rod's twist),
  sweeping its stick around it in the plane of the ice. The goalie slides
  side to side and doesn't spin. The two teams' slots interleave, and the
  top team's layout is the bottom team's rotated 180 degrees.
- **Collision shapes:** a skater is a body circle plus a stick capsule from
  its center to the stick tip. A goalie is one wide capsule. A stick
  contact passes on the stick's sweep speed at that point, so spinning is
  what shoots.
- **Puck:** a circle with friction, a speed cap, and a gentle "table slope"
  that only acts on a slow puck. The slope rolls it toward the nearest slot
  and out of the corners, but never into a goal mouth. A puck that sits
  still for 3 seconds gets a new face-off, and it pops up at center ice.
- **Pinch rule:** a puck squeezed between two figures moves with them
  instead of bouncing between them at full speed.
- **Inputs:** per figure, `[target_s, has_angle, target_angle]`, where `s`
  is the distance along the slot. Figures chase their targets at a capped
  speed. With no angle target, a figure keeps spinning and slowly winds
  down.
- All tuning numbers are in `config/table.json`. The slot layout is data:
  change the `figures` list to try other tables.

Why not Godot's built-in physics? A hand-written sim for one puck and a few
capsules is short, fully deterministic and unit-testable, and it gives exact
control over game feel. Same-seed AI matches replay identically, which is
what the determinism test checks.

## 3D view

`TableView3D` draws the sim with Godot's Compatibility renderer, so the same
scene runs on phones and in a browser. The ice is a shader (`shaders/ice.gdshader`)
that paints the markings and the grooved slots from the slot layout. The
camera frames the rink to fit the screen below the HUD:

- **vs. Computer:** from your end of the table.
- **Online guest:** from the other end.
- **Pass & Play:** straight down.
- **Menu:** a slow orbit.

`FigureModel` builds the players from shapes, or loads `assets/skater.glb`
and `assets/goalie.glb` when they exist.

## Match rules

`Match` wraps the sim with phases: `COUNTDOWN` (puck held, 1.6 s), then
`PLAYING`, then `GOAL` (2.2 s), then back to `COUNTDOWN`, and finally
`ENDED`. Timer mode counts down from 3:00 and goes to sudden death on a tie.
Goals mode ends at the target. `end_by_forfeit()` covers a player leaving.

## Computer opponent

Per figure, every tick, the AI:

1. Reads the puck as it was `reaction_delay` seconds ago, looking a little
   ahead along its path (`predict`).
2. Skates the figure level with the puck, nudged so the stick's sweep at
   the contact point heads for the goal (`aim_skill`), with random error
   (`aim_error`), at a capped speed (`slide_speed`).
3. When the puck is within stick reach, it shoots with probability
   `shot_chance`: a full spin at `swing_speed`. It always picks the spin
   direction that sweeps the puck toward the opponent's goal, never its own.
4. Moves the goalie to where the puck will cross the goal line, folding in
   side-wall bounces.

## Online play

The host's phone is the authority. The relay only pairs players and forwards
messages.

| Direction | Message | Rate | Content |
|---|---|---|---|
| host → guest | `{"k":"start","rules","resume"}` | on join/rejoin | match rules |
| host → guest | `{"k":"st","n","s","m","e"}` | 20 Hz | tick, table state, match state, events since the last snapshot |
| guest → host | `{"k":"in","r"}` | 30 Hz | the guest's figure targets |
| both | `{"k":"ping","t"}` / `{"k":"pong","t"}` | 1 Hz | round-trip time for the HUD |
| both | `{"k":"rematch"}`, host → `{"k":"restart"}` | on demand | rematch handshake |
| both | `{"k":"bye"}` | on quit | leaving on purpose |

- The **guest** sees the table rotated so their goal is at the bottom.
- The guest draws the host's world **100 ms in the past**, blending between
  snapshots, so motion stays smooth despite network jitter.
- The guest's **own figures are predicted locally**, so they respond instantly.
  The host applies the same targets, so the two converge.
- Everything received goes through `NetCodec` before use: input is shape-
  and number-checked, rules are clamped, and malformed snapshots are dropped.
- **Disconnects:** if the guest drops, the host pauses and gives them 30
  seconds to rejoin with the same code (the guest's overlay has a Reconnect
  button). After that the host wins by forfeit. If the host drops, the room
  ends.

Relay protocol (client ↔ server):

- **Client → server:** `create`, `join {code}`, `msg {d}`, `leave`, each with `v: 1`.
- **Server → client:** `created {code}`, `joined {code}`, `peer_joined`,
  `peer_left`, `msg {d}`, and `error {code}`, where `code` is one of
  `not_found`, `full`, `version`, `rate_limited`, `busy` or `bad_request`.

**Known trade-off:** the host has a latency edge. Their figures are where they
see them, while the guest's touches reach the host half a round trip late.
At friend-level latency (under about 100 ms) this is hard to notice. If it
becomes a complaint, the next step is server-authoritative simulation. The
pure `Match` class can run unchanged in a headless Godot server.
