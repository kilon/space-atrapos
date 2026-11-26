# Space Atrapos

[![Play on itch.io](.github/play-itch.svg)](https://kilonalios.itch.io/space-atrapos)
[![Download for Windows](.github/download-windows.svg)](https://github.com/kilon/space-atrapos/releases/latest)
[![Download for Linux](.github/download-linux.svg)](https://github.com/kilon/space-atrapos/releases/latest)

A procedural 3D space game made with [Godot 4](https://godotengine.org/). You are an automaton in
**New Hellas**, a galaxy of 120 star systems where six star empires of ancient Greece, the
independents and the pirates compete. Fly your ship between stars and planets, land on worlds of
procedural ground and walk them, trade, mine, fight, dock at stations and make your own way. There is
no story to follow: the galaxy is yours.

![Flying over Amnissos, the Minoans' ocean world](data/docs/shots/space3d.jpg)

## What's in it

- **A whole galaxy to fly**: 120 star systems with their own suns, planets and moons, linked by gates
  and a hyperspace drive, with a living economy, traders, wars between the empires and reputations
  to earn or lose.
- **Real worlds to land on**: every planet is procedural ground on a cube sphere, streamed in as you
  come down from orbit, with seas, coasts, clouds, caves, towns, flora and fauna.
- **On foot and aboard**: stand up from the pilot's seat, walk out of your ship through its doors, into
  towns, station hangars and concourses, caves and dungeons. A jet pack, a rifle, a mining beam, a
  scanner and a builder go with you.
- **Six empires, each with its own look**: ships, stations, towns, people and hangars for the Minoans,
  Mycenaeans, Athenians, Spartans, Ionians and Cycladic islanders.
- **Talos, the game's own editor**: data editors for everything in the game, a mesh editor with curve
  modelling (sketches, procedural solids, booleans, baked solids shaped by their edges), animation
  and effects editors, all live-editable over a running game.
- **Mods**: mods are folders of files laid out like the game's own, mounted over it at start-up,
  with a mod editor to make them.
- **Built-in documentation**: a pilot's guide, a tutorial, an encyclopedia and the editor's manual,
  in the game's Archive (F1), with annotated screenshots.

![Minoan androids in a town](data/docs/shots/space3d_people.jpg)

![The planet map](data/docs/shots/planet3d.jpg)

## Running it

The quickest way is the [itch.io page](https://kilonalios.itch.io/space-atrapos) (in the browser, or the
Windows and Linux downloads). To run it from the source:

1. Install [Git LFS](https://git-lfs.com/) **before cloning**: images, models, audio and fonts are
   stored in LFS.

   ```sh
   git lfs install
   git clone https://github.com/kilon/space-atrapos.git
   ```

2. Install **Godot 4.7** (the standard build, not .NET).
3. Open the project in Godot and run it (F5), or from a terminal:

   ```sh
   godot --path space-atrapos
   ```

The first start imports the assets, which takes a while; later starts are quick.

## Controls (the basics)

| | |
|---|---|
| Steer the ship | the mouse (a virtual stick); **A / D** roll |
| Throttle | **W / S** (stops at zero; again for reverse), **X** stop, **Shift** boost |
| Thrusters | **R / F** up and down, **Q / E** sideways |
| Land / take off | **L** (near a station: ask for a landing pad) |
| Stand up / walk | **U** out of the seat, **W A S D**, **Space** jump (hold: jet pack) |
| Fire / use | left mouse button |
| The Automaton (inventory, maps, archive) | **Tab** |
| The guide | **F1** |
| Talos, the editor | **F8** |

Everything can be rebound in **Settings > Controls**, and gamepads are supported.

## For developers

- **Code layout**: `scripts/core` (engine-level services), `scripts/sim` (the game's rules and data,
  no visuals), `scripts/world` (the 3D world), `scripts/ui` (the HUD and menus), `scripts/editor`
  (Talos). Scenes are in `scenes/`, shaders in `shaders/`.
- **Tests**: `python3 tools/test.py` runs the whole suite in parallel, each process with its own
  throwaway user data. Filter it with `python3 tools/test.py <file filter> [<test name filter>]`.
- **Frame rate**: the game aims for 600 FPS and never freezes while loading.
  `python3 tools/fps_test.py` plays it in a window and checks.
- **Live coding**: start the game with `-- --live`, then `python3 tools/live.py` inspects it, runs
  code in it and hot-reloads scripts while it runs.
- **Documentation screenshots**: `python3 tools/doc_shots.py` retakes the guide's annotated shots.
- **Characters**: the characters are generated in Blender by the scripts in `external/blender`
  (`blender -b --python build.py -- <character> model`, then `actions` and `export`). Hand edits are
  layered over them from `external/blender_overrides`.
- **Patch notes**: every change is tracked between patches (`python3 tools/patch.py status`) and
  published as an illustrated entry in the game's Patch Notes screen.

## License

Space Atrapos is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 3 of the License.
It is distributed in the hope that it will be useful, but **without any warranty**; without even the
implied warranty of merchantability or fitness for a particular purpose. See [LICENSE](LICENSE) for
the full text.

Copyright © 2026 kilon.
