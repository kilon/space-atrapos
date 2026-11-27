# Space Atrapos - notes for Claude

Godot 4.7 game (GDScript): a procedural 3D space game - star systems flown from a third-person camera,
planets of procedural ground landed on and walked, life on them, stations, ships, combat, trade. Since
2026-11-21 the game is 3D only: the old 2D game is a backup and a reference in external/2d_game/ (not
imported; its art, data and code are where to look for the original designs to port).
Tests: `python3 tools/test.py [<file filter> [<test name filter>]]` (parallel, each process with its own
throwaway user data). One process: `godot --headless --path . -s tests/run_tests.gd [-- <filter>]` (set
XDG_DATA_HOME to a scratch folder). Talos is the game's editor (title screen > Talos); the docs are
data/docs/*.md (F1).

## Code layout

- `scripts/core/` - engine-level services, mostly autoloads: Settings, SaveGame, Keybinds, Sfx/Music/Voice,
  ProcArt (art loading), LiveLink, LoadVeil.
- `scripts/sim/` - the game's rules and data, no visuals: Galaxy (the simulation: systems, stations,
  economy, traders, empires, HOME_ORBITS), PlayerData, Items/Gear/Hardpoints/Shipyard/ShipDesigns/Tech/
  Upgrades/Industry/Mining, Missions, QuestData, PlanetGen/StarGen (looks), Skills, Stamina.
- `scripts/world/` - the 3D world (the "Cosmos" classes): `space/` (Cosmos - the scene's root, floating
  origin; PlanetShape + CosmosPlanet - procedural ground on a cube-sphere quadtree; star, stations, gates,
  rocks, NPC ships, hulls, bolts), `life/` (flora, fauna, creatures, NPCs), `player/` (CosmosShip + its
  walkable CosmosShipInterior, CosmosWalker, CosmosCam, CosmosHud), `station/` (CosmosHangar), `models/`
  (CosmosModels - characters merged and PBR; Stage3D - model loading; CosmosWarm - first-use warm-up;
  EmpireKit - each empire's look for ships, stations and their insides: colours, emblem, frieze, one shader
  (empire.gdshader), a Mesher; EmpireHulls - the empires' ship designs; MinoanShip - your ship's hull),
  `game/` (CosmosGame - your save in and out, CosmosQuest, proxies the 2D-made menus read).
- `scripts/ui/` - HUD (hud.gd, the gauge, radar, toolbar, event log), the menus (main_menu = title + Esc
  menu, ship_menu = the Automaton (Tab), station_menu), pages, theme (NeonTheme), Archive/Encyclopedia.
- `scripts/editor/` - Talos (data editors, the ECurves editor - mesh_editor.gd + mesh/curve_tools.gd: every model an ECurve
  object of solids made of faces, edges and vertices, no mesh editing; the rules for any topology it builds: quads with a uniform layout, following the flow and shape of the edges - and the animation editor; EditTarget - where they save: the game or a mod),
  the Patcher (the title screen's Patch Notes), the Mod Editor (mod_editor.gd; standalone: `-- --mod-editor`).
- Mods: `scripts/core/mods.gd` (the first autoload): user://mods/<id>/ (mod.json, files/ laid out like res://,
  `<file>.json.merge` patches) mounted as a zip over res:// plus a front ResourceFormatLoader for what's load()ed;
  the title screen's Mods (scripts/ui/mods_screen.gd); a start that never reaches the title runs without them next time.
- Scenes: `scenes/ui/`, `scenes/world/cosmos.tscn` (the game), `scenes/editor/`. Shaders: `shaders/world/`
  (the 3D world's), `shaders/` (UI, characters' PBR).
- Standing directions: photoreal, cinematic (no cel shading/outlines); everything a 3D model, modular -
  pieces swapped, colours/textures as shader parameters; the empires' looks kept; one theme everywhere
  (the game's HUD and menus - NeonTheme) and one typeface (Atrapos Sans, made by tools/make_font.py); text
  never under 14 px (Settings.MIN_FONT - the helpers clamp; tests/test_fonts.gd); no helper text (the tutorial's icon); walk in and out of ships
  through doors, no teleporting; the camera never clips.

## Frame rate: aim for 600 FPS, nothing loads in the foreground

Aim for 600 FPS everywhere - a target, not a hard limit since 2026-11-23 (the user: keep close to it, but if
reaching it isn't easy or convenient that's fine; don't sink big effort into the last few percent). Load everything in the background and
never freeze. `python3 tools/fps_test.py` plays the game in a real window (`3d`, `loading`, `talos`,
`title` to filter) and fails a scenario under 600 FPS (average and 95% of frames), with a frame over 50 ms,
or under 3/4 of its baseline (tests/fps_baseline.json; `--save-baseline` after a speed-up) - and a loading
step with a frame over 33 ms. Run it after anything that adds per-frame work, nodes, drawing or loading.
Measure on a quiet machine (close my own test windows first: an uncapped one halves the numbers). Habits:
meshes and scatter built on workers (MultiMesh buffers made there too), shared meshes, few surfaces a
model (CosmosModels merges), draw ranges on small things, shadows only near, periodic work paced by time
not frames, LOD visits rare when slow, nothing heavy in one frame, worker tasks always waited for. The 3D
scene builds itself a piece a frame under the loading veil (Cosmos: `await _stage()`, `build_settled()`).
New kinds of 3D visuals go into CosmosWarm (drawn at the title).

## Screenshots in the docs: keep them current

The guide (data/docs/game.md), the tutorial and the encyclopedia show screenshots of the game with
infographic notes where their text has `![caption](shot:id)` (DocPictures). The shots are listed in
data/docs/shots.json (caption, the files each shows, notes in 1920x1080 units); tests/doc_shots.gd sets
each moment up and `python3 tools/doc_shots.py [ids|--stale|--notes]` takes them (a window, ~1.5 min for
all) into data/docs/shots/. test_doc_shots fails when a shot is older than the files it shows: then run
`python3 tools/doc_shots.py --stale` and look at the pictures (notes still pointing at the right things?).
Do it before publishing a patch too. When a change adds a screen or a workflow, give it a shot.

## Characters from Blender: the automaton, the pirate, Kilon Alios, each empire's android

The characters are 3D models made in Blender (external/blender/automaton/: kit.py - the rig, pose solver and
the part makers (box / loft / tube / ball / plate / decal), physically based materials (Principled BSDF:
metal / roughness by the material's name - surface()), no ink outlines (kit.INK = 0); automaton.py /
pirate.py / kilon.py - skins on the automaton's frame; minoan.py - the empires' android, a body of its own
(Mn.style / Mn.paints: a skin's marks and paints), guard.py / athenian.py / spartan.py / mycenaean.py /
ionian.py / cycladic.py - that body in each empire's palette with its own head (CosmosNpc.PEOPLE says who
wears which); moves.py - every clip as key poses, 30 fps),
exported by `blender -b --python build.py -- <skin> model`, then `blender -b <skin>.blend --python build.py --
<skin> actions`, then `... export` to art/<id>_3d/ (glb + model.json), then `godot --headless --import`. The
game merges each into one PBR surface (CosmosModels; Stage3D.surface_look gives each part's metal/roughness/
glow); `apply(root, id, recolor, hide)`: slots AUT_Armor / AUT_Red / AUT_Glow recolourable, parts hidden by
material prefix (the Minoan android's weapons MIN_Rifle* / MIN_Bow* / MIN_Axe*). Keep decals on flat plates
at cuts=0 (each cut x4 triangles). Photoreal only: no cel shading, no ink, no anime look.
**The user's own work on the characters: external/blender_overrides/** (README.md there; overrides.py): one
`<skin>_overrides.blend` a character - a Reference (the generated rig, parts `gen:<Part>`, clips `gen:<clip>`) and
their Overrides collection; build.py's export merges it in (a part named like a generated one replaces it, others
are added; actions with plain names replace or add clips) and records it in model.json "overrides"
(tests/test_overrides.gd fails on its problems). Never edit the user's overrides files; keep bone, part, material
and clip names stable (a rename breaks their work - say so in the patch); `overrides.py <skin> refresh` only when asked.
In scripts run with `-s` (tests/doc_shots.gd, fps_tour.gd) load class_name scripts at run time
(`load("res://scripts/sim/skills.gd")`): naming them makes the script fail to compile - and the run hangs.

## The 3D game

Entry: title (scenes/ui/main_menu.tscn) > New game / Continue / Load > scenes/world/cosmos.tscn under the
LoadVeil (CosmosGame.begin / begin_state). Saves: the old format (SaveGame slots; Cosmos.get_save_data =
CosmosGame.snapshot: player, galaxy, missions, quest, ship position in map units, "cosmos3d" extras).
Scale: 10 m a map unit (PlanetShape.PX_TO_M). New 3D materials: add one to CosmosWarm (no compile hitches);
share meshes; characters through CosmosModels. Tests: tests/test_cosmos.gd; frame rate: `fps_test.py 3d`
and `loading`; my own windows always pass the user arg `--bot` (no focus, no mouse capture).
Done since: big stations (CosmosStation: pads, lifts, solid parts - push_out / cam_hit), manual docking (F a pad,
thrusters Space/Ctrl/Q/E, touchdown, the lift), traders on pads (haulers); towns (CosmosTown: palace, houses,
shrine, storehouse, landing field - one mesh, building.gdshader slots; PlanetShape.flats level their ground;
citizens = CosmosNpc.citizen_of, recoloured via CosmosModels slots); space monsters (CosmosMonster: a kit of
lofted parts, one mesh, monster.gdshader sway; lairs = monster signals); the 2D animals (CosmosFauna.SPECIES); each empire its own
stations (CosmosStation._athens / _sparta / ...), ships (EmpireHulls), hangars and crews (CosmosHangar,
CosmosNpc.people_id / dress), town architecture (CosmosTown.Builder by `emp`) - from the reference sheets in
external/images/<empire>_ships_1.png / _spacestations_1.png and data/sprites/tile_<empire>_*;
the guide/tutorial for 3D; controls as Keybinds actions. Pending: more of the 2D game's systems in 3D
(mining, the other signal kinds, the main quest's characters, skills on foot), interiors of the buildings.

## Patches: track every change, publish when asked

The user reviews changes in the game's **Patch Notes** screen (the title screen's Patch Notes; scripts/editor/patcher.gd - "the Patcher" below): each patch
entry (data/patches/<id>_<name>.json) has a one-paragraph summary, a step-by-step
vector infographic, and a code review with diffs and explanations
(format: header comment of scripts/editor/patcher.gd). Changes are tracked between patches:

- The tracking lives in `external/patcher/` (not imported by Godot - it has a
  `.gdignore`; not in builds - all of `external/` is excluded on export).
- Tracking is automatic: `external/patcher/snapshot/` + `manifest.json` hold the game as of
  the last published patch; `python3 tools/patch.py status` lists everything changed
  since. Never edit `external/patcher/snapshot/` or `manifest.json` by hand.
- **After every change you make, add a section to `external/patcher/pending.md`**: the date,
  what was asked, what was done (and why), numbers worth an infographic (sizes,
  timings, counts), the files changed and new assets. Keep it current - it's what
  the patch entry will be written from, possibly in a later session.
- Publish only when the user asks ("publish the pending changes", "make a patch
  entry"). Then:
  1. `python3 tools/patch.py status` and read `external/patcher/pending.md`.
  2. Write `data/patches/<next id>_<name>.json`: id, title, date, a one-paragraph
     summary, and steps (title, caption, diagram on the 1000 x 560 canvas; text size 16 or more, labels inside their boxes, no texts over each other - test_editor.test_patch_diagrams_readable checks) - look at
     data/patches/0001_streamed_planets.json for the style; screenshot the steps
     (Patcher) and fix overlaps.
  3. `python3 tools/patch.py notes-template <scratch>/notes.json`, fill in an
     explanation per file and a [title, note] per hunk - for code hunks
     [title, note, [[at, text]...]]: explanation bubbles, each pointing at the
     line containing `at` and saying how that part works (the key parts of the
     code; screenshot the code review to check they read well), then
     `python3 tools/patch.py review <scratch>/notes.json data/patches/<file>.json`.
  4. Run the editor tests (test_patcher checks every patch).
  5. `python3 tools/patch.py baseline <id>` - the next patch starts from here.

Versions group patches (the Patcher shows a tree: versions with their patches under
them). When asked to make a version (or add patches to one), write / update
`data/patches/version_<id>_<name>.json`: kind "version", id, title, date, a
one-paragraph summary, `patches` (the patch ids), and `steps` - one page per patch,
each with `patch` (its id), title, text and a diagram (like a patch step: what that
patch brought, at a glance; see version_0.1_planets_come_alive.json). Screenshot the
pages, run test_patcher. Patches not in any version show at the top level. **New patches join the open version automatically**: `patch.py baseline <id>` (step 5) appends the patch, a page for it and a line in the summary to the version file marked `"open": true` (else the newest; now 0.32) - then polish that page (its text, a real diagram). To start a new version, create its file with `"open": true` and remove `"open"` from the old one.
