# Bubble Hockey: MVP Scoped Plan

Version: 0.1 (initial draft)
Purpose: A scoped plan for a mobile bubble hockey game, vs. an AI opponent and with friends online. Written so it can be handed to a stronger LLM to refine into a technical spec, backlog, and build plan.

---

## 1. Vision

A faithful, satisfying digital version of classic bubble hockey (the rod-and-figure table game). Two players, each controlling figures on spinning rods, try to shoot a puck into the opponent's goal. The game should feel physical: the puck, the rods, and the figures are the whole experience.

**Core promise:** Pick up, play a 3-minute match in under 5 minutes, and feel like you are actually flicking rods on a table.

**Target audience:** Casual-to-mid-core mobile players, nostalgic adults who played bubble hockey, and friend groups who want a quick head-to-head game.

---

## 2. MVP Goals and Non-Goals

### Goals (must ship in MVP)
1. A physically convincing puck and rod simulation with two-player-feel controls.
2. A full match loop: face-off, play, goal, timer or score limit, result screen, rematch.
3. Play against a computer opponent with at least three difficulty levels.
4. Play online against a friend using a room code, with no account required.
5. Ship to TestFlight (iOS) first, then the App Store.

### Non-Goals (explicitly out of MVP)
- Matchmaking against strangers
- Accounts, login, friend lists, leaderboards (beyond a local stat)
- Cosmetics, shop, in-app purchases, ads
- Multiple table skins or competitive modes (tournaments, leagues)
- Android release (design so it is easy to add, but do not block on it)
- Tablet-specific layouts, controller support, or desktop builds

---

## 3. Platform and Tech Stack (recommended, open to revision)

| Area | Recommendation | Why | Alternative |
|---|---|---|---|
| Engine | **Godot 4 (GDScript)** | Free, no royalties, small builds, solid 2D physics, straightforward iOS export | Unity 2D (C#) if the team already knows it |
| Physics | Engine's built-in 2D physics, with tuned parameters | Good enough for a top-down puck game if tuned carefully | A custom fixed-timestep sim if determinism matters for netcode |
| Online backend | **Nakama** (self-hosted or managed) | Open source, has Godot and Unity SDKs, handles rooms, sessions, and realtime sockets | Photon (Fusion/Quantum), Colyseus, or a small custom Node/WebSocket server |
| Analytics / crash | Engine-agnostic crash reporter (e.g., Sentry) plus a minimal event log | Know when things break and whether people finish matches | Firebase Crashlytics |
| Build / release | Fastlane or the engine's exporter, plus TestFlight | Repeatable iOS builds | Manual Xcode archive for the first few builds |
| Target devices | iOS 16+, iPhone 11 and newer as the performance floor | Keeps scope realistic | Android 10+ later |

**Decision needed:** Confirm engine and backend before any prototyping starts. The rest of the plan assumes Godot 4 and Nakama.

---

## 4. Core Gameplay Design

### 4.1 The Table
- A rectangular, top-down table with rounded corners and walls.
- Two goals, one at each short end, with a defined opening width.
- A center line and a center circle for the face-off.
- Walls are bouncy but lose energy on contact (tunable restitution).
- The table surface has low friction for the puck.

### 4.2 Rods and Figures
- Each side has a set of **rods**. Each rod can:
  - **Slide** laterally along the table, bounded by the table edge.
  - **Rotate** (spin) around its axis, which swings figures and kicks the puck.
- Each rod carries **1 to 3 figures** (depending on the rod's role). Figures are the collision bodies that hit the puck.
- Typical configuration to model (confirm against the physical table the team wants to replicate): a goalie rod, a defense rod, and a forward rod per side. **MVP picks one fixed layout and makes it data-driven**, so a later stronger model or designer can change it without code changes.

### 4.3 The Puck
- A low-friction disc with mass, damping, and max speed clamp.
- Max speed is clamped (e.g., a fixed px/s cap) so shots stay readable and do not tunnel through figures.
- Puck is reset to center after a goal, with a short face-off delay.

### 4.4 Goals and Scoring
- A goal is awarded when the puck fully crosses the goal line within the opening.
- Score limit: **first to 5** OR **3-minute timer**, whichever is chosen in settings (default: 3 minutes, most goals wins; tie goes to sudden-death goal).

### 4.5 Match Flow
1. Title screen -> Mode select (vs. AI / Online / Pass-and-Play)
2. Pre-match (team name, difficulty, or room code)
3. Countdown -> face-off
4. Live play with score and timer
5. Goal celebration (brief pause, then reset)
6. Final whistle -> result screen (score, goals, time) -> Rematch / Menu

### 4.6 Controls (Touch)
This is the single most important design area. Plan for it explicitly.

- **Slide:** Drag a rod horizontally on its row. Rods snap to the finger with slight smoothing.
- **Spin / shoot:** Swipe or flick on a rod's row to rotate it. Faster swipe = faster rotation = harder shot.
- **Rod selection:** The screen is split into horizontal lanes, one per rod, so the player always knows which rod they are touching.
- **Multi-touch:** Allow at least two rods to be controlled at once (one finger per rod).
- **Input safety:** Ignore touches that start outside the player's half or on UI.
- **Sensitivity setting:** Slide and spin sensitivity sliders in settings. Default values to be tuned in playtests.

Acceptance check: a new player can make a goal within 60 seconds of their first match without reading any instructions beyond a one-screen tutorial.

### 4.7 Opponent AI (vs. Computer)
- Rule-based first. No ML needed for MVP.
- Each AI rod tracks the puck's lateral position with a **reaction delay**, a **max slide speed**, and an **aim error**.
- Difficulty levels change only those three numbers plus how often the AI chooses to spin.
  - **Easy:** long reaction delay, slow slide, large error, rarely shoots.
  - **Medium:** moderate values, occasionally shoots from distance.
  - **Hard:** short delay, fast slide, small error, reliable shooting and defense.
- AI should be beatable by a casual player on Easy and challenging on Hard, but never unfair (no perfect tracking, no teleporting).

### 4.8 Pass-and-Play (Local 2-Player)
- Both players share one device. Each controls their own half.
- Useful for testing controls and a cheap way to demo the game.
- Low effort once the core is working. Include in MVP because it is needed to test the online mode's rules.

---

## 5. Online Multiplayer (Friends via Room Code)

### 5.1 Approach
- **Room-based, no accounts.** Host creates a room and sees a 4 to 6 character code. Friend enters the code to join.
- **Share link / share sheet** for the code, so it can be sent over iMessage or WhatsApp.
- **Authoritative host model (recommended for MVP):** One client (the host) simulates the puck and the authoritative game state. The guest sends their rod inputs; the host sends back state snapshots. This avoids needing a paid dedicated server for each match.
- Alternative: **server-authoritative** simulation on Nakama or a small custom server. More robust against cheating and disconnects, but more to build and run. Revisit after MVP if cheating or host-advantage becomes a real complaint.

### 5.2 Network Behavior
- Input rate: send rod positions at 20 to 30 Hz.
- State snapshots from host: 15 to 20 Hz, with interpolation on the guest side.
- Handle latency with **client-side prediction for the guest's own rods** (their rods move immediately; host reconciles).
- Puck position is interpolated on the guest side. Small desync is acceptable if it corrects smoothly.
- Target: playable at up to ~120 ms round-trip. Show a simple connection quality indicator.

### 5.3 Disconnects
- If a guest disconnects, the host sees a "Waiting for opponent" screen with a 30-second timeout, then awards the match to the host by forfeit.
- If the host disconnects, the match ends for both players with a "Connection lost" screen.
- No mid-match reconnection in MVP. Document it as a Phase 2 item.

### 5.4 Matchmaking (out of MVP)
- Friend-code only in MVP. Public matchmaking is Phase 2+.

---

## 6. Features by Priority

### Must Have (MVP)
- Table, rods, figures, puck, walls, goals (fixed layout)
- Touch controls: slide, spin, multi-touch
- Vs. AI with 3 difficulty levels
- Pass-and-play local mode
- Online room-code mode (host-authoritative, forfeit on disconnect)
- Match rules: 3-minute timer and goal count, face-off reset, sudden-death tie-break
- Title, mode select, pre-match, pause, result screens
- Basic settings: sensitivity, sound on/off, music on/off
- Local stats: wins, losses, goals (stored on device)
- Simple sound effects: hit, wall, goal, whistle
- Crash reporting and minimal analytics events

### Should Have (MVP if time allows, otherwise Phase 2)
- Tutorial overlay on first launch
- Haptic feedback on goals and hard hits
- Basic background crowd music or ambience
- Haptics toggle
- Share-code button

### Could Have (Phase 2)
- Cosmetic table skins, jersey colors, figure styles
- Multiple table layouts (2-rod vs. 3-rod configurations)
- Public matchmaking and quick match
- Accounts (Sign in with Apple, Google Play Games, Game Center)
- Friends list and invites
- Leaderboards and seasonal stats
- Reconnection after disconnect
- Android release
- Controller (MFi / Bluetooth) support

### Won't Have (for now)
- Ads, paid currency, shop
- Tournament modes
- Replays

---

## 7. Art and Audio Direction

### Visual
- Stylized, clean 2D top-down look with bold outlines so figures and puck read at a glance on small screens.
- Table: wood-tone or painted surface with a clear center circle and goal mouths.
- Figures: simple silhouettes with two team colors. Team colors must have strong contrast with the puck and table (also consider color-blind palettes).
- Puck: high contrast, with a subtle motion trail when fast.
- **Placeholder art first.** Gameplay is validated with colored shapes before any illustration work.

### Audio
- Sound effects: rod hit, figure hit, puck hits wall, goal horn, whistle, face-off.
- Music: optional, low-volume loop on menus. Gameplay can be SFX-only in MVP.
- Every sound should have a volume setting.

### Legal and Naming
- Do not use real NHL team names, logos, player names, or trademarked table brand names (for example, "Tudor") anywhere in the game, store listing, or marketing.
- Use generic team names and colors. Use "Bubble Hockey" only as a generic description, and get a legal check before a public launch.

---

## 8. Technical Architecture

### 8.1 Client Modules (Godot 4 suggested)
- `TableSim`: owns the puck, rods, figures, walls, and goals. Runs on a fixed timestep (e.g., 60 Hz) for stable physics.
- `RodController`: maps touch input to rod slide and spin targets. Enforces speed and range limits.
- `MatchState`: score, timer, phase (face-off, playing, goal, ended), and rules.
- `AIController`: rule-based opponent, driven by difficulty config.
- `NetSession`: handles room creation, joining, input send, state receive, and interpolation (online mode only).
- `UI`: menus, HUD, result screens, settings.
- `SaveData`: local stats and settings.
- `Config`: difficulty values, table layout, physics constants (all data-driven, not hard-coded).

### 8.2 Backend (Nakama, MVP scope)
- Create and join rooms by code.
- Relay match messages between two players (or handle match presence, if using Nakama match handler).
- Minimal user session: anonymous device ID, no PII stored.
- No database schema beyond what room matching needs in MVP.

### 8.3 Data Stored
- On device: settings, local stats.
- On server: transient room state only. Delete after match ends or after 10 minutes idle.
- No personal data collected in MVP. Confirm before any analytics that could identify a user.

### 8.4 Performance Budget
- 60 FPS on iPhone 11 during gameplay.
- Cold start to menu under 3 seconds on a mid-range device.
- App size under 100 MB for MVP.
- Physics step under 2 ms per frame on target device.

---

## 9. Milestones

Timelines assume a small team (1 to 2 developers, part-time). Adjust once the team and hours are known.

### M0: Physics Feel Prototype (1 to 2 weeks)
- Table with walls and goals, rods with slide and spin, one puck, placeholder shapes.
- Touch controls working on a real device.
- **Exit criterion:** A playtester can score a goal and rally with another person within 2 minutes, and the team agrees the puck and rods feel right. Do not start M1 until this is true.

### M1: Vs. AI (2 to 3 weeks)
- Full match rules, timer, score, face-off reset, and result screen.
- Rule-based AI with 3 difficulty levels.
- Basic menus, settings, local stats.
- **Exit criterion:** A full match can be played start to finish vs. AI on all difficulty levels with no soft-locks.

### M2: Pass-and-Play and Sound (1 week)
- Two-player local mode.
- SFX and volume settings.
- Haptics (should-have).
- **Exit criterion:** Two people can play a full match on one device.

### M3: Online Room Mode (3 to 4 weeks)
- Nakama integration, room create and join, share code.
- Host-authoritative state sync with input and snapshot pipelines.
- Client-side prediction for local rods, interpolation for opponent and puck.
- Disconnect handling (forfeit on guest drop, end on host drop).
- **Exit criterion:** Two players on separate networks, one on mobile data and one on Wi-Fi, can finish a match with less than 1 visible desync per match.

### M4: Polish, Tutorial, Playtests (2 weeks)
- Tutorial, first-run flow, title art pass, placeholder art replaced where possible.
- Crash reporting verified on device.
- At least 5 external playtests with notes captured.

### M5: TestFlight and App Store Submission (1 week plus review time)
- Privacy policy URL, App Store listing, screenshots, age rating.
- TestFlight beta with 10 to 20 testers.
- Submit to App Store.

**Rough total:** 9 to 12 weeks part-time for a small team. Treat as an estimate until M0 is done.

---

## 10. Testing Plan

### Automated
- Unit tests for match rules (scoring, timer, sudden death, reset).
- Unit tests for AI difficulty configs (reaction, max speed, error stay within bounds).
- Deterministic physics test: same inputs produce the same outputs for a given seed (helps online debugging).
- Network simulation tests with injected latency (50, 100, 200 ms) and packet loss (1 to 5%).

### Manual
- Playtests every milestone with at least 3 people who have never seen the game.
- Device matrix for MVP: 1 iPhone 11 (performance floor), 1 current-gen iPhone, 1 iPad (scaling check only).
- Thumb-position test: play one-handed and two-handed, confirm controls work without accidental touches.

### Metrics to Watch in Playtests
- Time to first goal (target: under 60 seconds for a new player).
- Average match length (target: 3 to 4 minutes).
- Rematch rate after a completed match (target: over 40%).
- Online room success rate (target: over 90% of joins succeed).
- Desync reports per match (target: under 1).

---

## 11. Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Physics does not feel right | High | Medium | M0 exists to catch this before investing elsewhere. Tune with playtesters, not by guessing. |
| Touch controls are frustrating | High | Medium | Dedicated control prototyping in M0. Sensitivity settings. Playtest with real fingers. |
| Netcode desync and lag | High | High | Host-authoritative with prediction. Test with latency injection early. Keep online mode behind a flag until M3 passes. |
| AI feels cheap or unfair | Medium | Medium | Difficulty knobs are numbers, not hacks. Playtest each level. |
| Scope creep into cosmetics or accounts | Medium | High | Non-goals list above. Anything else goes to Phase 2 backlog. |
| Trademark or IP complaint | Medium | Low | Generic names, original art, no brand names. Legal check before public launch. |
| App Store rejection | Medium | Low | Privacy policy, clear description, no misleading claims, age rating reviewed early. |
| Backend cost surprise | Low | Low | Host-authoritative keeps backend light. Set spend alerts. |

---

## 12. Open Questions (answer these before or during M0)

1. **Engine:** Godot 4 (recommended) or Unity? Does anyone on the team already know one of them?
2. **Table layout:** Which real table should the MVP copy? Number of rods per side and figures per rod.
3. **Team size and hours per week:** Changes milestone dates.
4. **Platform:** iOS first only, or iOS and Android at the same time?
5. **Online model:** Host-authoritative (cheaper, simpler) or server-authoritative (more robust)?
6. **Match length:** Default to 3 minutes or 5 goals, or both as settings?
7. **Art:** Commission artwork, use an asset pack, or stay stylized and minimal?
8. **Monetization (post-MVP):** Premium one-time purchase, cosmetics, or free with ads? This affects architecture only slightly, so decide before Phase 2.
9. **Account policy:** Is "no account" for MVP acceptable for your friends, or do they expect a login?
10. **Name and branding:** Working title, and does the App Store name need to be unique?

---

## 13. Definition of Done for MVP

- All "Must Have" features are implemented, tested on the device matrix, and pass their milestone exit criteria.
- Playtesters can complete a match vs. AI, in pass-and-play, and online with a friend, without outside help.
- Crash-free session rate above 99% in TestFlight.
- App Store listing submitted with privacy policy, screenshots, and age rating.
- Phase 2 backlog exists, with every deferred feature from Section 6 recorded.

---

## 14. Instructions for the Stronger Model

When you receive this plan, please:

1. Confirm or challenge the tech stack in Section 3. Give a short recommendation with reasons.
2. Turn Sections 4 and 5 into a technical design doc: component diagram, data flow for input and network state, and the data format for table, rod, and difficulty configs.
3. Write a physics spec with starting numbers for mass, friction, restitution, max puck speed, rod slide speed, rod spin speed, and goal opening width. Mark every number as a guess to be tuned in M0.
4. Break Sections 9 and 6 into an ordered task backlog with estimates and dependencies. Each task needs an acceptance check.
5. List the questions in Section 12 that block work, and mark which ones block M0.
6. Flag anything in this plan that is unclear, contradictory, or risky, and say what you would change.
7. Keep scope to the MVP. Put anything else in a Phase 2 list, not in the MVP tasks.

Keep the output in plain Markdown so it can be stored in the repo as `docs/`.
