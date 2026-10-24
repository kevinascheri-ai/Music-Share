# Architecture

## Layers

```
            ┌─────────────── scripts/main.gd (menus, lobby) ───────────────┐
            │                                                              │
            ▼                                                              ▼
   GameScreen (one match)                                    Net autoload ◄──► relay server
   ├─ TableView      draws the table                         (WebSocket, JSON)
   ├─ TouchInput     touches → rod targets (per local team)
   ├─ AIController   rod targets for the computer
   └─ Match ── TableSim ── Rod × 6        pure logic, no nodes
```

- **Pure logic** (`scripts/sim`, `scripts/ai`, `scripts/net/net_codec.gd`)
  never touches nodes, rendering, time or randomness it wasn't given. The
  same code runs in tests, on the online host, and in the attract screen.
- **Presentation** (`scripts/game`, `scripts/ui`, `scripts/main.gd`) reads
  that state, draws it, and turns touches into inputs.
- **Autoloads:** `Settings` (save file), `Sfx` (synthesized sounds) and
  `Net` (relay connection).

## Simulation

- Fixed 60 Hz tick, with 4 physics substeps per tick so a fast puck can't
  pass through a stick.
- **Puck:** a circle with friction, a speed cap, and a gentle "table slope"
  that only acts on a slow puck. The slope rolls it toward the nearest rod
  and out of the corners, but never into a goal mouth. A puck that sits
  still for 3 seconds gets a new face-off.
- **Rods:** each rod slides along x and spins on its axis. Each figure is a
  capsule from its body to its stick tip. Spinning swings the tip
  forward/back along y, and the tip's velocity is what shoots the puck.
- **Pinch rule:** a puck squeezed between two figures moves with them
  instead of bouncing between them at full speed.
- **Inputs:** per rod, `[target_x, has_angle, target_angle]`. Rods chase
  their targets at a capped speed. With no angle target, a spring returns
  the sticks to rest.
- All tuning numbers are in `config/table.json`. The rod layout is data:
  change the `rods` list to try other tables.

Why not Godot's built-in physics? A hand-written sim for one puck and a few
capsules is short, fully deterministic and unit-testable, and it gives exact
control over game feel. Same-seed AI matches replay identically, which is
what the determinism test checks.

## Match rules

`Match` wraps the sim with phases: `COUNTDOWN` (puck held, 1.6 s), then
`PLAYING`, then `GOAL` (2.2 s), then back to `COUNTDOWN`, and finally
`ENDED`. Timer mode counts down from 3:00 and goes to sudden death on a tie.
Goals mode ends at the target. `end_by_forfeit()` covers a player leaving.

## Computer opponent

Per rod, every tick, the AI:

1. Reads the puck as it was `reaction_delay` seconds ago.
2. Optionally predicts where the puck crosses the rod's line, folding in
   side-wall bounces (`predict`).
3. Picks the figure that can reach that spot. When shooting, it aims to hit
   the puck off-center toward the goal (`aim_skill`), with random error
   (`aim_error`).
4. Moves its target at a capped speed (`slide_speed`).
5. If the puck sits in front of a lined-up figure, it shoots with
   probability `shot_chance`: wind up, then strike (`swing_speed`), then
   recover.
6. If the puck is behind the rod, it parks a figure on the goal-mouth side
   so an accidental touch pushes the puck toward the boards instead of into
   its own net.

## Online play

The host's phone is the authority. The relay only pairs players and forwards
messages.

| Direction | Message | Rate | Content |
|---|---|---|---|
| host → guest | `{"k":"start","rules","resume"}` | on join/rejoin | match rules |
| host → guest | `{"k":"st","n","s","m","e"}` | 20 Hz | tick, table state, match state, events since the last snapshot |
| guest → host | `{"k":"in","r"}` | 30 Hz | the guest's rod targets |
| both | `{"k":"ping","t"}` / `{"k":"pong","t"}` | 1 Hz | round-trip time for the HUD |
| both | `{"k":"rematch"}`, host → `{"k":"restart"}` | on demand | rematch handshake |
| both | `{"k":"bye"}` | on quit | leaving on purpose |

- The **guest** sees the table rotated so their goal is at the bottom.
- The guest draws the host's world **100 ms in the past**, blending between
  snapshots, so motion stays smooth despite network jitter.
- The guest's **own rods are predicted locally**, so they respond instantly.
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

**Known trade-off:** the host has a latency edge. Their rods are where they
see them, while the guest's touches reach the host half a round trip late.
At friend-level latency (under about 100 ms) this is hard to notice. If it
becomes a complaint, the next step is server-authoritative simulation. The
pure `Match` class can run unchanged in a headless Godot server.
