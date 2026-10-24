# MVP Status

Last updated: October 2026, first build.

## Milestones

| Milestone | State | Notes |
|---|---|---|
| M0 Physics feel prototype | **Built, not yet felt** | Table, rods, puck, touch controls, and 15 physics tests are done. The exit criterion ("feels right to playtesters on a real phone") still needs people and a device. |
| M1 Vs. AI | **Done** | Full match rules, 3 difficulty levels, menus, settings and local stats. Tests confirm Hard beats Easy and same-seed matches replay identically. |
| M2 Pass & Play and sound | **Done** | Two players on one device. Synthesized sound effects and crowd noise. Vibration is coded, but untested on a phone. |
| M3 Online room mode | **Done, tested locally** | Relay server, room codes, host-authoritative sync, prediction and interpolation, and disconnect/rejoin. An automated two-instance test passes against a local relay. Not yet tried across real networks or mobile data. |
| M4 Polish and playtests | **Partly done** | Done: how-to-play screen and placeholder art pass. Not done: crash reporting (needs a Sentry or similar account), real artwork, and the 5 external playtests. |
| M5 TestFlight / App Store | **Not started** | Needs a Mac with Xcode, an Apple Developer account, a deployed relay, a bundle ID, app icons and a privacy policy. Steps are in the README. |

## Changes from the plan

1. **Hand-written physics instead of Godot's built-in 2D physics.** One puck
   and a few capsules take about 300 lines. It's deterministic and fully
   unit-tested, and it avoids the tunneling and jitter problems the plan
   flagged. The plan listed this as the alternative "if determinism matters
   for netcode".
2. **A small custom relay instead of Nakama.** The MVP only needs "pair two
   phones by code and pass messages". About 200 lines of Node do that with
   no database and nothing to configure, and the whole flow can be tested
   here. Nakama (or similar) is still the right move once you want accounts,
   friend lists or matchmaking.
3. **Table layout:** each team's goalie, defense and forward rods sit in its
   own half, at 7.5%, 27% and 42% of the rink from its own goal.
   Interleaving the forwards trapped the puck between opposing figures. The
   layout is data in `config/table.json`, so it's easy to try others.
4. **Guest rejoin is in.** The plan had no mid-match reconnection. The host
   now waits 30 seconds for a dropped guest, and the guest gets a Reconnect
   button.
5. **"Copy Code" instead of the iOS share sheet.** The native share sheet
   needs an iOS plugin. Copy-and-paste into Messages works today.

## Before friends can play online

- Deploy `server/` (Dockerfile included) behind HTTPS.
- Set `DEFAULT_SERVER` in `scripts/core/settings.gd` to its `wss://` URL.
  The current default, `ws://127.0.0.1:8787`, only works on your own computer.

## Known issues and things to watch

- **Own goals are common.** Pucks deflect off defenders a lot, which is
  partly true to the real table. Tune with real players before changing it.
- **Unverified on a device:** vibration, the notch/home-bar insets, and
  touch feel on an actual phone.
- **Host latency edge:** the guest's touches reach the host half a round
  trip late (see ARCHITECTURE.md).
- **Engine quirk:** scripts run with `godot -s` can't use autoload names, so
  the unit tests only cover autoload-free code. The scene-based checks
  (`tests/*.tscn`) cover the rest.

## Suggested next steps

1. Run it on an iPhone and do the M0 feel pass. Tune `config/table.json`
   using docs/PLAYTEST.md.
2. Deploy the relay and play one real online match over mobile data.
3. Add crash reporting.
4. Commission or pick art and sound to replace the placeholders.
5. Do TestFlight with 10–20 friends, then App Store submission.
