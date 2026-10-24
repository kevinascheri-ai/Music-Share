# Asset Brief

The game draws everything with built-in 3D shapes until real assets arrive.
Drop finished files into `bubble-hockey/assets/` with the exact names below
and the game uses them automatically. If a file is missing, the built-in
stand-in is drawn instead.

**Style for every piece:** a premium, modern take on an arcade bubble hockey
table. The figures should look like glossy painted die-cast toys, with clean
shapes and no realistic faces. The look is bright, saturated and readable on
a phone screen. It should feel like a collectible toy, not a photoreal athlete.

Avoid any real league, team or brand names and logos, and avoid real
players' likenesses.

## 3D models (Meshy AI)

Export each model as **.glb** with PBR textures embedded and **1024 px**
textures. Shared rules:

- Units are meters, Y is up, and the model faces **-Z**.
- The pivot is at the center of the base, at floor level.
- Keep it to one mesh, with no rig and no animation. The game spins and
  slides figures as rigid pieces, just like the real table.
- Stay at or under the triangle budget. If Meshy's output is heavier,
  remesh or decimate it in Meshy before exporting.

| File | What it is | Size in game | Triangles | Meshy prompt |
|---|---|---|---|---|
| `assets/skater.glb` | Hockey skater figure, stick held out to the right side | 0.55 m tall, stick reaches 0.5 m from center | ≤ 8k | "Stylized die-cast toy hockey player figure for a bubble hockey table, glossy painted plastic, helmet with visor, jersey, gloves, skates, holding a hockey stick extended to the right side at ice level, chunky toy proportions, mounted on a small round base, no face details, white jersey for recoloring" |
| `assets/goalie.glb` | Goalie figure in a crouch with wide pads | 0.5 m tall, 0.45 m wide | ≤ 8k | "Stylized die-cast toy hockey goalie figure for a bubble hockey table, glossy painted plastic, crouched stance, wide leg pads, blocker and catching glove, goalie mask, stick on the ice in front, mounted on a small base, white gear for recoloring" |
| `assets/puck.glb` | Puck | 0.26 m across | ≤ 500 | "Hockey puck, matte black rubber, subtle knurled edge" |
| `assets/cabinet.glb` | Table base under the rink: legs, sides and control rod housings at both ends, with no dome and no rink surface | Fits a 6 m × 11 m rink with a 0.6 m rim, top surface at y = 0 | ≤ 25k | "Modern arcade bubble hockey table base, sleek black and chrome cabinet with LED accent strips, control rod housings at both short ends, no dome, flat top opening for the rink" |
| `assets/scoreboard.glb` | Four-sided jumbotron that sits on top of the dome | 1.6 m wide, 1.0 m tall | ≤ 6k | "Four-sided arena jumbotron scoreboard, black glossy frame, chrome trim, blank dark screens on all four sides, small antenna lights on top" |

**Team colors are applied in the game.** Make the skater and goalie jerseys
white or light grey, and the game will tint them red and blue.

## Flat art (ChatGPT images)

Use **PNG**, square unless noted, with a transparent background where it says so.

| File | What it is | Size | Prompt |
|---|---|---|---|
| `assets/center_logo.png` | Logo painted at center ice | 1024 × 1024, transparent | "Flat circular sports logo for center ice of a toy hockey rink, bold two-color design, a puck inside a glass dome with motion lines, the words BUBBLE HOCKEY around the ring, no real team marks, vector style, transparent background" |
| `assets/crest_red.png` | Red team crest for menus and the scoreboard | 512 × 512, transparent | "Flat vector hockey team crest, red and white, a fierce stylized fox, no text, transparent background" |
| `assets/crest_blue.png` | Blue team crest | 512 × 512, transparent | "Flat vector hockey team crest, blue and white, a stylized polar bear, no text, transparent background" |
| `assets/app_icon.png` | App Store icon | 1024 × 1024, no transparency, no rounded corners | "App icon for a mobile bubble hockey game: a glossy glass dome over a mini hockey rink with two toy players and a puck mid-air, dramatic arena lighting, vibrant, centered, no text" |
| `assets/arena_backdrop.png` | Blurred arena behind the table | 2048 × 1024 | "Dark hockey arena interior out of focus, crowd in shadow, colorful stadium lights as soft bokeh, deep navy and purple tones, cinematic, no logos or text" |

## Handing them over

Add the files to `bubble-hockey/assets/` and push them, or upload them in
the chat. Send a few at a time: start with `skater.glb`, because the
figures matter most.
