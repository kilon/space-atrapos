# Space Atrapos - Talos documentation

# start | Getting started
How the editor is organised, how its tooltips and this documentation work, and every keyboard shortcut in one place.

## overview | The editor
Talos, the game's editor, is opened from the title screen (**Talos**) - or from inside a game: the **Esc menu's Talos** button, or **F8** (in space or on a planet; Settings > Controls to rebind). Opened from a game, it opens **over the game**: the game stays loaded underneath, paused, and the rail's way out reads **Back** - leaving Talos (Back, Esc, or F8 again) puts you straight back in it, as it was, with whatever you changed in Talos already applied. Its parts:
- **The data editor** - the quest, its dialogue, lore, the citizens' lines, and a browser of every sprite. See [The data editor](doc:data-editor).
- **The Library** - every asset of the game, alive, in rooms. See [The Library](doc:zoo).
- **The Scenario Editor** - quests written as plain-sentence rules. See [Scenarios](doc:scenarios).
- **The Level Editor** - opened in the game (right-click on a planet or in space), to reshape maps. See [Level Editor](doc:level-editor).
- **The Mesh Editor** - the game's 3D models and your own: parts, vertices, faces, materials. See [The Mesh Editor](doc:mesh).
- **The Animation Editor** - the characters' clips on a timeline: pose bones, key them, make new clips. See [The Animation Editor](doc:anim).
- **The Effects Editor** - the game's particle effects (explosions, dust, sparks, impacts): their emitters, colours and sizes over life, played as you change them. See [The Effects Editor](doc:fx).

Outside Talos, on the title screen: **Patch Notes** - every version of the game and its patches (see [Patch Notes](doc:patcher)) - and **Mods**, with the **Mod Editor**, which makes mods: your changes to the game, any of it, kept apart from it (see [Mods](doc:mods)).

**The rail.** Talos opens on **Meshes**. Down the left of every Talos screen runs one column of every tool, each an icon with its name: **Meshes** and **Animation** at the top, then **Effects**, then the data editor's pages (**Dialogue**, **Chapters**, **Lore**, **Citizens**, **Sprites**), and **Exit** (to the title screen) at the foot. The screen you're on is lit; the rail never moves or changes size. Click any of them to go straight there. Every tool stays as you left it while you're in another (it's built the first time you open it, then kept), so switching is instant and never asks about unsaved changes; **Exit** - or **Esc**, on any Talos screen, once there's nothing in it to cancel first (a selection, a room of the Library, a path being drawn) - does ask, tool by tool, for any unsaved work. The same from the keyboard anywhere in Talos: Ctrl+1 to Ctrl+5 for the data editor's pages, F4 Effects, F6 Meshes, F7 Animation.

**The header.** Each screen has one line at the top: its name, a short note on what it's for (status messages - "Saved...", "Reloaded" - appear there too), and the screen's own buttons on the right.

Every button - in Talos and in the game alike - shows its icon and a short name (a word or two); hover one for its tooltip: its full name, its keys and what it does. See [Tooltips](doc:tooltips) for how tooltips work, and [Keyboard shortcuts](doc:shortcuts) for every shortcut.

## tooltips | Tooltips and this documentation
Hover any button, field or list for half a second to see its tooltip: its name, its keyboard shortcut in brackets, what it does and how to use it.
- **Keep hovering for 12 seconds** and the tooltip **pins**: a thin bar fills while you wait. A pinned tooltip stays on screen when you move away, so you can read it, and its links can be clicked.
- **Close a pinned tooltip** with the **✕** in its corner. A **right-click** (anywhere) or a **click outside** it closes it too, and so does opening another tooltip (hovering another control) - only one tooltip is open at a time.
- **Links** at the bottom of a tooltip open this documentation at the matching section. In the documentation, links in the text jump between sections.
- This manual is one book of the **Archive** - the game's one window for all its documentation: the shelf on the left holds the Pilot's Guide, the Tutorial, the Encyclopedia, Controls, Versions and this Talos Manual; **Search every book** finds the pages in all of them that have all your words.
- The documentation is a book of **chapters** (on the left, numbered 1-5, each opening to its sections 1.1, 1.2...). Click a chapter for its introduction and contents; each page ends with links to the previous and next page, and sections show their chapter at the top.
- **Back** and **Forward** (the arrows at the top left, **Alt+Left / Alt+Right**, or the mouse's back / forward buttons) move through the sections you visited, like a web browser. Opening a new section after going back clears the forward history.
- Press **Esc** or the **✕** to close the documentation.

## shortcuts | Keyboard shortcuts
**In a game:** F8 opens Talos over the game (paused underneath); F8 or Back returns to it.
**Anywhere in Talos (the rail):** Ctrl+1 to Ctrl+5 the data editor's pages (Dialogue, Chapters, Lore, Citizens, Sprites) · F4 Effects · F6 Meshes · F7 Animation.
**Data editor:** Ctrl+S save · Ctrl+R reload from file · Ctrl+P preview the stage's dialogue · Esc exits Talos (as the rail's Exit).
**Scenario Editor:** Ctrl+S save · Ctrl+R reload · Ctrl+N new scenario · F5 test in game · F1 documentation · Esc exits Talos.

**Mesh Editor:** Tab object / edit mode · 1 / 2 / 3 vertices, edges, faces · G / R / S move, rotate, scale (X / Y / Z axis; click or Enter: done; right-click or Esc: cancel) · E extrude · M merge · X / Delete delete · A / Alt+A select all / none · O proportional (Shift+O falloff, Alt+O connected; wheel while moving: radius) · Shift+A add a box · Shift+D duplicate · Numpad 1 / 3 / 7 / 5 views, F frame, Home all · middle-drag orbit, Shift+middle-drag pan, wheel zoom · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save · Ctrl+Shift+S save as · F1 documentation · Esc exits Talos.

**Animation Editor:** Space play / pause · Left / Right a frame · Ctrl+Left / Ctrl+Right the key before / after · R turn the bone, G move it (X / Y / Z axis) · K key the bone · Shift+K key all · Delete keys · Ctrl+C / Ctrl+Shift+C / Ctrl+V copy keys / the pose, paste · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save · O onion skin · L loop · Numpad 1 / 3 / 7 views · F1 documentation · Esc exits Talos.

**Live Editor (in a game):** F10 open / close · click: pick · Ctrl+S save · F1 documentation.
**Effects Editor:** Space replay · L loop · G ground · F frame · drag orbit, wheel zoom · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save · F1 documentation · Esc exits Talos.

**Mod Editor:** Ctrl+N new mod · Ctrl+S save the open file · F5 test in game · F1 documentation · Esc back to the title screen.

**Library:** 1-9, 0 rooms · left-click an asset to edit it · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+C / Ctrl+V copy / paste a look · + / - zoom · WASD or arrows look around · Home reset view · Esc back to the browser, then out of Talos.

**Level Editor:** 1-9 pick a tool · [ / ] brush size · Ctrl+S save the layout · F10 exit · wheel zoom · middle click: zoom back · WASD / arrows / middle drag pan · right-click: the editor menu.

# data | The data editor
The editor's main screen: the main quest's stages, dialogue, chapters and lore, the citizens' lines, and the sprite browser.

## data-editor | The data editor
Talos opens here, from the title screen's **Talos** button. Its five pages - the top five of the rail - edit the game's text data; edits apply immediately in this session.
- **Save** (Ctrl+S) writes `data/main_quest.json` (stages, dialogue, chapters, lore) and `data/interactions.json` (citizens' lines).
- **Reload** (Ctrl+R) throws away unsaved edits and reads those files again.
- The rail opens the other tools; **Exit** (or Esc) returns to the title screen.
Pages: [Dialogue](doc:dialogue) · [Chapters](doc:quest) · [Lore](doc:lore) · [Citizens](doc:interactions) · [Sprites](doc:sprites).

## dialogue | Dialogue and quest stages
The list on the left is every stage of the main quest in order (it stays put; the stage on the right scrolls if it's long). Click one to edit it - its fields two to a row:
- **Chapter** - which chapter the stage belongs to (titles are edited in [Chapters](doc:quest)).
- **Objective** - shown in the HUD and the Automaton while the stage is active.
- **Station** - for docking stages: the exact name of the station to dock at.
- **Position (x, y)** - for "go to" stages: the place in the system, in world units.
- **Items needed** - for delivery stages: `id=amount` pairs separated by commas, e.g. `energy_cell=4, titanium_ore=6`.
- **Enemies** - for fights: ship class ids separated by commas, e.g. `traced_ember`.
- **Rewards** - drachmas, Data Cores and an equipment id, given when the stage completes (empty or 0: none).
- **Unlocks lore ids** - lore entries unlocked by the stage, ids separated by commas.

**Dialogue** plays when the stage starts. Each line has a **speaker** and the **text**, shown as the player will read it - bold, italic, colours. **Edit** (the button beside it) shows its source, with the formatting tags dimmed (`[b]bold[/b]`, `[i]italic[/i]`, `[color=gold]colour[/color]`); **Ctrl+B** / **Ctrl+I** (or the B / I buttons under Edit) wrap the selected words; **Done**, **Esc** or a click elsewhere shows it formatted again (Esc while typing ends the typing - press it again to leave Talos). The arrow buttons move a line up or down, the cross deletes it, the plus adds a line, and the play button in the header previews the whole dialogue (Ctrl+P). Each line's box is as tall as its text.

## quest | Chapter titles
The titles of the main quest's chapters, as shown in the Automaton's quest page. Each stage picks its chapter in [Dialogue](doc:dialogue).

## lore | Lore entries
The lore the player unlocks during the quest. Pick an entry in the list to edit its **title** and **text** - the text shown as the player reads it; Edit beside it shows the source (as for dialogue lines: tags dimmed, Ctrl+B / Ctrl+I, Done or Esc). Stages unlock entries by id ([Dialogue](doc:dialogue)).

## interactions | Citizens' lines
What Minoan citizens say when you click them: the **Minoan words** (shown in their speech bubble) and the **translation** (shown in the event log). A random line is picked each time. The plus button adds a line, the cross removes one.

## sprites | Sprites
Every sprite of the game, grouped (ships, stations, citizens, building pieces, effects...). Hover a thumbnail for its key, file and size. Sprites are cut from the reference sheets in `external/images/` by `tools/extract_sprites.py`; after re-running it, press **Reload sprites** (the first button in the header) to load the new ones.

# zoo-ch | The Library
A live preview of every asset of the game.

## zoo | The Library | keywords: asset browser, Browser, View live, Search every asset
The Library opens on the **asset browser**: every asset of the game, sorted by **who it belongs to**. On the left, a search box and a tree - the **Minoan Thalassocracy**, the **Athenian League**, the **Spartan Hegemony**, the **Mycenaean Kingdoms**, the **Ionian League**, the **Independents**, the **Sea Peoples**, **you** (your ship, the pilot on foot), **monsters and bosses**, **wildlife** (by kind of world), **the galaxy** (planet, star, nebula and asteroid templates, jump gates, skies, terrain tiles) and **the interface** - each with its categories (ships, stations, characters, portraits, buildings, furniture, effects...) and how many. Click an owner for everything it has, a category for just that; the middle shows them as cards. Click a card for its big preview, what it is (a ship's class, hull, shields, speed, price), its size and its file; **View live** (or a double-click) opens the live room with it in it, centred on it where the room can. Type in the search box to find any asset by name, file or owner.
Every **category** in the tree shows its **icon and name** (ships, stations, characters, buildings, planets...): hover it for how many assets it holds. **The live rooms** (the tabs at the top, each its icon and name - People, Ships, Stations, Planets, Rocks, Suns, Nebulae, Buildings, Effects, GUI, Monsters - keys 1-9 and 0; **Browser** or Esc goes back to the browser) - the assets side by side, alive:
- **Characters** - the Minoan androids (drawn from sprite sheets cut by tools/android_sheets.py from external/images/minoan_android_rifle.png, _bow.png and _axe.png: relaxed and attacking - the labrys also wound up - 8 views each) with a laser rifle, a laser bow and a labrys, walking in all 8 directions, fighting drones (bursts of bolts, single arrows, closing in and cleaving) and patrolling, and their attack pictures in 8 views; the Minoan guard (drawn from sprite sheets: a relaxed and an aiming pose, 8 views each - external/images/minoan_npc_guard_idle.png and _aim.png) walking in all 8 directions, idling, shooting and patrolling; the guard's 8 aiming views; the pirate raider (drawn from its four reference sheets - external/images/npc_pirate_frame_1..4.png, cut by tools/character_sheets.py: rifle down, across the body, at the hip and aimed, 8 views each) walking with its rifle down, four moments of its attack side by side, and one raising its rifle and firing at a drone; the pilot; your landed ship. You on foot - an armoured android with a rifle, drawn from sprite sheets (external/images/player_on_foot_idle.png and _aim.png): walking round a loop, and its 8 relaxed and 8 aiming views.
- **Ships** - every class at its in-game size, by who flies it. **Stations** - every design, spinning, by who builds it. **Planets** - the seven planet templates, the named planets and every planet of the galaxy (generated from the templates, each one different). **Asteroids** - the two rock templates (a contact binary of two fused lobes, a long craggy rock), each ore's asteroids (iron: rust; titanium: glowing cyan veins; platinum: dark with gold veins) and a field of variants, all slowly tumbling. **Suns** - the six star templates and every system's sun (each one different). **Nebulae** - the four backdrop templates (supernova remnant, planetary nebula, emission nebula, spiral galaxy) and every system's nebulae.
- **Buildings** - every Minoan wall, floor, roof, column and decor piece; the scenery. **Effects** - every effect sprite. **GUI** - every kind of widget on a sample board: the interface's own look. **Monsters** - the creatures of the signal sites, alive: Skylla, the sea witch (cut from her reference art by tools/skylla_parts.py - her tentacles writhing, hair drifting, arms clawing, charging every few seconds) the Minotaur, the main quest's last boss (cut from his reference art by tools/minotaur_parts.py - his cape rippling, arms raking, leg kicking, winding up every few seconds), Cerberus, the three-headed hound of the monster signals (tools/cerberus_parts.py - heads snapping, legs pawing, tail lashing), Cetus, the sea monster (tools/cetus_parts.py - its top view bending as it swims, fins beating, tail sweeping), Echidna, the mother of monsters (tools/echidna_parts.py - arms reaching, tail swaying, rearing up in her front view), the Hydra (tools/hydra_parts.py - eight heads weaving, the knot of coils, the front view and its double head), the Chimera (tools/chimera_parts.py - lion, goat and serpent heads and three legs, each moving its own way), Charybdis (tools/charybdis_parts.py - whole, a shader turning its vortex and writhing its tentacles), and the Void Leviathan.
Drag, WASD or the arrows look around; the wheel or + / - zoom; Home resets the view; Esc returns to the browser (Esc there: exits Talos, as the rail's Exit). Everything in the Library uses the game's own code, so it shows exactly what the game shows.

## zoo-properties | Editing assets | keywords: property panel, properties, template, variant, undo, paste, apply to all
Almost everything in the Library can be edited: **left-click** it (a click, not a drag) and the **property panel** opens on the right, with a dashed ring (or frame) on what you picked.
- **Planets, asteroids, suns and nebulae** - their procedural shaders' properties (terrain, seas, ice, lava, craters, clouds, bands, storms, rings, atmosphere; lobes, lumps, crags, craters, rust, dust, ore veins, tumble; granulation, flares, corona, field loops, beams; filaments, shells, dust, arms...).
- **Buildings** - click a style's area to theme all its walls, floors, roofs, columns and decor.
- **GUI** - the interface's look; changes show on every window at once (the panel too). Leaving the Library puts back the look you came in with - save a preset to keep one.
Every property has a slider and a number box (colours a colour picker, positions x/y/z sliders); changes show at once. Hover a property's name for what it does and its range. Only the properties that apply are shown.
- **Template** and **Variant** regenerate the asset (variant 0 = the template; the next button = a random variant); **reset** goes back to how it was in the room.
- **Undo / Redo** (Ctrl+Z, Ctrl+Y) step through every change; a slider drag is one step.
- **Copy / Paste** (Ctrl+C, Ctrl+V) move a whole look between assets of the same kind (Copy also puts it on the clipboard as text).
- **Apply to all similar** gives every asset of that kind in the room the same look.
- **Esc** or the close button closes the panel; clicking empty space deselects.

## zoo-themes | Themes, presets and where they appear | keywords: preset, theme, rules, where and when, colour slots, recolour
**Colour slots.** The buildings' sprites are painted art; their colours are grouped into families that can each be moved to a new colour while keeping the painted shading:
- Buildings: **plaster** (reds), **wood and terracotta** (oranges), **gold trim** (yellows), **frescoes, tech and glass** (blues), **stone** (sandstone and limestone); then the whole building, and walls, floors, roofs and columns/decor each with their own hue, brightness, saturation and tint.
- **Slot width** widens or narrows which shades count as each family.
**Presets.** Type a name and **save**: the look is stored in data/themes.json under that name, for its kind of asset (buildings, planets, asteroids, suns, nebulae, GUI). Pick a saved preset from the list to load it; **delete** removes the named one.
**Where and when.** Each preset carries rules (the **Where and when...** button shows them; they're saved with the preset). The game uses the preset where they all match:
- **Star systems** and **Empires' sectors** (whose space it is) - nothing ticked means anywhere.
- **Planets** (for buildings on a surface; a named planet's look in space).
- **System conditions** - boom, bust, famine, outbreak, civil unrest, pirate raids, expansion.
- **Templates** - only for assets of these templates (e.g. ocean worlds, pulsars).
- **Empires that like you** - while you're Friendly or better with one of these empires.
- **From / Until chapter** - main-story stages (-1: no limit).
- **Chance** - how often it's used where it matches; **Priority** - when several match, the highest wins (equal ones are shared out).
- **Enabled** - off keeps the preset without using it.
In the game: a planet surface's buildings, the planets, asteroids, sun and nebulae of a system and the interface all pick their matching preset when you arrive; with none they keep their own look.

# scen-ch | The Scenario Editor
Quests written as plain-sentence rules, built by clicking: no code.

## scenarios | Scenarios and rules | keywords: scenario, rule, when, and, then, step, quest
A **scenario** is a quest: a list of **steps** (Not started, Search, Fight, Return, Finished...) and **rules**. Every rule is a sentence:
**WHEN** *something happens* **AND** *these are true* **THEN** *do these*.
- Every word is a drop-down or a small field: pick the kind of event, condition or action, then its station, system, item, ship, number... The choices are the game's real ones.
- **Steps** organise it: most rules say *AND the quest step is X*, and their actions *move the quest to step Y*. Click a step in the strip to see only its rules; new rules made then start with that step's condition. Add, rename (it's renamed in every rule), reorder and delete steps there.
- **Only once**: on, a rule runs the first time it matches; off, every time (e.g. a reminder each time you dock).
- Rules run top to bottom when several match; the arrows reorder them, Copy duplicates one, ✕ deletes.
- The **Problems** list checks the scenario as you edit: steps nothing leads to, rules without actions, groups nothing spawns, missing steps.
- **Test in game** (F5) starts a new game with the scenario running at the selected step - unsaved edits included.
- **Enabled** scenarios start with every new game; others start only through a *start scenario* action (or Test). **Import the main quest** writes the story as rules: a complete example of every kind of objective (it stays disabled, as the story runs on its own).
- Saved in data/scenarios.json; the scenario's progress is kept in save games.

## scen-words | Events, conditions and actions | keywords: event, condition, action, place, marker, group, timer, counter
**WHEN** (events): the scenario starts · the quest reaches a step · the player docks at a station · arrives in a system · lands on a planet · comes within some distance of a place · destroys a ship (of a type, or any) · every ship of a group is destroyed · picks up an item · has some of an item · a timer runs out · talks to a citizen on a planet · every N seconds.
**AND** (conditions): the quest step is / is not · the player has at least / fewer than N of an item · at least N drachmas · is in a system · the system's condition (boom, famine...) · its owner · reputation with an empire compared to a value · your standing with an empire at least a tier (Hostile ... Allied) · the main story's stage · a counter compared to a value · a random chance · another scenario is active / finished / failed / not started.
**THEN** (actions): move to a step · show / clear the objective (on the HUD) · play a dialogue (lines "Speaker: text") · show a message · give / take items and drachmas · change reputation · spawn N ships of a type as a named **group** at a place · place / remove a **marker** (a beacon) · leave an item floating at a place · start a **timer** · set / add to a **counter** · unlock an encyclopedia entry · start another scenario · finish or fail.
**Places**: the player · a station · a planet · a jump gate (to a system) · a marker placed earlier · a point x,y in the system. Places in another system only work while you're there.
**Names** you make up: groups (for "every ship of group X is destroyed"), markers (usable as places), timers and counters - type the same name where you use them.

# level | The Level Editor
Reshaping planets and space in the game itself: its tools and saved layouts.

## level-editor | Level Editor
Opened in the game from the right-click menu (on a planet, or in space). It pauses the game and shows the map's tools:
- **Planets:** [paint terrain](doc:level-tools), draw buildings, change walls, place columns, citizens and scenery, erase.
- **Space:** place enemy and neutral ships and asteroids, erase.
Left click uses the tool; 1-9 pick a tool; the list below the tools picks what it places; [ / ] change the brush. The wheel zooms (a middle click: the zoom back); WASD, the arrows or middle drag pan. **Save** (Ctrl+S) writes the map's [layout](doc:layouts); F10 exits.

## level-tools | Level Editor tools
- **Paint terrain** - click or drag to paint the chosen ground; the brush size sets how many tiles around the cursor.
- **Draw building** - drag a rectangle to build a Minoan palace, warehouse or temple. Buildings are at least 12 x 12 tiles (a smaller drag is enlarged); the ground under them is levelled and any scenery there removed.
- **Wall** - click a wall to cycle plain / window / door.
- **Column** - click a tile inside a building to add a column.
- **Citizen** - click to place a Minoan guard, or an android with a laser rifle, a laser bow or a labrys.
- **Scenery** - click or drag to place trees, rocks, crystals...
- **Erase** - click (or drag over) things to remove them.
- In space: **enemy / neutral ship** and **asteroid** place one of the chosen kind; **Erase** removes them (story ships can't be erased).

## layouts | Saved layouts
**Save** writes the map to its layout file in `data/` (`data/planets/<planet>.json`, or `data/space.json`): it is used from then on instead of the generated map. **Revert to generated** deletes it, so the map is generated again next time it loads.

# mesh-ch | The Mesh Editor
The game's 3D models and your own (**Meshes** on the rail, **F6**): their parts moved, turned, scaled and added from primitives; a part's vertices, edges and faces reshaped, with proportional editing, symmetry and a mirror modifier; its materials; saved as glb into the game or, in the [Mod Editor](doc:mod-editor), into your mod.

## mesh | The Mesh Editor | keywords: Find a model, New model, Import from disk, Object / Edit mode
The screen has four parts: on the left the **models** (find one by typing in **Find a model...**) and the open model's **parts**; in the middle the **toolbar** over the **3D view**; on the right two tabs: **Mesh** - the selected **part** (its name, place, the primitives to add, its **mirror modifier**, the **edit mesh** operations and its **material**) - and [Curve modeling](doc:mesh-curves) (curves drawn on a plane, made into solids). The right-click menu has the same two tabs; it opens on the one you used last (on Curve modeling while curves are picked).
- **Models** - the game's characters (art/*_3d/, gold) first, then every .glb, .gltf, .obj and mesh resource of the game and of your mod (green: your mod has its own copy). **Double-click** one to open it - it loads in the background.
- **Preview in game** (the toolbar): the model as it is - unsaved edits too - set down in front of you in the game, Talos hidden and the game running: walk or fly round it. **F8** or **Esc**: back to the editor as you left it. Opened from the title, Talos loads your latest save (a new game if there's none) and is carried over it whole - your model, its undo history, every tool as it was. Only a look: nothing is added to the game, its files or your save.
- **Parts** - the model's meshes. Click one to select it; the eye hides or shows it (hidden parts are still saved).
- **New model** (**Ctrl+N**) starts an empty one; **Import from disk** (**Ctrl+O**) opens a .glb, .gltf or .obj from anywhere on your computer - **Save as** then puts it into the game or your mod.
- The header's note says what's going on, and where saving goes now: **the game** or **mod: <name>**.

## mesh-view | The view | keywords: Perspective / orthographic, Frame selected
The view is lit like a photo studio - a warm key light with shadows, a cool fill, a rim, a soft sky for reflections - so metal, paint and glow look as they will in the game (in the game, the characters are drawn by its own merged, physically based look).
- **Middle-drag** (or **Alt+left-drag**) orbits, **Shift+middle-drag** pans, the **wheel** zooms.
- **Front**, **Side**, **Top** (**Numpad 1 / 3 / 7**; with **Ctrl** the opposite side), **Ortho** (**Numpad 5**) a flat view without perspective, **Frame** (**F** or **Numpad .**) centres on the selection, **Home** on the whole model.
- The floor grid has a line every 50 cm, the **X** axis red, **Z** blue, **Y** (up) green; the corner shows which way they point.

## mesh-object | Parts (object mode) | keywords: Add box, Add cylinder, Add cone, Add sphere, Add plane, Add torus, Delete part
- **Click** a part in the view (or in the list) to select it.
- **G** moves it, **R** rotates it, **S** scales it - with the mouse; **X**, **Y** or **Z** locks the change to that axis (again: free). A **left click** or **Enter** keeps it, a **right click** or **Esc** takes it back.
- Or type it: **Position**, **Rotation** (degrees) and **Scale** on the right.
- **Add a part**: a **box**, **cylinder**, **cone**, **sphere**, **plane** or **torus**, a metre across, at the model's origin (**Shift+A**: a box). **Duplicate** (**Shift+D**) copies the selected part, **Delete part** (**X** / **Delete**) removes it, the name field **renames** it (Enter).
- Every change can be undone: **Undo** (**Ctrl+Z**), **Redo** (**Ctrl+Y** or **Ctrl+Shift+Z**).

## mesh-bind | Parts on a character's skeleton | keywords: Auto-bind to the skeleton, Bind to bone, Bone to bind to, Unbind
A part added to a character - a primitive, a shape, a copy - is **bound** to its skeleton by itself, so it moves with the animations (the parts list says **(bound)**). The buttons under the primitives in the **PART** panel, and the right-click menu, do it by hand:
- **Auto-bind to the skeleton** - each vertex weighted to its nearest bones (up to four, the nearer the more), as the character stands now: a sleeve follows the forearm and the hand. Bind a part again after moving it: it's bound where it is.
- **Bind to bone** - the whole part on one bone, picked beside it (**Nearest**: the bone nearest the part): a helmet on the head, a sword in the hand.
- **Unbind** - the part lets go of the skeleton and stays where it's drawn (a boolean needs it unbound).
- Bound in the **T-pose**, a part is turned back with the body when saved, into the character's own pose.
- In the game a bound part is drawn as part of the character's body - its look and its animations; a part not bound stays still where it is.

## mesh-bone-parts | Parts from bones | keywords: Parts from bones, Bones to make parts for, Part from bone, Parts from bone and children, Parts from all bones
A character's bones can be given body parts of their own - a start for armour, a new body, or a stand-in to shape. **Parts from bones** (in the **PART** panel, beside the binding buttons; and the right-click menu) makes one for each bone chosen in the list beside it:
- **This bone** - the bone picked in **Bone to bind to** (**Nearest**: the bone nearest the selected part). **Bone and children** - that bone and every bone below it (an upper arm: the arm, the hand and the fingers). **All bones** - every bone but the weapon's.
- Each part is a **rounded loft** from the bone's head to the head of the child it points at, closed at both ends. Its thickness comes from the body's vertices weighted to that bone - how far they spread round the bone, ring by ring (wider than deep where the body is) - or, with none weighted to it, from the bone's length. A bone at the end of a chain (a head, the fingers, a foot) reaches as far as its vertices go, or is a short rounded cap.
- Each is named after its bone (**fore_L_part** for fore.L) and **skinned all to it**: it moves with the animations and, in the game, is drawn as part of the body. They share one new material (**Bone parts**), ready to restyle.
- Made in the **T-pose**, they're laid along the T-posed bones and turned back with the body when saved, into the character's own pose.
- All the parts made at once are **one undo step**.

## mesh-edit | Edit mode | keywords: Vertex select, Edge select, Face select, Auto select, N-gons / triangles, Show triangles, Show faces (n-gons), Extrude, Subdivide, Flip normals, Recalc normals
**Tab** switches the selected part to **edit mode** (and back). A big part - a character - is made ready in the background for a moment. Points at the same place are one point: a seam in the texture or a hard edge doesn't split what you see and move.
- **Faces are n-gons**: a face is the flat triangles that make it - a quad, or a face of any number of corners - and edit mode shows it whole, without the diagonals of its triangles. A model read from a file has its faces found again: flat triangles side by side make a quad, then flat quads and triangles round a flat rim make an n-gon (a corner is never made straight, and no point is left inside a face). **N-gons / triangles** (its toolbar button, or **Show triangles** in the right-click menu) shows every triangle instead. A face picked in face mode is picked whole; deleting takes whole faces; extruding an n-gon keeps it one face, with a quad for each wall.
- **1**, **2**, **3** pick **vertices**, **edges** or **faces**; **4** is **Auto select**: a click picks what's under the mouse - a point when it's within a few pixels of one, else an edge, else the face (shown faintly before you click). Points, edges and faces can be picked together (Shift+click); moving them moves all their points, Extrude takes the faces, Delete takes everything picked, Merge the points. A box picks the points in it, and the edges and faces wholly in it. **Click** picks one (the nearest corner or edge of the face under the mouse), **Shift+click** adds or takes away, **dragging a box** picks everything inside it (seen or not; Shift adds). **A** selects all, **Alt+A** nothing.
- **G**, **R**, **S** move, rotate and scale the selection, as in object mode (the axes are the world's).
- **Extrude** (**E**) - the selected faces pulled out, with walls round their border; they then follow the mouse along their normal (click to place them).
- **Delete** (**X** / **Delete**) - in vertex mode the faces touching the selected points, in edge mode those along the selected edges, in face mode the faces; points left with no face go too.
- **Merge** (**M**) - the selected points made one, at their centre. **Subdivide** - the selected faces cut in four (the faces beside them split to match, so there are no cracks). **Flip normals** - the selected faces (all, if none) turned to face the other way. **Recalc normals** - the shading worked out again from the faces (hard edges stay hard).
- A skinned part (a character's body) keeps its bone weights through every edit: new points take them from the points they're made from.
- In edit mode **Undo** and **Redo** step through the part's edits; back in object mode (Tab) they are one step of the model's history.

## mesh-move | Dragging the selection: smart axis and perspective moves | keywords: Smart axis move, Perspective move
A press on what's selected and a drag moves it - two ways, a button each on the toolbar:
- **Smart axis move** - along the one of the selection's own axes the drag goes most: along its surface (X, red), across it (Y, green) or out along its normal (Z, blue); a part moves along its own axes.
- **Perspective move** - freely over the plane you're looking at most squarely: the ground from above or below, the upright plane facing you from the front or the side. While the drag runs along one of that plane's axes on screen it snaps to it (the axis drawn); off it, it's free again.
Either way it's a move like G: proportional editing, symmetry and undo apply; let go to keep it, right-click to cancel.

## mesh-spherize | Spherize | keywords: Spherize
**Spherize** (Shift+Alt+S, the EDIT MESH row, the right-click menu): the selected points pushed onto a sphere round their middle, as big as they are from it on average, by a strength from 0 (as they were) to 1 (a sphere). Move the mouse away from the middle to make it rounder (twice as far as you started: all the way), or type 1-9 (10-90%) or 0 (100%); click to keep it, right-click or Esc to cancel. Proportional editing and symmetry apply; one undo step.

## mesh-curve | Curve deform | keywords: Curve deform
**Curve deform** (**V**, the EDIT MESH row, the right-click menu) bends the selected points along a curve. The curve starts fitted through the selected points - its ends on the two end points, its handles set so it passes through the others (as near as one curve can) - so nothing moves until you change it; it's drawn over the model: two **ends** (squares) and two **handles** (round knobs on dashed lines). **Drag** any of them in the view - over the plane facing you, or along an axis with **X**, **Y** or **Z** typed (again: free) - and the points follow: with **Snap onto the curve** on (the default) every selected point sits exactly on the curve, spaced along it by length as it was along the straight line; turned off, each keeps its offset from the line, carried and turned by the curve at its place along it - for bending an area of points. Points pulled by proportional editing always keep their offsets. With **faces** selected (face mode, or whole faces picked in Auto) the curve is fitted through the faces' middles and carries the faces whole - each keeps its shape, bent and turned along the curve (no snapping). An end dragged takes its handle with it. While it runs a bar at the top of the view has **Reset the curve** (back as it started, the points where they were), **Snap onto the curve**, **Keep** and **Cancel**. **Enter** keeps it, **Esc** or a **right click** cancels; the middle mouse still turns the view. Proportional editing (the wheel: its radius) and symmetry apply; one undo step.

## mesh-flatten | Flatten | keywords: Flatten
**Flatten** (**Shift+Alt+F**, the EDIT MESH row, the right-click menu) presses the selected points onto a plane through their middle - by default the plane that fits them best (least squares), or the selected faces' own plane when faces are selected. Type **X**, **Y** or **Z** (or use the bar at the top of the view) to flatten onto the part's own axis plane instead - every point given the middle's X, Y or Z; again: back to the best fit. Move the mouse away from the middle to flatten further (twice as far as you started: all the way), or type 1-9 (10-90%) or 0 (100%); click or **Enter** keeps it, a right click or **Esc** cancels. Proportional editing and symmetry apply; one undo step.

## mesh-refs | Reference images | keywords: Add reference image, Remove reference image, Show / hide reference image, Reference images
**Reference images** (the REFERENCE IMAGES panel on the right) are pictures from anywhere on this computer (png, jpg, webp) shown in the view to model from - drawings of a ship from the front and the side, say. **Add reference image** picks the file; the list shows the model's images - pick one to change it:
- **View**: Front, Side or Top - upright in that view, centred on the model's origin, shown while you look along that view (it fades as you turn away) - or a **Free plane**, placed (Offset X / Y / Z) and turned (Turn, Tilt) anywhere in the scene.
- **Layer**: **Behind the model** (the model, the floor grid and the edit overlays drawn over it) or **Over the model** (drawn over it, see-through by its opacity; the points and wireframe still on top).
- **Opacity**, **Size** (its height in metres; the width follows the picture) and **Offset X / Y** (a view's picture moved across and up in that view).
- **Show / hide** keeps it but hides it; **Remove** takes it away (the picture file isn't touched).
They're kept with the model (by its path, in your user data) and come back when it's opened again. The pictures are read in the background.

## mesh-island | Select island by material | keywords: Material island
**Material island** (L, the EDIT MESH row, the right-click menu): from the selected faces - or the faces round the selected points, or the face under the mouse when nothing's selected - every face joined to them across shared edges that has the same material, stopping where another material starts. It adds to the selection and shows faces.

## mesh-knife | The knife | keywords: Knife
The **Knife** (**K**, its toolbar button, or the right-click menu in edit mode) cuts the faces along a path you draw:
- **Click points on the surface**: each snaps to a face's corner (a square) or the middle of a side (a diamond) when the mouse is near one, else lands on the face (a dot); hold **Ctrl** for no snapping. A dashed line runs on from the last point to the mouse.
- **Enter** or **Space** makes the cut; **Backspace** (or **Ctrl+Z**) takes the last point back; **Esc** or a **right click** stops. Middle-drag still turns the view while you draw.
- Between two points the cut follows the surface - as the line looks on the screen, over the faces facing you - and every edge it crosses gets a new point. Each face it crosses from side to side is split in two (a cut that starts or ends inside a face starts or ends at that face's side); the faces beside the new points get them as corners (n-gons), so nothing cracks. Points bent in the middle of a face are kept as corners of the cut.
- New points take their UVs, colours, normals and bone weights from the edge they're on: hard edges and UV seams stay as they were, smooth stays smooth.
- **Shift+K** cuts **right through** the part, front and back, along the line between two clicks - a ring round a box or an arm.
- With **Symmetry** on, the mirror image of the cut is made too (a cut across the seam is made once). The new edges are selected afterwards, and the whole cut is one **Undo** step.
- Only the faces cut are made again, so it's quick on a character too (a cut over a few faces of a 70,000-triangle body takes a few hundredths of a second).

## mesh-dissolve | Dissolve | keywords: Dissolve
**Dissolve** (**Ctrl+X**, the **EDIT MESH** panel, or the right-click menu in edit mode) takes points or edges out and makes faces one - the opposite of the knife:
- **Points** (vertex mode): the faces round each point are made one face and the point goes; the new face is filled again from its outline. A point in a straight run along a side (one the knife left in the middle of an edge) just leaves that side. A point on an open border goes without leaving a hole.
- **Edges** (edge mode): the two faces either side of each edge are made one n-gon - the triangles stay as they are, so a bent pair of faces keeps its shape. Points left in a straight line along the new face's side go too.
- **Faces** (face mode): the faces side by side are made one, each group of them; the points left inside go, and the face is filled again from its outline.
- In **Auto select**, whatever's picked - faces, edges and points - is dissolved together.
- The corners keep their UVs, normals and bone weights; seams and hard edges round the new face stay. With **Symmetry** on, the mirror twins are dissolved too. One **Undo** takes it back. Only the faces changed are made again, so it's quick on a character too.

## mesh-duplicate | Duplicate | keywords: Duplicate selection
**Duplicate** (**Shift+D** in edit mode, the **EDIT MESH** row, the right-click menu) copies the selected faces - their points too, with their UVs, normals, colours and bone weights - as new faces of their own, not joined to the old ones. The copy is selected and moves with the mouse straight away (as **G**: X / Y / Z lock an axis, proportional editing and symmetry apply); click to keep it there. The copy and the move are an undo step each: a cancelled move leaves the copy where it was made. Selected points or edges that make up no whole face copy nothing - the mesh is made of faces (in object mode **Shift+D** duplicates the whole part).

## mesh-merge-distance | Merge by distance and Auto merge | keywords: Merge by distance, Auto merge
**Merge by distance** (**Alt+M**, the **EDIT MESH** row, the right-click menu) makes the selected points - all of them, when none are selected - that are closer to each other than the **distance** beside it into one point each, at the middle of each group; the note says how many went. It's the way to weld a seam of doubled points (a mirror applied without merging, a duplicate laid back on its original, an imported model in pieces). Faces left with two corners on one point lose that side; a triangle that's left with no area goes. One undo step. The distance is in metres in the part's own space; it starts at 0.0001 m.
**Auto merge** (the toggle beside it): after every move, turn, scale, spherize, inset or loop slide, the points it moved that ended within the distance of another point are welded to that point - the one that stayed keeps its place. Drag a corner onto another (snapping with a typed coordinate, or dragging close) and they become one. The weld is part of the move's undo step.

## mesh-inset | Inset | keywords: Inset
**Inset** (**I**, the **EDIT MESH** row, the right-click menu) makes a ring of new faces inside the border of the selected faces - the selection inset as one region, so faces side by side share the ring round them all, and a single face gets a smaller face inside it with a quad along each of its sides. Move the mouse towards the selection's middle to widen the ring (started near the middle: the further it's moved, the wider), or type the width in metres (digits and a point; Backspace takes one back). Each corner goes in so that the ring is as wide along every side. Click or Enter keeps it, right-click or Esc cancels - nothing changes. The inner faces are selected afterwards, ready to extrude; it's one undo step. A selection with no border (a whole closed part) has nothing to inset from.

## mesh-fillet | Fillet | keywords: Fillet, chamfer, bevel
**Fillet** (**Ctrl+B**, the **EDIT MESH** row, the right-click menu) rounds off the selected edges (in face mode, the border of the selected faces; a whole closed selection - every edge between them). Each edge between two faces becomes a strip of quads whose profile is an arc touching both faces; its sides move back along the faces by the width. Move the mouse away from the selection's middle to widen it (towards: narrower), or type the width in metres (digits and a point; Backspace takes one back). The **wheel** or **+ / -** sets the segments - the rows of quads across (4 to start, then as many as last time; **1** is a flat chamfer). The width is held where it would push corners past each other (the hint says so). Where filleted edges meet, the corner is closed: one edge ending - its arc becomes part of the face across the end; two going on through a point - their arcs join in a mitre; three or more - a rounded fan. A closed part stays closed. Click or Enter keeps it, right-click or Esc cancels - nothing changes. The new strips are selected afterwards; it's one undo step.

## mesh-loop-cut | Loop cut | keywords: Loop cut
**Loop cut** (**Ctrl+R**, the **EDIT MESH** row, the right-click menu) adds a new edge loop round a ring of quads:
- Point at an edge: the ring across it shows - through each quad to its opposite side, on to the next quad, stopping at a triangle, an n-gon or an open border, or all the way round (a box, a cylinder, an arm).
- **Click** cuts it: every edge it crosses gets a new point and each quad is split in two; a triangle or n-gon where it stops gets the new point as a corner (nothing cracks). New points take their UVs, normals and bone weights from the edge they're on.
- Then **move the mouse** along the edge first pointed at to slide the loop towards one side or the other; click (or Enter) keeps it there. **Right-click** or **Esc** keeps it in the middle.
- With **Symmetry** on, the mirror image of the ring is cut too (unless it's the same ring). The new loop's edges are selected; the cut and the slide are one undo step. Esc or a right-click before the cut stops it.

## mesh-select-loop | Select loop and ring | keywords: Select loop, Select ring
- **Alt+click** an edge (edge mode or Auto select) selects its **loop**: on from both its ends, straight across each point where four edges meet, to a pole (a point with three or five edges), an open border (along which a border edge's loop runs) or all the way round. **Shift+Alt+click** adds it to the selection. In vertex mode it selects the loop's points; in face mode Alt+click picks the **ring of quads** across the edge nearest the mouse. (Alt+drag still turns the view: a click is a press and let-go without moving.)
- **Select loop** (the **EDIT MESH** row, the right-click menu) does the same for every selected edge.
- **Select ring** selects the edges across the ring of quads either side of each selected edge - the ones a loop cut would cross.
With **Symmetry** on, the mirror twins are selected too.

## mesh-proportional | Proportional editing | keywords: Proportional editing, Falloff, Proportional radius, Connected only
With **Proportional** on (**O**), moving, rotating or scaling points drags the points round them along - fully at the selection, fading to nothing at the **radius**: the circle drawn round the selection while you move. The **mouse wheel** (or Page Up / Page Down) while moving changes the radius, or type it in **Radius**.
- **Falloff** (**Shift+O** goes through them) - how the pull fades: **Smooth**, **Sphere** (round, sharp at the edge), **Root**, **Linear**, **Sharp** (only the nearest) or **Constant** (everything inside alike).
- **Connected** (**Alt+O**) - only points joined to the selection by edges, the distance measured along them: an arm doesn't drag the body beside it.

## mesh-mirror | Mirror and symmetry | keywords: Mirror across, Clip at the seam, Merge distance, Apply the mirror, Symmetry X, Symmetry Y, Symmetry Z, Symmetrize
Make one half of a model and get both:
- **The mirror modifier** - tick **X**, **Y** or **Z** under **Mirror modifier**: the part shows a mirrored copy across its own axis, live while you edit it. **Clip** keeps points from crossing the mirror's plane (those on it stay on it); **Merge** is how close to the plane points are joined with their twins. The modifier stays a modifier while you work (the part's list entry says **(mirror)**) and is **applied** into the mesh when you save - the saved file has both halves, seamless. **Apply** makes it part of the mesh now.
- **Symmetry X / Y / Z** (toolbar) - edits mirror across that axis: move a point and its twin on the other side moves the mirrored way.
- **Symmetrize** - copies the +X side onto the -X side (**Shift+click**: -X onto +X; the axis is the first symmetry axis turned on). Each point is paired with its nearest twin, so the two sides must already roughly match.

## mesh-symmetrize-topology | Symmetrize topology | keywords: Symmetrize topology
**Symmetrize topology** (**Ctrl+Shift+M**, its toolbar button beside **Symmetrize**, or the right-click menu in edit mode) rebuilds one side as the mirror of the other - its faces, cuts and points, not only where they are. Use it after adding detail to one half (knife cuts, extrusions, subdivisions): the other half gets the same.
- The part is cut at the mirror plane (its own axis plane through its origin; the axis is the first **Symmetry** axis turned on, else X): faces crossing it are split along it, with new points on the edges.
- The side being replaced is deleted, and the kept side is mirrored onto it - faces turned the right way round, normals mirrored, UVs copied as they are - and welded along the seam: the points on the plane are shared, so the mesh stays closed.
- Which side is kept: the one you changed since the two sides last matched (moved points, or points the other side hasn't got); **Shift+click** the other way.
- Each face stays a face (n-gons too). A character's mirrored half follows its own bones: a bone named **.L** / **_L** / **Left** gives its weights to its **.R** / **_R** / **Right** twin and back; bones in the middle stay.
- One **Undo** takes it back; the new half is selected afterwards.

## mesh-materials | Materials | keywords: Albedo colour, Glow colour, Albedo texture, Roughness texture, Glow texture, Normal map, Transparency, UV scale, Cull mode, About this material, Material being edited
Each part has one or more **surfaces**, each with its own material. Pick the **Surface** in the **MATERIAL** panel (right): its material shows under it with a **preview ball**, ready to change. Or click a material in the [Materials tab](doc:mesh-materials-library) to edit that one.
- A change shows at once on **every surface that uses the material** - in every part of the model - and Undo takes it back (a slider dragged is one step).
- **A full material** (props, shapes, imported models): **Colour** (with its opacity), **Metallic**, **Roughness**, **Glow** and **Glow colour** (physically based: metallic 1 is bare metal, roughness 0 a mirror), and pictures for the **Albedo texture**, **Roughness texture**, **Glow texture** and **Normal map** (with how deep its **Bumps** look) - each with **Replace** (a PNG, JPG or WebP of yours, copied into the game or your mod under art/materials/ when you save) and **Clear**; **Alpha** (see-through), the **UV scale** (how often the textures repeat) and the **Sides** drawn (front, back, or both for thin things).
- **A character's material** shows only **Colour**, **Metallic**, **Roughness** and **Glow**: the game merges a character into one surface with one shader and keeps just these of each material, by its name, in the character's model.json - which saving the character writes. Materials named AUT_Armor, AUT_Red and AUT_Glow take the colours a character is recoloured with: keep those names.
- The game's looks and the characters' materials in the library are kept as they are: **Duplicate** one to change your own copy.

## mesh-materials-library | The material library | keywords: Material library, Find a material, Material group, New material, Duplicate material, Rename material, Delete material, Material preview, Material name
The **Materials** tab (left, beside **Models** and **Shapes**) shows every material as a ball - drawn once in the background and kept, turning while the mouse is on it - in four groups (the buttons above the balls; **All** for every one), with **Find a material...** to narrow them by name, group, kind or wearer:
- **This model** - the open model's own materials;
- **Characters** - every character's named materials (each says who wears it: the automaton's armour is on many);
- **Presets** - the game's looks: bronze, gold, steel, dark metal, painted armour, Minoan red, navy, cloth, stone, cyan and amber glow;
- **Mine** - your own (data/materials.json; in the [Mod Editor](doc:mod-editor) your mod's data/materials.json.merge, so a mod can bring materials).
Using one:
- **Click** a ball: its settings show in the MATERIAL panel. **Double-click** it: the selected part's surface gets it - in edit mode, the **selected faces** do (split into a surface of their own when they're only some of theirs). Or **drag** it onto a surface in the view: that surface gets it (onto a selected face in edit mode: the selected faces).
- A library material given to the model is one material however many surfaces have it: edit it (in the tab or on any of them) and all change.
- **New material** makes one of yours (a character's kind when a character is open), **Duplicate material** copies the picked one as yours - the way to change a built-in look - **Rename material** names yours, **Delete material** removes yours (the built-in looks only in a mod, asked first; surfaces that have it keep it).
- The library is saved with the model (Save), and at once when you add, rename or remove a material.

## mesh-shapes | The shape library | keywords: Shapes, Find a shape, Add to model, Save as new shape, Rename shape, Remove shape, Shape preview
The **Shapes** tab (left, beside **Models**) holds **120 shapes** to build from, each a recipe - a generator and its numbers - in six categories: **Basic** (boxes, wedges, prisms, pyramids, cylinders, cones, tubes), **Round** (spheres, domes, capsules, tori, superellipsoids, an egg), **Architecture** (Doric, Ionic, Corinthian, Tuscan and Minoan columns, arches, stairs and spiral stairs, domes, an obelisk, a step pyramid, amphorae and other vessels, the horns of consecration, a beehive tomb), **Mechanical** (gears, nuts, bolts, pipes and elbows, springs, beams, a chain link, a pulley, a piston), **Organic** (rocks, crystals, horns, tentacles, a spiral shell, knots, a mushroom, a leaf) and **Sci-fi** (greeble panels, vents, hull plates, a thruster, tanks, an antenna, a dish, pylons, a docking ring, a wing).
- Each is drawn once in the background and kept; with the mouse on it, it **turns**. Pick a category above the pictures (**All** for every one) or type in **Find a shape...**.
- **Double-click** a shape to add it as a part at the model's origin, or **drag** it into the view: it lands where you drop it, on the part under the mouse or on the floor.
- **Click** one: its numbers show in the **SHAPE** panel on the right, with a preview - change them, then **Add**. Every shape is solid and closed, so booleans work on it.
- A part made from a shape **keeps its recipe**: select it and its numbers are in the SHAPE panel - change one and the part is made again (Undo takes it back). The recipe is saved with the model. Once you **edit its vertices** (edit mode), it is a plain mesh.
- **Save as new shape** keeps the selected part's recipe - or, for a part with none, its mesh itself - (or the picked shape with your numbers) as a new shape, with a name and a category (**Mine** by default). **Rename shape** and **Remove shape** change the library; the 120 built in ask first.
- The library is data/shapes.json; in the [Mod Editor](doc:mod-editor) new and changed shapes go into your mod (its data/shapes.json.merge, a mesh shape's mesh into art/shapes/), so a mod can add shapes.

## mesh-boolean | Booleans | keywords: Union, Difference (A minus B), Intersection, Slice, Keep the cutter
Two parts made one, cut or trimmed - as solids:
- Select two parts: click one, then **Ctrl+click** (or **Shift+click**) the other - in the view or in the parts list. **A** is the one selected first, **B** the other (both outlined; the panel says which is which). Or select A and **right-click** B: the menu's **Boolean** group works on the two.
- **Union** - A and B made one part. **Subtract** - A with B cut out of it. **Intersect** - only what both share. **Slice** - A cut in two by B: the piece inside B becomes a part of its own, the rest stays A.
- The result replaces A; B is removed - or, with **Keep B (hidden)**, hidden (the eye in the parts list shows it again). Each surface keeps its material; the faces B cuts into A take B's. One **Undo** takes it all back.
- It's worked out in the background (two parts of 2,000 triangles each take a few hundredths of a second). Both parts must be **closed** solids: a plane, or a mesh with a hole in its skin, is refused, and the note says why. A part skinned to a skeleton can't take part (its weights would be lost).

## mesh-curves | Curve modeling | keywords: Curve modeling, Line, Spline, Circle, Arc, Rectangle, Polygon
The right panel's second tab (and the right-click menu's): model hard surfaces the quick way - **draw an outline, then pull it into a solid**. Curves are drawn on a **construction plane**, snapped to its grid and to points; picked and reshaped by dragging their points; then [extruded, revolved, lofted, swept or piped](doc:mesh-curves-solids) into new parts. A model's curves are kept with it (saved beside it as `<model>.curves.json`, in its variant) and shown over the view in blue (picked: amber, their points as white squares).
- **Wireframe** (the toolbar's Wireframe button, **Shift+W**): the parts' edges drawn over them in object mode - every quad as a quad (its two triangles' shared edge left out), edges behind a surface hidden - to see a stretched or folded patch at a glance.
- **Sketch tools** (keys work while the Curve modeling tab is open): **Line** (**L**) - click points, a polyline; **Spline** (**P**) - a smooth curve through the points you click; **Circle** (**C**) - its centre, then the rim; **Arc** (**Shift+C**) - its start, its end, then a point it passes through; **Rectangle** (**Shift+R**) - two opposite corners (**Alt** held: from the centre); **Polygon** (**Shift+P**) - the centre, then a corner (the wheel or **+ / -**: how many sides).
- A line or spline: **click its first point** to close it into a loop; **Enter**, **right-click** or a double click ends it open; **Backspace** takes back the last point. The tool stays on for the next curve; **Esc** stops it (with points placed: drops them first).
- **Typed sizes**: while drawing, type a number and **Enter** - a line's next segment that long (the way the mouse points), a circle's or polygon's radius, a rectangle's "width height". The distance from the last point shows beside the cursor.
- **Undo** (**Ctrl+Z**) takes back each curve and each change to one.

## mesh-curves-overview | The overview | keywords: Overview, Part, New part from the selected, Ungroup, Move to part
At the top of the Curve modeling tab, the **OVERVIEW** lists the whole model as a tree: first the **parts** - each a group of solids (with theirs under it) - then **Solids** in no part (each with the curves it's made from under it - a cut curve marked "(cut)"), **Meshes** (plain parts) and **Curves** no solid uses yet.
- **Parts (groups of solids):** select some solids, right-click one: **New part from the selected** - they're grouped into a part (saved in the glb, a part of the model: the Mesh tab's list shows it too, with its solids under it). Move the part and its solids move together - their curves with them. A new solid made while a solid of a part is selected joins that part. Right-click a part: Select its solids, Hide / Show, Duplicate, **Ungroup**, Delete (with its solids); a solid: **Move to part ›** (or out of it).
- The Mesh tab's **parts list** is the same kind of overview: parts with their solids and meshes under them; click a part to select all of it, right-click a row for its menu (Hide / Show, Duplicate, Delete, New part from the selected, Move to ›, Ungroup...), double-click to rename.
- **Dragging a curve's point:** it moves on the curve's plane; **X / Y / Z** while dragging lock it to that axis (again: free) - lift it, lower it.
- **Rename:** right-click a part, solid or curve - **Rename** - or select it and press **F2** (or double-click its row); type the name, Enter.
- **Move, turn, scale a part as one:** in object mode, **G / R / S** (and the gizmo) move every selected solid together, round their middle; when all of a part's solids are selected (click the part's row), the part itself moves - its solids stay in it. One undo step.
- **Click** a solid or a curve to select it; **Ctrl / Shift+click** for more - solids and curves together. It's the same selection the view and the boxes below use: pick two solids to join them, a solid's curves to drag or reshape them, a curve to see its CURVE box...
- Under each solid: its own curves, and each **tool step** ("Cut: an extrusion"...) as a row of its own with that step's curves under it - click a step to select its solid and pick its curves.
- **Right-click** a row for its menu:
  - a **solid**: Hide / Show, Duplicate, Delete, Pick its curves, Make plain mesh, Detach its last tool, **Attach to ›** another solid (cut from / join to / common with it - live);
  - a **tool step**: Role (Cut / Join / Common), Hide / Show its ghost, **Detach** (a solid of its own again), **Attach to ›** another solid (moved there), Delete step (its curves stay);
  - a **curve**: Hide / Show, Pick, Duplicate, Delete, **Detach from** its solid (taken out of its step; a tool step with no other curve goes with it), **Attach to ›** a solid (a new cut / join / common step).
- **Double-click** a name to rename it. The **eye** hides or shows it, everything it shows in the view: a solid and its ghosts; a curve, and the ghost of a tool made only of hidden curves; a tool step's ghost. (Hidden is only for seeing: the solid's shape doesn't change. One **Undo** step.)

## mesh-curves-plane | The construction plane and snapping | keywords: Auto plane, Ground plane, Front plane, Side plane, View plane, Selection's plane, Snap to the grid, Grid step, Snap to points, Guides
- The plane is picked in the **Plane** dropdown under the sketch tools. **Auto** (the default): the plane is the **surface under your first click** - click on a part's face and the curve is drawn flat on it - or, in empty space, the ground. **Ground** (X and Z), **Front** (X and Y), **Side** (Z and Y), **View** (square to the view) or **Selection** (through the selected faces in edit mode, or the picked curve) fix it. While a tool is on, the plane shows as a faint grid round the cursor.
- **Grid** snaps points to the plane's grid (**Grid step**, 0.05 m at first); **Points** snaps them to the curves' points, ends, middles of sides and centres, and to the parts' corners - the ring at the cursor is coloured by what it caught. Hold **Ctrl** for no snapping.

## mesh-curves-edit | Editing curves | keywords: Move curves, Turn curves, Scale curves, Simplify curve, Delete curves, Duplicate curves, Mirror curves, Radial array, Insert point, Dissolve point, Smooth point, Sharp point, Offset curve, Fillet corners, Join curves, Bridge curve, Reverse curve, Close / open, Union curves, Subtract curves, Intersect curves
- **Click a curve** in the view to pick it (**Shift+click**: more, or one off again); a click in empty space lets them go. Drag a picked curve's **point** to move it, or the **curve itself** to move it whole - smoothly, from where you pressed: after a few pixels the drag picks the axis (X, Y or Z) that runs closest to your drag on screen, drawn through it in its colour (X red, Y green, Z blue) with how far it's gone; **X / Y / Z** while dragging switch to that axis (the same again: free on the axis plane facing you); **Shift** as you start (or Perspective move in the menu): free on that plane; **Ctrl**: whole grid steps. **Guides** (on by default - the Guides box by Points; **Alt** while dragging: off): when a dragged point's X, Y or Z comes within a few pixels of another point's (its own curve's first) or of a flat face's level, it snaps there and a dashed guide in that axis's colour shows to what ("Y same as a point on this curve", "Y level with a flat face"). **Double-click a curve** to put a point into it where you clicked (a circle, an arc or a bezier becomes a path of points first - the same shape). **Double-click a point** to dissolve it - the curve runs on between its neighbours (an arc's middle point: a straight line; a curve keeps at least two points, a closed one three; a baked solid's edge keeps its ends). The solids hide the curves behind them: only what you'd see of a curve is drawn, and picked. **Right-click a picked curve's point** for **Smooth point** (the curve bends smoothly through it) or **Sharp point** (a corner: straight sides either side of it) - the curve becomes a path of points, each smooth or sharp.
- **In 3D:** with curves picked, **Move curves** (**G**) moves them over the plane facing you - up, down, anywhere; **Turn curves** (**R**) turns them about their middle (round the line of sight); **Scale curves** (**S**) scales them about their middle. **X / Y / Z** while doing it: along (or about) that axis - again: free. Moves snap to the grid and turns to 15° (**Ctrl**: free); type a number for an exact distance, angle or factor. Click or **Enter** keeps it, **Esc** or right-click cancels. A curve's plane turns with it, and the solids made from it follow. (With curves picked, G / R / S work on them rather than the part.)
- **Delete curves** (**X / Delete**), **Duplicate curves** (**Shift+D**), **Mirror curves** (a copy across the model's X), **Radial array** (six round the Y axis).
- **Offset curve** - a copy moved out (or in) by a distance in its plane: corners stay mitred, a circle's radius grows. The mouse sets it, or type it and **Enter**.
- **Fillet corners** - the corners of lines, rectangles and polygons rounded (the mouse or a typed radius; 0: sharp again). The radius stays with the curve: its points still drag, the rounding follows.
- **Union curves**, **Subtract curves**, **Intersect curves** - booleans of closed curves, worked out on the **first picked** curve's plane: pick two or more, and they're replaced by the result (one **Undo** step). Curves on other planes are brought onto it along its normal: on a parallel plane (lifted or lowered) they land as they are (a lifted circle cuts the same circle); at an angle they're projected - as seen square-on from the first one (a tilted circle cuts an ellipse); one standing edge-on to it is left out. The note says which were brought down, projected or left out. Union makes one outline (a gap they enclose becomes a hole); Subtract takes the others from the **first picked** - curves inside it become its holes; Intersect keeps what they all share. Extrude or fill the results together: a solid with its holes, still following its curves. The results are lean: a curve that comes through whole stays as it was (a circle hole is still a circle), the rest become **paths** - corners and straight sides kept as they are; a bend that's part of a circle drawn as that exact arc through its ends and one middle point; other bends get smooth points spread evenly along them. A circle minus another overlapping it is four points.
- **Simplify curve** - the picked closed curves with more points than they need (a dense outline) made lean the same way; solids made from them follow.
- **Join curves** - two open curves made one at their nearest ends. **Bridge curve** - a smooth curve between the nearest ends of two picked curves, leaving each along its own direction (its two handles drag). **Reverse curve** - runs the other way. **Close / open** - a line or spline made a loop, or opened.

## mesh-curves-solids | Solids from curves | keywords: Extrude, Revolve, Loft, Sweep, Pipe, Fill, Steps round, Push / pull faces, Fillet edges, Inset faces
Each makes a **new part** (one **Undo** takes it back). Closed curves make **closed solids**, facing out, so the [booleans](doc:mesh-boolean) work on them; open curves make sheets (walls). The solids are [procedural](doc:mesh-curves-procedural): they follow their curves.
- **Holes:** closed curves inside a closed curve (in its plane) are holes - pick the outline and the curves inside it, then **Extrude** or **Fill**: a plate with its holes, no boolean needed. A curve inside a hole is a solid again (an island).
- **Extrude** (**E** with curves picked) - pushed along their plane's normal. The mouse sets how far (a preview shows; snapped to the grid step, **Ctrl**: free), or type it; click or **Enter** makes it, **Esc** or right-click cancels. Sharp corners stay crisp, rounded ones smooth.
- **Revolve** - the profile turned round an axis: a two-point line picked with it, else the model's Y axis (a curve drawn on the ground: its X line). The mouse sets the angle (by 15°, **Ctrl**: by 1°) or type it; 360° closes it. **Steps round** sets how smooth.
- **Loft** - a skin through the picked curves, in the order you picked them (closed ones capped; loops wound either way are lined up).
- **Sweep** - the first picked curve (the profile) carried along the second (the path), turned with it without twisting.
- **Pipe** - a round tube along each picked curve (the mouse or a typed radius); a closed curve makes a ring.
- **Fill** - closed curves filled with flat faces.
- **On the mesh** (edit mode): **Push / pull faces** (the selected faces pulled out or in), **Fillet edges** (the selected edges rounded), **Inset faces**, **Flatten** - the mesh tools that go with curve modeling, at hand in the same tab.

## mesh-curves-procedural | Procedural solids: they follow their curves | keywords: SOLID, Height, Angle, Radius, Steps, Both ways, Role, Curve role, Ghosts, Add, Picked curves, Other solid, Separate, Curve name, Corner radius, Closed, Pick its curves, Make plain mesh, Negative, Make the cut positive, Bake, Rename
A solid made from curves keeps its **recipe** - which curves, which operation, its height / angle / radius and steps - and is **made again from its curves whenever they change**: drag a curve's point and the solid reshapes as you drag; round a curve's corners, offset it, undo or redo a change - the solid follows. Its material stays.
- Select the solid (a part) and the Curve modeling tab shows its **SOLID** box with its whole **recipe** - every step, editable at any time, made again at once (each change one **Undo** step): an extrusion's **height** (minus: the other way) and **Both ways** (half each side of its curves' plane), a revolve's **angle** and **steps**, a pipe's **radius**; and for each boolean step (a cut, a join...) its **role** - **Join** (union), **Cut** (subtract), **Common** (intersect) - switch it any time, and **Separate** (that step's tool solid a positive part of its own again). Steps inside steps show indented. **Pick its curves** picks the curves it's made from, ready to drag.
- **Ghosts:** a solid that's inside another's recipe (cutting it, joined to it, or shared with it) - or a curve with the **Cut** role inside a step - doesn't vanish: it shows where it is, see-through and drawn through the solid - **red** cutting, **green** joined, **blue** common - following every change live. Only a preview (never saved); the **Ghosts** box (by Grid / Points) turns them off.
- **Adding tools to a solid:** the SOLID box's **Add** row - choose **Cut**, **Join** or **Common**, then **Picked curves** (the curves you've picked become a new step: extruded both ways from their plane to the solid's height - change it in the recipe) or **Other solid** (select the solid, Ctrl+click another: it becomes a new step). Each new step shows in the recipe with its own settings and role, a ghost, and Separate; one **Undo** takes it back. Add as many as you like - they nest.
- **Roles everywhere:** every solid has a **Role** - **New solid (positive)** by default, or **Cut / Join / Common with the solid it's in** (a live boolean: the solid it's in keeps the recipe, and the role can be switched there any time). An extrusion or fill made from several curves lists **each curve with its own role**: **Add** (its outline part of the solid) or **Cut** (taken out of the others - a bite or a hole): one clean solid, made again from its curves live. In an extrusion each curve also has its own **height** and **Both ways** (the step's until you change them): a cut curve can be a shallow pocket or go right through, an added one stand taller or lower - everything that adds is built first, then everything that cuts is taken away. (With no roles set, a curve inside another is a hole, as drawn.)
- The **CURVE** box (under CURVES) shows the picked curve's own properties: its **name**, a circle's **radius**, a line's / rectangle's / polygon's **corner radius**, **Closed** - changed at any time, live (the solids made from it follow).
- **Moving a solid moves its curves.** A solid's place (move, turn or scale the part) is its curves' place too: they're drawn, picked, snapped and dragged where the solid is. A new solid made from them is put there as well, and copies made from them (duplicate, offset, mirror...) appear where they show.
- One curve can drive several solids (a profile both extruded and piped), and a duplicated solid (**Shift+D**) follows the same curves - move the copy and it keeps its place while sharing the shape (the curves show with the first).
- **Positive or negative:** a solid is **positive** (it adds) by default. While extruding, **N** makes it **negative**: the preview turns red and the hint names the solid it will cut - the one it's in - and when you click it's cut from that solid, live (reshape the curve: the pocket or hole follows). **Negative** in the SOLID box does the same to a solid already made; **Make the cut positive** (on the cut solid) gives the latest cutter back as a positive solid of its own, where it was.
- **Live booleans:** a boolean of two solids made from curves (**Union**, **Subtract**, **Intersect** - not Slice) stays live: the result keeps the recipe "A op B" and is worked out again whenever either one's curves change (while you drag, a few times a second). B's curves show where B was. With a plain mesh on either side the result is a plain mesh.
- It stops following its curves (a **plain mesh** from then on) when you edit its mesh in edit mode, when it's the **A** of a boolean with a plain mesh (or a Slice), or with **Make plain mesh** - **Undo** links it again. A solid whose curves are deleted stays as it was.
- **Bake** (the SOLID box; right-click the solid in the overview or the Mesh tab's list; or the view's right-click menu, Curve modeling tab): the solid made one **Baked** solid whose **curves are its edges**. The solid as it is - its tools worked in - and every other solid touching it (overlapping or meeting it), part of it or not, become one mesh; every edge of that mesh (where its faces meet at an angle) becomes a curve - corner to corner, or a closed loop - with as few points as keep its shape (a straight edge two points, an arc three, a round rim a circle). Baking gives it a clean mesh of its own: each wall rows of quads, from each point of its bottom edge straight up to its top edge; flat faces filled from their edges (its edges kept exactly; a few thousand triangles whatever its size). Move a point of an edge - in any direction (X / Y / Z while dragging lock an axis) - and that edge of the mesh moves, the faces at it follow smoothly (every point of a face blended from the moves of the edges round it); a corner shared by several edges moves with all of them. Every edge shapes the mesh along its whole length - a wall's standing side edges too: put a point in one (double-click) and pull it, and the walls either side bend with it. While you drag, its faces follow smoothly - each wall and flat face straight between its edges, bent where a side edge bends, solved smooth across it. When you let go (or after any other edit of its curves) the solid **settles**: solved all the way, then wherever neighbouring quads bend sharply a **loop cut** runs beside that edge - every quad along the strip split in two, carried across the solid round to where it closes, so it stays quads - and that becomes its new start: the next edit bends from the shape you see, not from the bake. Undo puts the mesh back exactly. Its walls and its flat faces (tops, bottoms, a recess's ceiling) are rows and columns of quads - triangles only in the strips along curved rims. Its old curves and the solids baked in go. One undo step; saved with the model, it opens as it was.
- The recipe is saved inside the model (in the glb) and its curves beside it: opened again, it still follows them.

## mesh-save | Saving: overrides, variants, and Revert to original | keywords: Revert to original, override, variant, Add variant, Duplicate variant, Erase variant
- **Save** (**Ctrl+S**) never writes over the original model. In the game it saves an **override** beside it (in `art/overrides/`, laid out like the game) - the game uses your version from then on, at once (no restart, no import), and the original is kept as it was. In the [Mod Editor](doc:mod-editor) the mod's copy is the override (the game's file untouched). **Save as** (**Ctrl+Shift+S**) saves under another res:// path.
- An override has **variants** - versions of it, numbered 1, 2, 3... The **latest is always the active one**: the game uses it. The header's variants list shows **Original** and each variant (the active one marked); pick one to open it. Saving writes into the open variant (saving the original makes a new variant).
- **Add variant** - a new variant starting from the original (the latest, so active). **Duplicate variant** - the open variant, with your unsaved edits, copied as a new variant: duplicate an older one to make it active again. **Erase variant** - deletes the open variant (asks first); if it was the latest, the one before it becomes active, none left - the original.
- A character's material changes (its colour, metal, roughness, glow) go into the variant's own `model.json` too.
- **Revert to original** (the header button, lit when the model has an override) deletes every variant and opens the original again - the game draws the original again at once. The models list shows edited models in green.
- A Blender rebuild of a character writes the original: your variants stay on top of it.
- What's saved: every part, its materials, mirror modifiers applied - and a character's **skeleton, skin and animations**, kept as they were.
- The model's [curves](doc:mesh-curves) are saved beside it (`<model>.curves.json`, in the same variant) and come back when it's opened.
- Leaving Talos (or opening another model) with unsaved changes asks first: **Save**, **Discard** or **Stay**.

# anim-ch | The Animation Editor
The characters' clips on a timeline (**Animation** on the rail, **F7**): every character with a 3D model, each clip played, scrubbed and stepped, its bones posed in a 3D view and keyed on a dope sheet; new clips of your own; saved as files the game plays in place of the model's own.

## anim | The Animation Editor | keywords: Animation, Clips, Front view, Side view, Top view, Onion skin
The screen has four parts: on the left the **character** and its **clips**; in the middle the **3D view**; on the right the selected **bone**; along the bottom the **timeline** - the transport bar over the dope sheet.
- **Character** - every character with a model (the automaton, the pirate, Kilon Alios, each empire's android, the monsters). It's drawn as the game draws it: its parts merged, physically based, lit by a key light and a cool rim light.
- **Clips** - each with its length in frames (30 a second) and **loop** if it loops. A star (*) marks unsaved changes, **[own]** a clip of yours, **[file]** one of the model's clips replaced by a saved file. Click one to show it.
- **The view** - **right-drag** (or Alt+left-drag) orbits round the character, **middle-drag** (or Shift+right-drag) pans, the **wheel** zooms. **Front view**, **Side view** and **Top view** (Numpad 1, 3, 7) look straight at it. The ground grid has a line every 25 cm. The skeleton is drawn over the model, the selected bone lit.
- **Onion skin** (**O**) - ghost skeletons 2 and 4 frames before (blue) and after (amber), to see the motion's arcs.

## anim-time | Playing and the dope sheet | keywords: Previous frame, Next frame, Previous key, Next key, Loop playback, Dope sheet, Copy keys, Copy pose, Delete keys
- **Play** (**Space**) plays the clip at the chosen **speed**; **Loop** (**L**) plays it round and round, else it stops at the end. **Left / Right** step a frame, **Ctrl+Left / Ctrl+Right** jump to the key before / after (the selected bone's, or any bone's), **Home / End** the first and last frame.
- **The dope sheet** - the bones down the side, the frames along the top, a diamond for each key. Click or drag in the **ruler** to scrub. Click a bone's name to select it (its row lit). Click a **key** to select it, **Shift**+click to add or take away keys, and **drag** them along time; keys where they land are replaced. The wheel scrolls the bones.
- **Delete keys** (**Delete**) - the selected keys (none selected: the selected bone's key at this frame).
- **Copy keys** (**Ctrl+C**) copies the selected keys (none selected: the whole pose); **Copy pose** (**Ctrl+Shift+C**) every bone's pose at this frame; **Paste** (**Ctrl+V**) puts them at this frame - keys keep their spacing, a pose keys every bone. Paste works across clips and characters with the same bone names.

## anim-pose | Posing and keying | keywords: Key bone, Key all, Auto-key, Easing, Reset pose, Rest pose
- **Select a bone** by clicking it in the view (or its name in the dope sheet).
- **R** turns it with the mouse: move left and right; **X**, **Y** or **Z** turns it round that axis of the bone itself (no axis: round the line you look along). **G** moves it the same way (the pelvis: the body's height and sway). A **left click** or **Enter** keeps the pose, a **right click** or **Esc** takes it back.
- Or type it: **Rotation** in degrees (applied Y, then X, then Z) and **Position** in metres, both from the bone's parent.
- A pose isn't in the clip till it's **keyed**: the bone shows **(not keyed)**, and changing frame drops it. **Key bone** (**K**) keys the selected bone at this frame, **Key all** (**Shift+K**) every bone. **Auto-key** keys every pose as you give it. **Reset pose** (**Alt+R**) drops the unkeyed pose; **Rest pose** puts the bone as it rests.
- **Between keys** the bones move as the game moves them: turns slerped, positions straight. **Easing** sets how the selected bone moves through its keys in this clip: **Linear**, **Smooth** (cubic: eased through the keys) or **Step** (each key held).
- Every edit can be undone: **Undo** (**Ctrl+Z**) and **Redo** (**Ctrl+Shift+Z** or **Ctrl+Y**), one history per character.

## anim-clips | Clips and saving | keywords: New clip, Delete clip
- **New clip** - an empty clip of your own (the rest pose till you key it); **Duplicate** - a copy of the selected clip to change as your own.
- **Name** renames your own clips. The model's clips keep their names: the game plays them by name (and the characters' makers in Blender depend on them too).
- **Frames** sets the length (keys past the end are kept, unplayed); **Loop** makes it loop in the game (its last frame blending into its first).
- **Delete clip** deletes a clip of yours; on one of the model's clips with a saved file it goes back to the model's own (the file deleted when you save).
- **Save** (**Ctrl+S**) writes every changed clip, of every character, as `art/<character>_3d/clips/<clip>.tres` - into the game, or, in the [Mod Editor](doc:mod-editor), into your mod. The game puts each file in its model's clips in place of the clip of that name (the walker, the NPCs, the hangars' crews, the rifle's draw, holster and aim all play it), or adds it when it's new. A new clip plays in the game only where something plays it by name. The header says where saving goes; leaving Talos with unsaved clips asks first.

# fx-ch | The Effects Editor
The game's particle effects (**Effects** on the rail, **F4**): the explosions, the dust a landing kicks up, the sparks of a bolt striking and of the mining beam - each one data (`data/effects.json`), a list of emitters played as you change them, here and in the game at once.

## fx | The Effects Editor | keywords: Effects, particle, particles, emitter, Replay, Loop, Ground, Frame, preview scale
The screen has three parts: on the left the **effects**, in the middle a **3D view** playing the one picked, on the right its **parameters**.
- **Effects** - every effect of the game, with how many emitters it has; hover one for what it is and where the game uses it. **New effect** starts one of your own (a soft glow), **Duplicate** copies the picked one, **Delete effect** deletes it; **Name** renames it (Enter). The game plays its own effects by name - `explosion`, `dust_land`, `dust_jet`, `bolt_hit`, `bolt_hit_ground`, `mining_sparks` - so renaming or deleting one of those leaves the game asking for a name that isn't there (it plays nothing).
- **The view** plays the effect: a one-shot again and again (**Loop**, **L**), a looping one on and on. **Replay** (**Space**) starts it over. **Ground** (**G**) puts a ground under it (dust, a bolt striking a planet); off, it's in space. **Scale** plays it bigger or smaller, as the game does (an explosion is scaled to the ship that blew up) - only the view, not saved. **Frame** (**F**) zooms to fit it; drag to orbit round it, the wheel zooms.
- Every edit shows at once - in the view, and in a game under Talos (F8): every effect of that name in it changes.

## fx-emitters | Emitters and their parameters | keywords: Material, Mesh, Billboard, Amount, Lifetime, One-shot, Explosiveness, Delay, Shape, Direction, Spread, Velocity, Gravity, Damping, Radial accel, Scale, Angle, Spin, Emissive, Align to flight, Local space, Takes the tint, Duration, Light
An effect has a few values of its own - **About** (what it is), **Duration** (how long a spawned effect's looping emitters run) and an optional **flash of light** (its colour, **energy** - 0 for none -, **range**, and how long it takes to fade) - and a list of **emitters**, each one kind of particle. Click **>** by an emitter to open its parameters; the tick turns it **on** or off (to see the others alone); **Copy**, **Up**, **Down** and **Delete** duplicate it, move it in the list or take it out; **Add emitter** adds one.
- **Material** - what the particles are made of: **glow** (a soft light, added over the scene), **fire** (ragged flame burning away as it ages), **spark** (a streak along its flight), **ring** (a thin ring: a shockwave), **smoke** (soft billows lit by the scene's lights - dust too) or **debris** (solid lit pieces tumbling, glowing with heat). **Mesh** - a quad, a streak (sparks) or a shard (debris). **Billboard** - the quads face the camera.
- **Amount**, **Lifetime** (seconds; **Lifetime random** makes some shorter), **One-shot** (all at once, a burst - or off: emitting on and on), **Explosiveness** (1: all at the same moment, 0: spread over the lifetime), **Delay** (after the effect starts).
- **Shape** and **Shape size** - where particles start: a point, inside a sphere, on its surface, in a box, on a ring round the emitter's up. **Direction** and **Spread** (degrees round it; 180 every way). The emitter's up is the effect's: the game turns it - a landing's dust round the ground's up, a bolt's sparks back the way it came.
- **Velocity**, **Gravity**, **Damping** (slowing, m/s each second), **Radial accel** (pushed out from the centre), **Scale** (metres), **Angle** and **Spin** - each pair is the least and the most: every particle gets a value between.
- **Emissive** - how bright: the colours times this (over 1 glows past white). **Takes the tint** - the game colours some effects (a landing's dust the ground's colour, a bolt's sparks its gun's); off, the emitter keeps its own colours. **Align to flight** turns the particle along its velocity. **Local space** - the particles move with the effect; off, they stay where they were let go (the mining beam's sparks as the beam sweeps).

## fx-colours | Colour over life and scale over life | keywords: Colour over life, colour ramp, gradient, stop, Scale over life, curve
- **Colour over life** - the bar shows a particle's colour and opacity from its birth (left) to its end (right), over checks so the opacity shows. Each **stop** is a handle under the bar: click one to pick it (its colour, with opacity, in the picker beside it), drag it along; **double-click** the bar for a new stop there; **right-click** a handle to take it away (two stay at least). A fire's ramp goes white, yellow, orange, deep red, gone; smoke's fades in and out.
- **Scale over life** - a particle's size through its life (across: its age; up: times its **Scale**; the faint line is 1). Drag a point; **double-click** for a new one; **right-click** one to take it away. Empty, the size stays the same all its life (double-click to start a curve).

## fx-save | Undo and saving | keywords: Undo, Redo, Save, effects.json, mod
- **Undo** (**Ctrl+Z**) and **Redo** (**Ctrl+Shift+Z** or **Ctrl+Y**) take back and do again every edit - a slider's whole drag is one step.
- **Save** (**Ctrl+S**) writes every effect to `data/effects.json` - into the game, or, in the [Mod Editor](doc:mod-editor) (its **Effects** tab), into your mod (a mod can also change a few effects with a merge patch of the file). The header says where saving goes; leaving Talos with unsaved effects asks first.

## fx-live | Particles in the running game | keywords: Particles, Live Editor, Add here, Remove added, Effects here, Any effect
The [Live Editor](doc:live) (**F10** in a game) has a **Particles** tab for what you pick: **Effects here** lists the effects playing on it (or on its kind) - pick one and its parameters are there, as in the Effects Editor; **Any effect** edits any of the game's effects. An edit changes the effect itself: every explosion, every landing's dust in the game changes at once. **Replay** plays the one-shots on what's picked again.
- **Add here** attaches an effect to what's picked (at its origin) - a looping one keeps playing there. It's kept for **every thing of its kind** and put back each time one is made; **Remove added** takes them away.
- **Save** writes the effects (`data/effects.json`) and what you added - into the game, or into the mod picked at the top of the Live Editor.

# patcher-ch | Patch Notes
The game's patch notes: **Patch Notes** on the title screen (and in the Esc menu, over your paused game). It always opens on the newest version's infographic; **Back** (Esc) closes it.

## patcher | Reading a patch | keywords: Replay, Reload patches, Previous step, Next step, Code review, Infographic, diff
Every change to the game - code, art, data - gets a **patch** entry. The list on the left is a tree: each **version** with its patches under it (click the arrow to fold it), newest first, and any patches not in a version yet at the top (Up / Down to move between them all). A patch shows:
- **A summary** - one paragraph: what changed, and why it matters.
- **An infographic** - the change step by step, drawn as vector diagrams: each step's boxes, arrows, maps and charts appear in turn, with a caption underneath. **Next step** (Right or Space) and **Previous step** (Left) move through it, going round (Next on the last step shows the first, Previous on the first the last); **Replay** (R) plays the step's animation again.

**Code review** (the second tab, or Tab) - the change as code: the changed files - code first (scripts and tools), then the other text files, then the assets - each with how many lines were added and removed; pick one to read what changed in it and why, hunk by hunk, each with the diff itself (lines added in green, removed in red, unchanged ones grey for context). Assets are shown as what they are: pictures full size (with their size in pixels, on a checkerboard so transparency shows), sounds with a Play button, fonts as sample text, and text files without a diff as their contents; **All assets** (heading the assets in the list) shows every picture of the change together. **Explanation bubbles** sit beside the code, in the empty space to the right of it, each with an arrow to a line (outlined) and a few words on how that part of the code works; they fade in as you scroll to them. Text in the review can be selected and copied.

**Unpublished changes** - at the top of the list (marked ●) when running the game from its project folder (it appears a moment after Versions opens - finding the changes takes a scan of the project - without taking you away from what you're reading): everything changed since the last patch, not yet published - the change log and the changed files (new, modified, deleted). It's tracked in the project's `external/patcher/` folder (see `external/patcher/README.md`; `python3 tools/patch.py status` lists it too); when you're ready, ask Claude to publish it as a patch entry.

**Versions** - a version gathers patches into a release: it has its own one-paragraph summary and an infographic with a **page for each patch** - what that patch brought, at a glance. The counter says which patch a page is about; **Open this patch** (Enter) jumps to it, with its full steps and code review. A version has no code review of its own.

Patches are files in `data/patches/` (one JSON file each: an id, title, date, summary, the steps with their diagrams, and the code review), and so are versions (`version_<id>_<name>.json`: "kind": "version", the patch ids it holds, its summary and pages); **Reload patches** (Ctrl+R) reads them again. Esc exits Talos.

# mods-ch | Mods
Mods are your changes to the game - any of it: its data, scripts, scenes, shaders, models, pictures, sounds - kept apart from it and laid over it as it starts. Turn them on and off in **Mods** (title screen); make them in the **Mod Editor**.

## mods | Mods: turning them on, their order, sharing them | keywords: mod, mods, install, export, zip, load order, restart, safe mode
**Mods** on the title screen lists every mod you have. Tick one to turn it on; the turned-on mods load **in order** (the arrows move one earlier or later) - where two change the same file, the later one wins, and the list says when that happens. Mods load as the game starts, so a change shows **Restart to apply**.
- **Install** takes a mod shared as a zip; **Export** saves one as a zip to share; **Folder** opens the mods' folder; **Delete** removes one.
- A mod with **a script of its own** can do anything a game script can - install mods only from people you trust.
- **Safe start.** If a start with mods never reaches the title screen (a broken mod), the next start runs without them and says so; turn them back on once it's fixed. Starting the game with `--no-mods` skips them too.

## mod-files | What a mod is | keywords: mod.json, files, merge, override, main script
A mod is a folder in the mods' folder: **mod.json** (its name, version, author, description and its own script, "main") and **files/**, laid out like the game - `files/data/galaxy.json` is the game's `data/galaxy.json`.
- **A file the game has** is replaced by the mod's.
- **A new file** is added to the game (a new script, scene, picture...).
- **A merge patch** - `<file>.json.merge` next to where the game's JSON file is - changes only what's in it: objects merge key by key (deeply), anything else replaces. Two mods can patch the same data file this way.
- **Its own script** (mod.json "main", e.g. `res://mods/<id>/main.gd`) runs once the game's up: a Node added to the root, after the game's own singletons - connect to their signals, change their data, change scenes as they're made.

## mod-editor | The Mod Editor | keywords: mod editor, override, merge patch, new file, check, test in game, standalone
The **Mod Editor** (Mods > Mod Editor, or straight in: start the game with `-- --mod-editor`) makes mods. Pick a mod at the top, or **New mod**; **Properties** sets its name, version, author, description and its own script.
- **Files** - the game's files on the left (**Find a file...** narrows them): **Override** (Enter) copies one into the mod to change it; **Merge patch** starts a patch for a JSON data file. The mod's files in the middle (gold: replacing the game's; green: new; pale: merged) and the open one on the right: text, data, scripts, scenes and shaders in a code editor with their colours (**Save**, Ctrl+S - JSON and scripts checked as you save); pictures shown, models opened in the mesh editor, sounds played - each can be **Replace**d from a file of yours. **New file** adds one to the game; **Main script** makes (or opens) the mod's own script; **Remove** drops a file from the mod.
- **Meshes**, **Animation** and **Effects** - Talos's mesh, animation and effects editors, saving into the mod.
- **Check** - every file: JSON that parses, scripts that compile, scenes that load, merge patches with a file to merge into.
- **Test in game** (F5) - turns the mod on and restarts the game with it.
- **Export** - the mod as a zip to share.

# live-ch | The Live Editor
Everything edited while the game runs: in a game, **F10** opens the Live Editor - a panel down the right of the screen over the running game. Click anything in the world to pick it.

## live | Picking and editing in the running game | keywords: live editor, F10, its parts, edits apply to
**F10** (Settings > Controls to rebind) opens it; F10 or Esc closes it. The game goes on underneath - **Pause** stops its time (the editor still works) and the speed list runs it slower or faster.
- **Pick** anything with a click in the world: a character, a building, a ship, a rock, the ground. Its box is drawn round it. **Up** picks what it's part of; **its parts** lists what it's made of.
- **Its kind.** Under its name the panel says what an edit applies to - "every Cosmos Ship", "every town: minoan port 4182". Edits go on that one at once and on every other of its kind in the world a moment later, and are **kept**: put back each time such a thing is made.
- **Save** keeps the edits for good - into the game itself, or into one of your mods (the list under the top buttons). Unsaved, they last until the game closes; closing the panel asks.
- The tabs show what can be edited on what's picked: [Object](doc:live-object), [Model](doc:live-model), [Materials](doc:live-materials), [Animation](doc:live-anim), [Particles](doc:fx-live) and [Collision](doc:live-collision).

## live-object | Object | keywords: See-through, its values, Forget its edits
Its place, turn and size (a part's are kept for its kind; the whole thing's own place and turn are just where this one is - live, not kept), shown or not, its shadow, how see-through it is - and **its values**: its script's own numbers, ticks, colours and vectors (speeds, sizes, its hull and shields...), all live, refreshed as the game changes them. **Forget its edits** drops what's kept for its kind.

## live-model | Model | keywords: Put in the world, As made
Its meshes, each with its vertex and surface counts. **Mesh editor** opens a copy of one in the mesh editor in a window over the game (every tool of [The Mesh Editor](doc:mesh)); **Put in the world** puts it on this one and every one of its kind. **Replace** takes a model file of yours (.glb, .gltf, .obj); **As made** puts back the mesh it was made with. Saved, a new mesh is kept as a file in `art/live/` (of the game, or the mod).

## live-materials | Materials | keywords: Its own copy, this thing's own values
Each surface's material: a shader's every parameter (sliders where the shader gives a range, colours, vectors, ticks, textures) or a standard material's colour, metal, roughness, glow and textures - and the thing's own per-instance values. Edits change the material itself, so everything that shares it changes too; **Its own copy** first gives this kind its own. A texture's **Replace** takes a picture of yours (PNG, JPG, WebP), kept in `art/live/tex/` when saved.

## live-anim | Animation | keywords: clips of a character
The clips of a character: which one's playing and where; double-click one (or **Play**) to play it on this one now; its **Speed**. **Animation editor** opens [The Animation Editor](doc:anim) in a window over the game on this character and its clip: saved there, the clip changes on every character of that model at once.

## live-collision | Collision | keywords: collision, solid, solids, walls, boxes, push, camera, Show through walls
The Live Editor's **Collision** tab edits what's solid in the place you picked - a town's buildings, a structure of yours, a station's parts, a port's walls and furniture, a ship's furniture, a dungeon's walls. Nothing in the game is a physics body: these boxes are what you walk into and stand on, and what stops the camera.
- **The lines.** Its boxes are drawn in the world within 60 m of the camera: blue solid, green the feet only (furniture), violet the camera only, grey turned off, amber the selected one. **Show through walls** draws them over everything.
- **Picking.** Click a box in the world, or one in the list (the boxes near the camera, nearest first).
- **The selected box.** **Solid** (off: kept and drawn, but nothing meets it), its **Centre** and **Size** in metres (in the place's own frame, y up) and its **Turn** in degrees - about the vertical in towns and structures, any way on a station; a dungeon's and a port's boxes stay square to it. A port's box also says what it **Stops**: the camera, your feet or both (for the feet only its footprint counts). A sloped roof or a many-sided block can be turned off, copied or deleted, not moved.
- **Add** puts a box round what's picked (when it's small - a crate, a statue) or in front of the camera; **Copy** copies the selected box a metre over; **Delete** removes it.
- Changes count at once: walk into the moved box. **Revert** puts the place back as it's built and forgets its collision edits.
- **Kept for that place.** The edit is kept as what changed (moved, added, deleted) against the place as the game builds it, and put back each time it's built again - a town by its seed, each station on its own, a port by its station and platform, a ship's insides by its hull. **Save** (Ctrl+S) writes it into the game or the mod picked at the top.

# dev-ch | Developer tools
Looking inside the running game, and changing it while it runs.

## dev-menu | The developer menu and the Inspector | keywords: Alt, inspector, inspect, developer, pause, game speed, hot reload, screenshot
In a development run of the game (from the project folder - not an exported game), **Alt + right-click** opens the **developer menu**:
- **Inspect** (the thing under the cursor) - the nearest ship, creature, station or other object of the world there, and **Inspect UI** for the panel or button under the mouse - opens it in the Inspector.
- **Inspector** - a window inside the game's, along its right edge (drag its title bar to move it, an edge to resize it - an edge brought near the game window's **snaps** flush to it, and stays docked there if the game window changes size; it opens again where you left it; × closes it): the **node tree** of the whole game at the top (type in **Filter nodes...** to find one by name or script; ⟳ Tree rebuilds it), and the selected object's **properties** below - its script's variables first, and with **Built-in** ticked the engine's own (position, scale, modulate...). The values update several times a second as the game runs. Arrays, dictionaries and objects open with their arrow; **double-click** an object to inspect it (**Back** returns to the one before). **Double-click** a number, text, true/false, vector or colour to change it - Enter sets it on the live object. A field that isn't at its **default** (the value its script declares, or the engine's own default) shows a **reset button** (↺) beside its value: click it to put the default back. **Reset all** does it for every field of the object. (A value the game works out as it runs - not written in the script - has no default to go back to, and no button.)
- **Pause**, **Game speed** (×0.25 to ×4) and **Screenshot** (saved in the game's user folder).
- **Hot reload** - while ticked, saving a script, shader or picture of the project reloads it in the running game: every object keeps its values and runs the new code from its next frame (variables the new code adds get their declared values). Code that doesn't compile is reported and the old code keeps running. **Buildings** too: change a tile picture (data/sprites/tile_*.png), a Minoan tile sheet in external/images (it's cut into its pieces again by itself) or the building styles (scripts/minoan_tiles.gd - add pieces to a style) and every building on the planet - and the Library's Buildings room - takes the new look at once: same shape, doors and rooms, its walls, floors, roofs, columns and decor redone. (Code that runs once - when an object is created - doesn't run again: re-create the object to see it.)

## live-coding | Live coding with Claude | keywords: live, --live, LiveLink, debugger, breakpoint, step, remote debug, tools/live.py
Started with `-- --live`, the game also opens a door for **tools/live.py** (on this computer only - port 6070): Claude, or you, can read the game's state (`live.py state`), evaluate expressions (`live.py eval 'ship.hull'`), set values, run whole snippets of GDScript inside the game, hot reload files, take screenshots and follow the log of prints, errors and reloads (`live.py log --follow`) - so a change can be made, tried and tuned while you play, without restarting.
**The debugger** - start `python3 tools/live.py debugger` first and the game with `--remote-debug tcp://127.0.0.1:6007`: then breakpoints (`live.py dbg break scripts/hydra_beast.gd 177`), stopping the game, stepping a line at a time (`step`, `next`, `out`, `continue`), the call stack and every variable of a frame (`dbg stack`, `dbg vars`), evaluating expressions where the game stopped, and every error with its call stack (`dbg events`). Script errors don't stop the game unless asked (`dbg errors on`). `python3 tools/live.py help` lists it all.
