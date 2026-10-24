# Bubble Hockey

A mobile take on classic bubble hockey, built with Godot 4. Play the computer,
pass the phone to a friend, or play a friend online with a room code.

This is the MVP described in [docs/MVP_PLAN.md](docs/MVP_PLAN.md). What's done,
what changed from the plan, and what's next are in [docs/STATUS.md](docs/STATUS.md).

## What's in the box

- **Vs. computer:** Easy, Medium and Hard opponents, tuned in `config/difficulty.json`.
- **Pass & Play:** two players on one phone. The bottom half of the screen is Red, the top half is Blue.
- **Online with a friend:** one player creates a game and shares a 5-character code, and the other joins with it. A dropped guest gets 30 seconds to rejoin.
- **Match rules:** 3-minute games with sudden death on a tie, or first to 5 goals.
- **Extras:** settings for sensitivity, sound, crowd noise and vibration, plus local win/loss stats and a first-run how-to-play screen.
- **3D table:** a lit 3D table under a glass dome, with grooved slots in the ice, a jumbotron, control rods sticking out of the cabinet ends, a puck that pops up at center ice, and goal-light and confetti effects.
- **No asset files yet:** figures and props are built from shapes in code, and sound effects are synthesized at startup. Drop real models and art into `assets/` and they're used automatically (see [docs/ASSETS.md](docs/ASSETS.md)).

## Controls

Like a real bubble hockey table, each side has a goalie and five skaters (two
defense, a center and two wings). Each skater rides a straight slot up and
down the ice and spins a full 360 degrees. The goalie only slides side to side.

- Touch near a player to grab it.
- Drag along its slot to skate it forward or back (the rod's push and pull).
- Drag sideways to spin it (the rod's twist). Flick sideways for a slapshot: the player keeps spinning after you let go.
- Use two thumbs to work two players at once. Held players glow.

## Running it

1. Install [Godot 4.6](https://godotengine.org/download) (the standard build, not .NET).
2. Open Godot, choose **Import**, and select `bubble-hockey/project.godot`.
3. Press **F5**. The window is phone-shaped, and mouse clicks act as touches.

For online play on your own computer, start the relay first (see below), then
run two copies of the game. Godot's **Debug > Customize Run Instances** can
launch two at once. Leave the server address in Settings at
`ws://127.0.0.1:8787`.

## Playing in a browser

The **Web** export preset builds a browser version, which is handy on an iPad
or for sharing a test build. Online play needs the relay to be reachable from
the page.

1. Install the web templates (part of Godot's export templates).
2. Run `godot --headless --path . --export-release "Web" export/web/index.html`.
3. Serve `export/web/` over HTTP. Opening the file directly won't work.

## Tests

```bash
# Game logic: physics, rules, AI, network message validation (41 tests)
godot --headless --path . --import          # first run only
godot --headless --path . -s res://tests/run_tests.gd

# Relay server (9 tests)
cd server && npm install && npm test
```

There are also two scene-based checks that need a display. On a headless
machine, run them with `xvfb-run -a`:

```bash
# Screenshots of every screen
godot --path . --resolution 720x1280 res://tests/screenshots.tscn -- /tmp/shots

# Two game instances play online through a local relay (start it first)
godot --path . res://tests/online_smoke.tscn -- host  ws://127.0.0.1:8787 /tmp/code.txt /tmp/out &
godot --path . res://tests/online_smoke.tscn -- guest ws://127.0.0.1:8787 /tmp/code.txt /tmp/out
```

CI (`.github/workflows/bubble-hockey.yml` at the repo root) runs the unit
tests, checks that the main scene boots cleanly, and runs the relay tests.

## The relay server

`server/` is a small Node.js WebSocket server that pairs two players by room
code and forwards their messages. It runs no game logic, because the host's
phone runs the match. It holds rooms in memory, needs no database, and stores
nothing about players.

```bash
cd server
npm install
npm start          # listens on $PORT, default 8787; GET /health for checks
```

To deploy it, use the included `Dockerfile` on any host that runs containers
and supports WebSockets (Fly.io, Render, Railway, a small VPS). Put it behind
HTTPS so the game can connect with `wss://`.

**Before shipping**, change `DEFAULT_SERVER` in `scripts/core/settings.gd` to
your deployed `wss://` address. iOS blocks plain `ws://` connections to
anything but your own computer. Players can still change the address under
Settings > Online server.

## Shipping to iOS

You need a Mac with Xcode and an Apple Developer account.

1. In Godot, install the export templates with **Editor > Manage Export Templates**.
2. Open **Project > Export**, select the **iOS** preset, and set:
   - **App Store Team ID** to your 10-character team ID.
   - **Bundle Identifier** to your own reverse-domain ID, replacing `com.example.bubblehockey`.
   - **Icons**: add the required sizes, or start from `icon.svg`.
3. Export the Xcode project. Open it in Xcode, archive it, and upload to TestFlight.
4. Before App Store review, publish a privacy policy URL. The game collects no
   personal data; online play only relays game moves. Then fill in the age
   rating and screenshots (`tests/screenshots.tscn` makes raw ones).

Android needs no code changes. Add an Android export preset when you're ready.

## Project layout

```
config/          table.json (layout + physics), difficulty.json (AI tuning)
scripts/sim/     TableSim, Figure, Match: pure, deterministic game logic
scripts/ai/      AIController: rule-based opponent
scripts/game/    GameScreen (one match), TouchInput
scripts/view3d/  TableView3D (the 3D table), FigureModel (player models)
shaders/         ice, dome glass, goal netting
assets/          drop-in models and art (see docs/ASSETS.md)
scripts/net/     Net autoload (relay client), NetCodec (message validation)
scripts/core/    Settings and Sfx autoloads
scripts/ui/      UIKit: theme and widget helpers
scripts/main.gd  menus, lobby, switching into matches
server/          relay server, its tests, and Dockerfile
tests/           unit tests and scene-based checks
docs/            plan, status, architecture, playtest guide
```

## Naming

The game uses generic team names and colors, with no league, team or table
brand names. Keep it that way in the store listing, and get a quick legal
check before a public launch.
