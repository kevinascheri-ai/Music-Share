# Playtest and Tuning Guide

Every gameplay number lives in `config/table.json` or `config/difficulty.json`.
Change one value at a time, play a few matches, and keep notes.

## What to watch for

- **Time to first goal:** a new player should score within about 60
  seconds. If not, make the controls or the AI easier.
- **Match length:** a 3-minute match plus face-offs should feel like 3–4
  minutes of action, not long stalls.
- **Rematch rate:** if players stop after one game, ask them why.
- **Frustration moments:** the puck stuck out of reach, shots that seem to
  vanish, a rod that won't respond. Note where on the table each happened.

## Symptoms and knobs (`config/table.json`)

| Symptom | Try |
|---|---|
| Puck feels floaty and slides forever | raise `puck_friction` (0.35 → 0.5) |
| Puck dies too quickly | lower `puck_friction` |
| Shots too fast to react to | lower `puck_max_speed` (1700 → 1400) or `rod_max_spin_speed` |
| Shots feel weak | raise `rod_max_spin_speed` or `figure_restitution` |
| Walls too bouncy or too dead | `wall_restitution` (0.8) |
| Puck gets stuck between rods | raise `slope_accel`, or lower `stall_seconds` for faster re-drops |
| Puck parks in corners | raise `corner_slope_accel` |
| Sticks snap back too fast after a swing | lower `rod_spring` |
| Hard to reach the puck | raise `stick_length` or `figure_radius` |
| Too many or too few goals | `goal_width` (150), or move `dist_from_goal` for the goalie rod |

## Touch feel (player settings, plus `scripts/game/touch_input.gd`)

- **Slide sensitivity** (Settings, 0.5–2.0x): how far a rod slides per
  finger movement. At 1.0x the figure tracks the finger.
- **Swing sensitivity** (Settings, 0.5–2.0x): how much stick swing per
  finger movement. The base rate is `SPIN_PER_PIXEL` in `touch_input.gd`.

## Computer opponent (`config/difficulty.json`)

| Too easy / too hard? | Knob |
|---|---|
| Reacts too fast or too slow | `reaction_delay` (seconds) |
| Gets to the puck too quickly | `slide_speed` (fraction of max) |
| Shots too accurate | `aim_error` (pixels), `aim_skill` |
| Shoots too often or too rarely | `shot_chance` |
| Reads the play too well | `predict` |
| Shots too hard | `swing_speed` |

After changing difficulty values, run the tests. `test_hard_beats_easy_more_often`
checks that the levels still rank correctly.

## Playtest checklist

- [ ] First launch shows how-to-play, and it doesn't come back after "Got It".
- [ ] Can score against Easy within the first match.
- [ ] Hard feels beatable but tough.
- [ ] Two-thumb play works (two rods at once).
- [ ] Pause works, and backgrounding the app pauses the game.
- [ ] Pass & Play: both players can control their rods at the same time.
- [ ] Online: create, share code, join, play a full match, then rematch.
- [ ] Online: turn on airplane mode for 10 seconds on the guest, reconnect, and keep playing.
- [ ] Sound and vibration toggles work.
- [ ] Nothing important hides under the notch or home bar.
- [ ] Runs smoothly (60 fps) on the oldest phone you have.
