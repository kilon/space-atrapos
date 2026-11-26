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

# mesh-ch | The ECurves editor
The game's 3D models and your own as **ECurve objects** (**ECurves** on the rail, **F6**). An ECurve object is made of one or more **solids**; each solid of **faces** (the areas of its surface), **edges** (the curves bounding them) and **vertices** (the points along the edges). Reshape an edge - drag its vertices - and the faces beside it follow; every solid stays fully editable. Its materials, its variants, its bones; saved as glb into the game or, in the [Mod Editor](doc:mod-editor), into your mod.

## mesh | The ECurves editor | keywords: Find a model, New model, Import from disk, ECurve object, Primitives, Variants
On the left the **models** (find one by typing in **Find a model...**), the **Primitives** and the **Material library**, and under them the **variants** of the picked model; in the middle the **toolbar** over the **3D view**; on the right one panel showing only what's about the selection (the overview of the object's collections and solids, the selected solid, its recipe, its edges, sketching, its material...).
- **Every model is an ECurve object.** Opening one that isn't yet - an imported file, an older model, a character dragged in from the Models list - makes it one in the background, several solids at once, the bar at the foot of the left panel showing how far it's got. A part made of separate pieces (a character's body) is split into solids first: the pieces of one material that move with one bone become one solid, named after that bone and material ("Forearm L Armor"; a character's biggest piece keeps the name **Body**, the one the game looks for). Each solid's edges are traced where its faces meet at 45 degrees or more, each a lean curve; a smooth piece with none (an eye, a ball) gets a seam round its middle. Its surface stays exactly what it was, the edges laid along its own points.
- **Every conversion is checked.** Each solid is looked over against what it was made from before it's put in: its surface where the old one was, nothing turned inside out, no thin slivers or doubled triangles (they flicker), no new holes, its shading true to its faces. One that falls short is made again just as it was, triangle for triangle - a converted model never looks worse than the original.
- **Converted once.** When all its solids are made, the object is stored as an ECurve object (a new variant of the model: its meshes, their weights moved onto them, its edges) - dragged in or opened again it's an ECurve object at once, no conversion. The game draws and animates the stored variant like any model.
- **The overview** lists the collections (a crate), the ECurve solids (an amber triangle), plain meshes (a green one) and edges (a gold curve) - each solid folded: open one to see its edges. **Double-click** a row to rename it. Beside each row's eye, its **arrow**: off, the solid - or everything in the collection - can't be picked or let go (nor its faces, edges, vertices); clicks go through it. Click a **collection's** row - or click a picked solid again in the view - to pick the whole collection: drag any of its solids to move it as one (G / R / S too); click again for a face.
- **Models** - the game's characters (art/*_3d/, gold) first, then every .glb, .gltf, .obj and mesh resource of the game and of your mod. **Double-click** one to open it, or **drag it into the view**: it's added to the open object where it's dropped, in a collection of its own.
- **Variants** (under the models): click a model and its variants show below - its original and each saved variant (the latest is the one the game uses); double-click one to open it.
- **Primitives** - the primitive solids of ECurve objects: **box**, **cylinder**, **prism**, **cone**, **sphere**, **torus**. Double-click one to add it, or drag it into the view (it stands where it's dropped).
- **Collections** - the object's solids grouped as in Blender, in the **overview** (the right panel): a collection holds solids (and is hidden or shown with its eye); right-click for **New collection** from the selected, **Move to**, **Ungroup**, **Duplicate**, **Delete**; double-click a name to rename it.
- **No mesh editing**: ECurve objects are edited by their solids, faces, edges and vertices - there's no edit mode of loose triangles.
- **Levels of detail**: every solid's mesh gets coarser copies the renderer switches to as it gets small on screen (and the game's imported models have theirs made when they're imported) - far away, a solid costs a fraction.
- **Preview in game** (the toolbar): the model as it is - unsaved edits too - set down in front of you in the game, Talos hidden and the game running: walk or fly round it. **F8** or **Esc**: back to the editor as you left it. Only a look: nothing is added to the game.
- **New model** (**Ctrl+N**) starts an empty one; **Import from disk** (**Ctrl+O**) opens a .glb, .gltf or .obj from anywhere on your computer - **Save as** then puts it into the game or your mod.

## mesh-view | The view | keywords: Perspective / orthographic, Frame selected
The view is lit like a photo studio - a warm key light with shadows, a cool fill, a rim, a soft sky for reflections - so metal, paint and glow look as they will in the game (in the game, the characters are drawn by its own merged, physically based look).
- **Middle-drag** (or **Alt+left-drag**) orbits, **Shift+middle-drag** pans, the **wheel** zooms.
- **Front**, **Side**, **Top** (**Numpad 1 / 3 / 7**; with **Ctrl** the opposite side), **Ortho** (**Numpad 5**) a flat view without perspective, **Frame** (**F** or **Numpad .**) centres on the selection, **Home** on the whole model.
- The floor grid has a line every 50 cm, the **X** axis red, **Z** blue, **Y** (up) green; the corner shows which way they point.

## mesh-object | Solids | keywords: Delete solid, Duplicate solid
- **Click** a part in the view (or in the list) to select it.
- **G** moves it, **R** rotates it, **S** scales it - with the mouse; **X**, **Y** or **Z** locks the change to that axis (again: free). A **left click** or **Enter** keeps it, a **right click** or **Esc** takes it back.
- Or type it: **Position**, **Rotation** (degrees) and **Scale** on the right.
- **Add a part**: a **box**, **cylinder**, **cone**, **sphere**, **plane** or **torus**, a metre across, at the model's origin (**Shift+A**: a box). **Duplicate** (**Shift+D**) copies the selected part, **Delete part** (**X** / **Delete**) removes it, the name field **renames** it (Enter).
- Every change can be undone: **Undo** (**Ctrl+Z**), **Redo** (**Ctrl+Y** or **Ctrl+Shift+Z**).

## mesh-bind | Solids on a character's skeleton: bones | keywords: Auto-bind to the skeleton, Bind to bone, Bone to bind to, Unbind
- **An ECurve solid's bones**: Auto-bind or Bind to bone on an ECurve solid associates it with the bones (kept with its recipe): its edits stay free, and as the object's saved it's bound to them - its nearest bones, or that one - so it moves with the animations in the game. A solid made from a skinned mesh keeps that mesh's weights: each new vertex takes those of the old one nearest it.
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

## mesh-move | Dragging the selection: smart axis and perspective moves | keywords: Smart axis move, Perspective move
A press on what's selected and a drag moves it - two ways, a button each on the toolbar:
- **Smart axis move** - along the one of the selection's own axes the drag goes most: along its surface (X, red), across it (Y, green) or out along its normal (Z, blue); a part moves along its own axes.
- **Perspective move** - freely over the plane you're looking at most squarely: the ground from above or below, the upright plane facing you from the front or the side. While the drag runs along one of that plane's axes on screen it snaps to it (the axis drawn); off it, it's free again.
Either way it's a move like G: proportional editing, symmetry and undo apply; let go to keep it, right-click to cancel.

## mesh-refs | Reference images | keywords: Add reference image, Remove reference image, Show / hide reference image, Reference images
**Reference images** (the REFERENCE IMAGES panel on the right) are pictures from anywhere on this computer (png, jpg, webp) shown in the view to model from - drawings of a ship from the front and the side, say. **Add reference image** picks the file; the list shows the model's images - pick one to change it:
- **View**: Front, Side or Top - upright in that view, centred on the model's origin, shown while you look along that view (it fades as you turn away) - or a **Free plane**, placed (Offset X / Y / Z) and turned (Turn, Tilt) anywhere in the scene.
- **Layer**: **Behind the model** (the model, the floor grid and the edit overlays drawn over it) or **Over the model** (drawn over it, see-through by its opacity; the points and wireframe still on top).
- **Opacity**, **Size** (its height in metres; the width follows the picture) and **Offset X / Y** (a view's picture moved across and up in that view).
- **Show / hide** keeps it but hides it; **Remove** takes it away (the picture file isn't touched).
They're kept with the model (by its path, in your user data) and come back when it's opened again. The pictures are read in the background.

## mesh-mirror | Mirror and symmetry | keywords: Mirror across, Clip at the seam, Merge distance, Apply the mirror, Symmetry X, Symmetry Y, Symmetry Z, Symmetrize
Make one half of a model and get both:
- **The mirror modifier** - tick **X**, **Y** or **Z** under **Mirror modifier**: the part shows a mirrored copy across its own axis, live while you edit it. **Clip** keeps points from crossing the mirror's plane (those on it stay on it); **Merge** is how close to the plane points are joined with their twins. The modifier stays a modifier while you work (the part's list entry says **(mirror)**) and is **applied** into the mesh when you save - the saved file has both halves, seamless. **Apply** makes it part of the mesh now.
- **Symmetry X / Y / Z** (toolbar) - edits mirror across that axis: move a point and its twin on the other side moves the mirrored way.
- **Symmetrize** - copies the +X side onto the -X side (**Shift+click**: -X onto +X; the axis is the first symmetry axis turned on). Each point is paired with its nearest twin, so the two sides must already roughly match.

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

## mesh-boolean | Booleans | keywords: Union, Difference (A minus B), Intersection, Slice, Keep the cutter
Two parts made one, cut or trimmed - as solids:
- Select two parts: click one, then **Ctrl+click** (or **Shift+click**) the other - in the view or in the parts list. **A** is the one selected first, **B** the other (both outlined; the panel says which is which). Or select A and **right-click** B: the menu's **Boolean** group works on the two.
- **Union** - A and B made one part. **Subtract** - A with B cut out of it. **Intersect** - only what both share. **Slice** - A cut in two by B: the piece inside B becomes a part of its own, the rest stays A.
- The result replaces A; B is removed - or, with **Keep B (hidden)**, hidden (the eye in the parts list shows it again). Each surface keeps its material; the faces B cuts into A take B's. One **Undo** takes it all back.
- It's worked out in the background (two parts of 2,000 triangles each take a few hundredths of a second). Both parts must be **closed** solids: a plane, or a mesh with a hole in its skin, is refused, and the note says why. A part skinned to a skeleton can't take part (its weights would be lost).

## mesh-curves | ECurves | keywords: ECurves, Line, Spline, Circle, Arc, Rectangle, Polygon
The side panel's ECurves sections (and the right-click menu's ECurves page): model hard surfaces the quick way - **draw an outline, then pull it into a solid**. Edges are drawn on a **construction plane**, snapped to its grid and to vertices; picked and reshaped by dragging their vertices; then [extruded, revolved, lofted, swept or piped](doc:mesh-curves-solids) into new parts. A model's edges are kept with it (saved beside it as `<model>.curves.json`, in its variant) and shown over the view in blue (picked: amber, their vertices as white squares).
- **Turning the view** turns it round what's selected - the smallest thing first: the mesh vertices picked in edit mode, else the edge vertex you last pressed, else the picked edges' middle, else the selected solids' middle.
- **One side panel, only what's about the selection:** the mesh's and ECurves's sections are one page (no tabs), each shown only when it's about what's picked - nothing picked: the overview, the sketch settings and the reference images; a part: its place, solid recipe, shape, mirror and material (two parts: the booleans); edges, vertices, a face or a whole baked solid: ECurves's (the merge distance with two edges or a solid, the face resolution with a face); edit mode: the mesh's editing.
- **Tools live in the right-click menu:** every tool the menu has is used from there (the toolbar, the panels and the header keep only what it hasn't: the panel buttons, Preview, Wireframe, the falloff, the file and the variants). Each tool has its own icon. The menu **unrolls** from where you clicked and rolls up again as a tool starts or you click away.
- **Wireframe** (the toolbar's Wireframe button, **Shift+W**): the parts' edges drawn over them in object mode - every quad as a quad (its two triangles' shared edge left out), edges behind a surface hidden - to see a stretched or folded face at a glance.
- **Edge primitives** (the right-click menu's ECurves page, nothing picked): **Add edge box**, **cylinder**, **prism**, **cone**, **sphere**, **torus** - each an edge and the solid made from it, on the ground at the middle (a square, circle or hexagon extruded 1 m; a line, half circle or circle turned round the Y axis): reshape the edge and the solid follows; bake it to shape it by its edges.
- **Sketch tools** (keys work in object mode): **Line** (**L**) - click vertices, a polyline; **Spline** (**P**) - a smooth edge through the vertices you click; **Circle** (**C**) - its centre, then the rim; **Arc** (**Shift+C**) - its start, its end, then a vertex it passes through; **Rectangle** (**Shift+R**) - two opposite corners (**Alt** held: from the centre); **Polygon** (**Shift+P**) - the centre, then a corner (the wheel or **+ / -**: how many sides).
- A line or spline: **click its first vertex** to close it into a loop; **Enter**, **right-click** or a double click ends it open; **Backspace** takes back the last vertex. The tool stays on for the next edge; **Esc** stops it (with vertices placed: drops them first).
- **Typed sizes**: while drawing, type a number and **Enter** - a line's next segment that long (the way the mouse vertices), a circle's or polygon's radius, a rectangle's "width height". The distance from the last vertex shows beside the cursor.
- **Undo** (**Ctrl+Z**) takes back each edge and each change to one.

## mesh-curves-overview | The overview: collections | keywords: Overview, Collection, New collection from the selected, Ungroup, Move to collection
Near the top of the side panel, the **OVERVIEW** lists the whole model as a tree: first the **parts** - each a group of solids (with theirs under it) - then **Solids** in no part (each with the edges it's made from under it - a cut edge marked "(cut)"), **Meshes** (plain parts) and **Edges** no solid uses yet.
- **Parts (groups of solids):** select some solids, right-click one: **New part from the selected** - they're grouped into a part (saved in the glb, a part of the model: the Mesh tab's list shows it too, with its solids under it). Move the part and its solids move together - their edges with them. A new solid made while a solid of a part is selected joins that part. Right-click a part: Select its solids, Hide / Show, Duplicate, **Ungroup**, Delete (with its solids); a solid: **Move to part ›** (or out of it).
- The Mesh tab's **parts list** is the same kind of overview: parts with their solids and meshes under them; click a part to select all of it, right-click a row for its menu (Hide / Show, Duplicate, Delete, New part from the selected, Move to ›, Ungroup...), double-click to rename.
- **Dragging an edge's vertex:** it moves on the edge's plane; **X / Y / Z** while dragging lock it to that axis (again: free) - lift it, lower it.
- **Rename:** right-click a part, solid or edge - **Rename** - or select it and press **F2** (or double-click its row); type the name, Enter.
- **Move, turn, scale a part as one:** in object mode, **G / R / S** (and the gizmo) move every selected solid together, round their middle; when all of a part's solids are selected (click the part's row), the part itself moves - its solids stay in it. One undo step.
- **Click** a solid or an edge to select it; **Ctrl / Shift+click** for more - solids and edges together. It's the same selection the view and the boxes below use: pick two solids to join them, a solid's edges to drag or reshape them, an edge to see its CURVE box...
- Under each solid: its own edges, and each **tool step** ("Cut: an extrusion"...) as a row of its own with that step's edges under it - click a step to select its solid and pick its edges.
- **Right-click** a row for its menu:
  - a **solid**: Hide / Show, Duplicate, Delete, Pick its edges, Make plain mesh, Detach its last tool, **Attach to ›** another solid (cut from / join to / common with it - live);
  - a **tool step**: Role (Cut / Join / Common), Hide / Show its ghost, **Detach** (a solid of its own again), **Attach to ›** another solid (moved there), Delete step (its edges stay);
  - a **edge**: Hide / Show, Pick, Duplicate, Delete, **Detach from** its solid (taken out of its step; a tool step with no other edge goes with it), **Attach to ›** a solid (a new cut / join / common step).
- **Double-click** a name to rename it. The **eye** hides or shows it, everything it shows in the view: a solid and its ghosts; an edge, and the ghost of a tool made only of hidden edges; a tool step's ghost. (Hidden is only for seeing: the solid's shape doesn't change. One **Undo** step.)

## mesh-curves-plane | The construction plane and snapping | keywords: Auto plane, Ground plane, Front plane, Side plane, View plane, Selection's plane, Snap to the grid, Grid step, Snap to vertices, Guides
- The plane is picked in the **Plane** dropdown under the sketch tools. **Auto** (the default): the plane is the **surface under your first click** - click on a part's face and the edge is drawn flat on it - or, in empty space, the ground. **Ground** (X and Z), **Front** (X and Y), **Side** (Z and Y), **View** (square to the view) or **Selection** (through the selected faces in edit mode, or the picked edge) fix it. While a tool is on, the plane shows as a faint grid round the cursor.
- **Grid** snaps vertices to the plane's grid (**Grid step**, 0.05 m at first); **Vertices** snaps them to the edges' vertices, ends, middles of sides and centres, and to the parts' corners - the ring at the cursor is coloured by what it caught. Hold **Ctrl** for no snapping.

## mesh-curves-edit | Editing edges | keywords: Move edges, Turn edges, Scale edges, Simplify edge, Delete edges, Duplicate edges, Mirror edges, Radial array, Insert vertex, Dissolve vertex, Smooth vertex, Sharp vertex, Manual vertex, Symmetry, Mirror solid, Knife, Offset edge, Fillet corners, Join edges, Bridge edge, Reverse edge, Close / open, Union edges, Subtract edges, Intersect edges
- **Click an edge** in the view to pick it (**Shift+click**: more, or one off again); a click in empty space lets them go. Drag a picked edge's **vertex** to move it, or the **edge itself** to move it whole - smoothly, from where you pressed: after a few pixels the drag picks the axis (X, Y or Z) that runs closest to your drag on screen, drawn through it in its colour (X red, Y green, Z blue) with how far it's gone; **X / Y / Z** while dragging switch to that axis (the same again: free on the axis plane facing you); **Shift** as you start (or Perspective move in the menu): free on that plane; **Ctrl**: whole grid steps. **Guides** (on by default - the Guides box by Vertices; **Alt** while dragging: off): when a dragged vertex's X, Y or Z comes within a few pixels of another vertex's (its own edge's first) or of a flat face's level, it snaps there and a dashed guide in that axis's colour shows to what ("Y same as a vertex on this edge", "Y level with a flat face"). **Double-click an edge** to put a vertex into it where you clicked (a circle, an arc or a bezier becomes a path of vertices first - the same shape). **Double-click a vertex** to dissolve it - the edge runs on between its neighbours (an arc's middle vertex: a straight line; an edge keeps at least two vertices, a closed one three; a baked solid's edge keeps its ends). The solids hide the edges behind them: only what you'd see of an edge is drawn, and picked. **Right-click a vertex** (or anywhere, with vertices picked - all of them at once) for **Smooth vertex** (the edge bends smoothly through it), **Sharp vertex** (a corner: straight sides either side of it) or **Manual vertex** - the edge becomes a path of vertices, each smooth, sharp or manual.
- **Manual vertex**: the edge's bend into the vertex is yours to shape. Press the part of the edge beside it (it glows green as the mouse comes over it) and drag: that side of the edge bends towards where you drag, its handle drawn from the vertex. Each side is shaped on its own, and so is each edge meeting at the vertex - press the one you mean.
- **Symmetry X / Y / Z** (the right-click menu): dragging a vertex moves its twin across the model too - the vertex where its mirror image is; a vertex on the mirror's plane stays on it. **Mirror solid across X / Y / Z**: a copy of the picked solid on the other side, with edges of its own - a left arm's copy is a right arm, its name and bone too.
- **Knife** (K, or the right-click menu): click points across a solid's surface - the cut follows the surface between them (across a gap between a solid's pieces, the part facing you is sliced) - then **Enter** or right-click to cut, **Backspace** to take a point back, **Esc** to stop. Each cut is a new edge of the solid: it splits the faces it crosses and shapes the solid like any of its edges.
- **T-pose** and **Weapons** work on ECurve objects too: each converted solid moves with its bone, so the T-pose turns it whole with that bone (saved in the character's own pose); a weapon's solids hide whole, and are still saved.
- **In 3D:** with edges picked, **Move edges** (**G**) moves them over the plane facing you - up, down, anywhere; **Turn edges** (**R**) turns them about their middle (round the line of sight); **Scale edges** (**S**) scales them about their middle. **X / Y / Z** while doing it: along (or about) that axis - again: free. Moves snap to the grid and turns to 15° (**Ctrl**: free); type a number for an exact distance, angle or factor. Click or **Enter** keeps it, **Esc** or right-click cancels. A edge's plane turns with it, and the solids made from it follow. (With edges picked, G / R / S work on them rather than the part.)
- **Delete edges** (**X / Delete**), **Duplicate edges** (**Shift+D**), **Mirror edges** (a copy across the model's X), **Radial array** (six round the Y axis).
- **Offset edge** - a copy moved out (or in) by a distance in its plane: corners stay mitred, a circle's radius grows. The mouse sets it, or type it and **Enter**.
- **Fillet corners** - the corners of lines, rectangles and polygons rounded (the mouse or a typed radius; 0: sharp again). The radius stays with the edge: its vertices still drag, the rounding follows.
- **Union edges**, **Subtract edges**, **Intersect edges** - booleans of closed edges, worked out on the **first picked** edge's plane: pick two or more, and they're replaced by the result (one **Undo** step). Edges on other planes are brought onto it along its normal: on a parallel plane (lifted or lowered) they land as they are (a lifted circle cuts the same circle); at an angle they're projected - as seen square-on from the first one (a tilted circle cuts an ellipse); one standing edge-on to it is left out. The note says which were brought down, projected or left out. Union makes one outline (a gap they enclose becomes a hole); Subtract takes the others from the **first picked** - edges inside it become its holes; Intersect keeps what they all share. Extrude or fill the results together: a solid with its holes, still following its edges. The results are lean: an edge that comes through whole stays as it was (a circle hole is still a circle), the rest become **paths** - corners and straight sides kept as they are; a bend that's part of a circle drawn as that exact arc through its ends and one middle vertex; other bends get smooth vertices spread evenly along them. A circle minus another overlapping it is four vertices.
- **Simplify edge** - the picked closed edges with more vertices than they need (a dense outline) made lean the same way; solids made from them follow.
- **Merge edges** (**Ctrl+J**) - the picked edges (or a whole picked solid's edges) joined wherever their ends meet: a vertex they share, or ends within the **Merge distance** (the panel, under the edges' line; 0.001 m to start). Where several ends meet, the two running on straightest through the vertex are made one (a corner there - neither changes shape); again till no ends meet; an edge whose own ends meet is closed. A baked solid's edges are joined the same way, its mesh as it is. One Undo.
- **Join edges** - two open edges made one at their nearest ends. **Bridge edge** - a smooth edge between the nearest ends of two picked edges, leaving each along its own direction (its two handles drag). **Reverse edge** - runs the other way. **Close / open** - a line or spline made a loop, or opened.

## mesh-curves-points | Picking vertices: separate, merge, extrude... | keywords: Separate vertices, Merge vertices, Extrude vertices, Subdivide vertices, Connect vertices, Delete vertices, picked vertices
- **Click a picked edge's vertex** to pick it - it turns orange, bigger, ringed; **Shift+click** more vertices (on any picked edge - Shift+click an edge to pick it too), or one off again. Dragging a picked vertex drags **all the picked vertices** together; **G / R / S** move, turn or scale the picked vertices about their middle (X / Y / Z: an axis). A baked solid's edges joined to them follow at the corners they share. Clicking an edge or empty space lets them go.
- **A click picks, a drag moves:** what's picked changes only on a click (let go where you pressed); a press that moves drags instead - on a vertex, the picked vertices; on a baked solid's edge, that edge's vertices; on a baked solid's face, the picked face or solid there (a face of nothing picked: its face, picked as the drag starts) - smart axis or free, as for vertices; the faces beside follow and it settles when you let go (one Undo).
- **Click again to pick bigger:** a click on a vertex picks only that vertex (its edge and any face let go); a click on it again picks its **edge**; again, a **face** that edge bounds (the face under the click if it's one of them); again, the **whole solid** - the solid alone, shaded: its edges and their vertices aren't picked or even shown (**G / R / S** move, turn or scale all of it). A face's face clicked again picks the whole solid too; with the solid picked, a click on its face picks that face again (its edges back). Choosing a baked solid any other way - clicking it in object mode, its row in the parts list or the overview - picks it the same way, the solid alone. A edge clicked again picks a face beside it; an edge of a picked face clicked: just that edge. A drag instead of a click moves what's under it, the pick as it was.
- **Separate vertices** (**Y**) - the picked vertices become an edge of their own: a run of picked vertices one edge, the rest of the edge the edges either side (one vertex picked: the edge split there). Nothing moves. On a **baked solid** its edge is split the same way and its mesh stays as it is - **each piece still shapes it**.
- **Merge vertices** (**M**) - two edge **ends** picked (one on each of two edges): the two edges become one, running on through where they met (a corner there, so neither changes shape); both ends of one edge: it's **closed**. A baked solid's two edges are joined the same way, its mesh as it is. Other vertices picked: they're moved together to their middle (welded).
- **Extrude vertices** (**E** with vertices picked) - each picked vertex pulled out into a new one that follows the mouse (**X / Y / Z**: along an axis; a click keeps it, a right-click takes it back): an open edge's end grows on from it; from any other vertex (or a baked solid's edge) a new line starts.
- **Subdivide vertices** - a new vertex on the edge between each two picked vertices next to each other (the shape kept). **Connect vertices** (**F**) - a straight line between the two picked vertices. **Delete vertices** (**X / Delete** with vertices picked) - taken out, each edge running on between its neighbours.

## mesh-curves-patches | Faces: a baked solid's faces, their resolution | keywords: Face, Face finer, Face coarser, Face resolution
- In object mode, **click on a baked solid's face** (not on an edge): that **face** is picked - the face between its edges, shaded orange, its edges' edges picked with it. **G / R / S** move, turn or scale the whole face (its edges' vertices; the edges joined to it stretch to follow) - the mesh settles as after any edit.
- **Face resolution** (the panel, under the edges' line; or **Face finer / Face coarser** in the menu): each step cuts every quad of the face in four - each cut a **loop** that runs on through the quads beyond, so the surface stays quads, with no triangles to join the finer part to the rest. Lower it again and the face is back as it was (bent to its edges as they are now).
- **Quads everywhere:** a baked solid's mesh is made of quads where it can be - its walls rows of quads, its flat faces grids; where two triangles side by side would make a quad by turning their shared side, they're turned (when it's baked and each time it settles), so few lone triangles are left.

## mesh-curves-solids | Solids from edges | keywords: Extrude, Revolve, Loft, Sweep, Pipe, Fill, Steps round, Push / pull faces, Fillet edges, Inset faces
Each makes a **new part** (one **Undo** takes it back). Closed edges make **closed solids**, facing out, so the [booleans](doc:mesh-boolean) work on them; open edges make sheets (walls). The solids are [procedural](doc:mesh-curves-procedural): they follow their edges.
- **Holes:** closed edges inside a closed edge (in its plane) are holes - pick the outline and the edges inside it, then **Extrude** or **Fill**: a plate with its holes, no boolean needed. A edge inside a hole is a solid again (an island).
- **Extrude** (**E** with edges picked) - pushed along their plane's normal. The mouse sets how far (a preview shows; snapped to the grid step, **Ctrl**: free), or type it; click or **Enter** makes it, **Esc** or right-click cancels. Sharp corners stay crisp, rounded ones smooth.
- **Revolve** - the profile turned round an axis: a two-vertex line picked with it, else the model's Y axis (an edge drawn on the ground: its X line). The mouse sets the angle (by 15°, **Ctrl**: by 1°) or type it; 360° closes it. **Steps round** sets how smooth.
- **Loft** - a skin through the picked edges, in the order you picked them (closed ones capped; loops wound either way are lined up).
- **Sweep** - the first picked edge (the profile) carried along the second (the path), turned with it without twisting.
- **Pipe** - a round tube along each picked edge (the mouse or a typed radius); a closed edge makes a ring.
- **Fill** - closed edges filled with flat faces.
- **On the mesh** (edit mode; in the right-click menu): **Push / pull faces** (the selected faces pulled out or in), **Fillet edges** (the selected edges rounded), **Inset faces**, **Flatten** - the mesh tools that go with ECurves, at hand in the same tab.

## mesh-curves-procedural | Procedural solids: they follow their edges | keywords: RECIPE, Height, Angle, Radius, Steps, Both ways, Role, Edge role, Ghosts, Add, Picked edges, Other solid, Separate, Edge name, Corner radius, Closed, Pick its edges, Make plain mesh, Negative, Make the cut positive, Bake, Rename
A solid made from edges keeps its **recipe** - which edges, which operation, its height / angle / radius and steps - and is **made again from its edges whenever they change**: drag an edge's vertex and the solid reshapes as you drag; round an edge's corners, offset it, undo or redo a change - the solid follows. Its material stays.
- Select the solid (a part) and the side panel shows its **SOLID** box with its whole **recipe** - every step, editable at any time, made again at once (each change one **Undo** step): an extrusion's **height** (minus: the other way) and **Both ways** (half each side of its edges' plane), a revolve's **angle** and **steps**, a pipe's **radius**; and for each boolean step (a cut, a join...) its **role** - **Join** (union), **Cut** (subtract), **Common** (intersect) - switch it any time, and **Separate** (that step's tool solid a positive part of its own again). Steps inside steps show indented. **Pick its edges** picks the edges it's made from, ready to drag.
- **Ghosts:** a solid that's inside another's recipe (cutting it, joined to it, or shared with it) - or an edge with the **Cut** role inside a step - doesn't vanish: it shows where it is, see-through and drawn through the solid - **red** cutting, **green** joined, **blue** common - following every change live. Only a preview (never saved); the **Ghosts** box (by Grid / Vertices) turns them off.
- **Adding tools to a solid:** the SOLID box's **Add** row - choose **Cut**, **Join** or **Common**, then **Picked edges** (the edges you've picked become a new step: extruded both ways from their plane to the solid's height - change it in the recipe) or **Other solid** (select the solid, Ctrl+click another: it becomes a new step). Each new step shows in the recipe with its own settings and role, a ghost, and Separate; one **Undo** takes it back. Add as many as you like - they nest.
- **Roles everywhere:** every solid has a **Role** - **New solid (positive)** by default, or **Cut / Join / Common with the solid it's in** (a live boolean: the solid it's in keeps the recipe, and the role can be switched there any time). An extrusion or fill made from several edges lists **each edge with its own role**: **Add** (its outline part of the solid) or **Cut** (taken out of the others - a bite or a hole): one clean solid, made again from its edges live. In an extrusion each edge also has its own **height** and **Both ways** (the step's until you change them): a cut edge can be a shallow pocket or go right through, an added one stand taller or lower - everything that adds is built first, then everything that cuts is taken away. (With no roles set, an edge inside another is a hole, as drawn.)
- The **CURVE** box (under CURVES) shows the picked edge's own properties: its **name**, a circle's **radius**, a line's / rectangle's / polygon's **corner radius**, **Closed** - changed at any time, live (the solids made from it follow).
- **Moving a solid moves its edges.** A solid's place (move, turn or scale the part) is its edges' place too: they're drawn, picked, snapped and dragged where the solid is. A new solid made from them is put there as well, and copies made from them (duplicate, offset, mirror...) appear where they show.
- One edge can drive several solids (a profile both extruded and piped), and a duplicated solid (**Shift+D**) follows the same edges - move the copy and it keeps its place while sharing the shape (the edges show with the first).
- **Positive or negative:** a solid is **positive** (it adds) by default. While extruding, **N** makes it **negative**: the preview turns red and the hint names the solid it will cut - the one it's in - and when you click it's cut from that solid, live (reshape the edge: the pocket or hole follows). **Negative** in the SOLID box does the same to a solid already made; **Make the cut positive** (on the cut solid) gives the latest cutter back as a positive solid of its own, where it was.
- **Live booleans:** a boolean of two solids made from edges (**Union**, **Subtract**, **Intersect** - not Slice) stays live: the result keeps the recipe "A op B" and is worked out again whenever either one's edges change (while you drag, a few times a second). B's edges show where B was. With a plain mesh on either side the result is a plain mesh.
- It stops following its edges (a **plain mesh** from then on) when you edit its mesh in edit mode, when it's the **A** of a boolean with a plain mesh (or a Slice), or with **Make plain mesh** - **Undo** links it again. A solid whose edges are deleted stays as it was.
- **Bake** (the SOLID box; right-click the solid in the overview or the Mesh tab's list; or the view's right-click menu, ECurves page): the solid made one **Baked** solid whose **edges are its edges**. The solid as it is - its tools worked in - and every other solid touching it (overlapping or meeting it), part of it or not, become one mesh; every edge of that mesh (where its faces meet at an angle) becomes an edge - corner to corner, or a closed loop - with as few vertices as keep its shape (a straight edge two vertices, an arc three, a round rim a circle). Baking gives it a clean mesh of its own: each wall rows of quads, from each vertex of its bottom edge straight up to its top edge; flat faces filled from their edges (its edges kept exactly; a few thousand triangles whatever its size). Move a vertex of an edge - in any direction (X / Y / Z while dragging lock an axis) - and that edge of the mesh moves, the faces at it follow smoothly (every vertex of a face blended from the moves of the edges round it); a corner shared by several edges moves with all of them. Every edge shapes the mesh along its whole length - a wall's standing side edges too: put a vertex in one (double-click) and pull it, and the walls either side bend with it. While you drag, its faces follow smoothly - each wall and flat face straight between its edges, bent where a side edge bends, solved smooth across it. When you let go (or after any other edit of its edges) the solid **settles**: solved all the way, then wherever neighbouring quads bend sharply a **loop cut** runs beside that edge - every quad along the strip split in two, carried across the solid round to where it closes, so it stays quads - and that becomes its new start: the next edit bends from the shape you see, not from the bake. Undo puts the mesh back exactly. Its walls and its flat faces (tops, bottoms, a recess's ceiling) are rows and columns of quads - triangles only in the strips along curved rims. Its old edges and the solids baked in go. One undo step; saved with the model, it opens as it was.
- The recipe is saved inside the model (in the glb) and its edges beside it: opened again, it still follows them.

## mesh-save | Saving: overrides, variants, and Revert to original | keywords: Revert to original, override, variant, Add variant, Duplicate variant, Erase variant
- **Save** (**Ctrl+S**) never writes over the original model. In the game it saves an **override** beside it (in `art/overrides/`, laid out like the game) - the game uses your version from then on, at once (no restart, no import), and the original is kept as it was. In the [Mod Editor](doc:mod-editor) the mod's copy is the override (the game's file untouched). **Save as** (**Ctrl+Shift+S**) saves under another res:// path.
- An override has **variants** - versions of it, numbered 1, 2, 3... The **latest is always the active one**: the game uses it. The header's variants list shows **Original** and each variant (the active one marked); pick one to open it. Saving writes into the open variant (saving the original makes a new variant).
- **Add variant** - a new variant starting from the original (the latest, so active). **Duplicate variant** - the open variant, with your unsaved edits, copied as a new variant: duplicate an older one to make it active again. **Erase variant** - deletes the open variant (asks first); if it was the latest, the one before it becomes active, none left - the original.
- A character's material changes (its colour, metal, roughness, glow) go into the variant's own `model.json` too.
- **Revert to original** (the header button, lit when the model has an override) deletes every variant and opens the original again - the game draws the original again at once. The models list shows edited models in green.
- A Blender rebuild of a character writes the original: your variants stay on top of it.
- What's saved: every part, its materials, mirror modifiers applied - and a character's **skeleton, skin and animations**, kept as they were.
- The model's [edges](doc:mesh-curves) are saved beside it (`<model>.curves.json`, in the same variant) and come back when it's opened.
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
