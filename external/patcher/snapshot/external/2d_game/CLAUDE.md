# Space Atrapos - notes for Claude

Godot 4.7 game (GDScript). Tests: `python3 tools/test.py [<file filter> [<test name filter>]]` - runs them in
parallel (~1 min for all), each process with its own throwaway user data (no backup needed). One process:
`godot --headless --path . -s tests/run_tests.gd [-- <file filter> [<test name filter>]]` (back up and restore
`~/.local/share/godot/app_userdata/Space Atrapos` around such runs, or set XDG_DATA_HOME to a scratch folder).
Talos is the game's editor (title screen > Talos); the docs are data/docs/*.md (F1).

## Frame rate: 600 FPS minimum, nothing loads in the foreground

The game must run at 600 FPS or more everywhere (the user's bar, raised from 240 on 2026-11-19), load
everything in the background and never freeze. `python3 tools/fps_test.py` plays every area in a real
window (~6 min; `space`, `surface`, `thalassa`, `loading`... to filter) and fails a scenario under 600 FPS
(average and 95% of frames), with a frame over 50 ms, or under 3/4 of its baseline (tests/fps_baseline.json;
`--save-baseline` after a speed-up) - and a loading step (new game, jump, landing, take-off, docking,
Talos, the computers, the Archive) with a frame over 33 ms. Run it after anything that adds per-frame
work, nodes, drawing or loading; `--profile` shows where the time goes (PROFILE_SPIKE_MS for long frames),
`--attrib` what each script costs, `--shots` takes screenshots. Measure on a quiet machine (another game
running halves the numbers). tests/test_frame_budget.gd guards the mechanisms headless (atlases,
GroundChunks, far culling, throttled redraws, script budgets). Habits that keep it: no draw_circle by the
hundred (ExhaustTrail.disc() + draw_texture_rect), textures drawn together in one atlas (TextureAtlas),
cosmetic redraws via UI.redraw_due (60 Hz), periodic work paced by time not frames (at 600 FPS "every
other frame" is 300 a second), shader backdrops cached (ShaderCache), nothing heavy in one frame (spread
it; scene changes via UI.switch_scene / UI.dismantle; first-use work warmed in the background), worker
tasks always waited for, off-screen things updated less often. The space scene builds itself a piece a
frame under the fade / the loading veil (main.gd: `await _stage()` between pieces, hidden and still until
`build_settled()`; built directly - tests - all at once): put new set-up work behind a `_stage()`. The
title screen's Warmup draws one of everything (shaders, pipelines) a frame - add new kinds of visuals to
it. Big textures (the automaton's anatomy: AnatomyArt, 4096 px) load on a worker one at a time from the
title screen: the second big one to reach the card costs a ~90 ms frame once a run, whatever its format -
never start such a load in play. A view of many draw commands is painted off screen when it changes and
shown as one rectangle (Surgery). `fps_test.py loading` on its own measures a cold start (everything used for the first time, shaders
compiled: the first new game after launching); in the full tour the loading steps come last, warm - compare
like with like (the long frames show scripts / drawing ms).

## Screenshots in the docs: keep them current

The guide (data/docs/game.md), the tutorial and the encyclopedia show screenshots of the game with
infographic notes where their text has `![caption](shot:id)` (DocPictures). The shots are listed in
data/docs/shots.json (caption, the files each shows, notes in 1920x1080 units); tests/doc_shots.gd sets
each moment up and `python3 tools/doc_shots.py [ids|--stale|--notes]` takes them (a window, ~1.5 min for
all) into data/docs/shots/. test_doc_shots fails when a shot is older than the files it shows: then run
`python3 tools/doc_shots.py --stale` and look at the pictures (notes still pointing at the right things?).
Do it before publishing a patch too. When a change adds a screen or a workflow, give it a shot.

## Characters rendered from Blender: the automaton and the pirate android

You on foot ("player") and the pirates ("pirate") are drawn from animations rendered in Blender
(external/blender/automaton/: kit.py - the rig and pose solver, automaton.py / pirate.py - the skins,
moves.py - every clip as key poses, 30 fps), packed by `python3 tools/puppet_atlas.py <skin>` into
art/<id>_clips/ (SheetPuppet's clip mode; half-size web/ sets). After changing a model or a move:
`blender -b --python build.py -- <skin> model`, `python3 render_all.py <skin> [clips]`, the packer,
`godot --headless --import`. The hand-drawn sheets (art/player/, art/pirate/) are the backup
(Settings.classic_sprites) - keep them working. Skills (scripts/skills.gd, skill_fx.gd, the Spell Book)
ride on those clips; tests/test_skills.gd. In scripts run with `-s` (tests/doc_shots.gd, fps_tour.gd)
load class_name scripts at run time (`load("res://scripts/skills.gd")`): naming them makes the whole
script fail to compile (autoloads aren't there yet) - and the run just sits there.

## Turning 3D, step by step

The game is being turned into a 3D game gradually (the user's direction since 2026-11-21); the 2D
ways stay as fallbacks behind Settings. So far: the automaton on foot is its actual model
(art/player_3d/player.glb from `build.py -- automaton export`; Stage3D - one SubViewport of cells,
cel shaders - shown by SheetPuppet's model mode; Settings.character_graphics), and the streamed
planets' ground is 3D geometry (Ground3D: a mesh per 32 x 32-tile chunk, heights real, an
orthographic Camera3D matched to the 2D camera to the pixel, its picture redrawn only when the view
leaves it; Settings.terrain_3d). Both draw into SubViewports shown by sprites in the 2D world, so
the rest still draws over them. Everything else - buildings, scenery, creatures, pirates - is 2D
sprites. Keep the 600 FPS habits for 3D too: redraw a viewport only when it must (60 Hz for
animation; never every frame for something that only slides), build meshes on workers, compile
shaders on the loading screen. `SA_GROUND2D=1` / `SA_SPRITES=1` in the environment switch a step
off to compare.

Since 2026-11-21 the user wants the WHOLE game redone in 3D (third-person, heavily procedural, landing
seamless from orbit). The 3D game lives in scripts/cosmos/ (scenes/cosmos.tscn; title > "3D: Continue" /
"3D: New game"): Cosmos (a Galaxy system at PlanetShape.PX_TO_M = 10 m a map unit, floating origin -
system_position()), PlanetShape + CosmosPlanet (one height field a planet, cube-sphere quadtree patches
on workers, plants/boulders per finest cell - CosmosFlora), CosmosShip (flight, the Hyperion drive with
gravity wells, lasers), CosmosWalker (on foot: planet or hangar deck), CosmosCreature/CosmosFauna, CosmosNpc
(pirate androids), CosmosNpcShip/CosmosHull (traffic), CosmosHangar + CosmosTerminal (docking, services),
CosmosGame (your save: PlayerData + Galaxy, written in the 2D format to the Autosave slot - the 2D game
loads it). Characters drawn merged (CosmosModels: 2 draws each). New 3D materials: add one to CosmosWarm
(drawn at the title: no compile hitches); share meshes; tests/test_cosmos.gd; `fps_test.py 3d` (and
`loading`). My own windows always pass the user arg `--bot` (no focus, no mouse capture).

## Patches: track every change, publish when asked

The user reviews changes in the game's **Versions** screen (Talos > Versions, F7; scripts/patcher.gd - "the Patcher" below): each patch
entry (data/patches/<id>_<name>.json) has a one-paragraph summary, a step-by-step
vector infographic, and a code review with diffs and explanations
(format: header comment of scripts/patcher.gd). Changes are tracked between patches:

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
pages, run test_patcher. Patches not in any version show at the top level. **New patches join the open version automatically**: `patch.py baseline <id>` (step 5) appends the patch, a page for it and a line in the summary to the version file marked `"open": true` (else the newest; now 0.31) - then polish that page (its text, a real diagram). To start a new version, create its file with `"open": true` and remove `"open"` from the old one.
