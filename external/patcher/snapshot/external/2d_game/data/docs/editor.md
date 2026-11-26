# Space Atrapos - Talos documentation

# start | Getting started
How the editor is organised, how its tooltips and this documentation work, and every keyboard shortcut in one place.

## overview | The editor
Talos, the game's editor, is opened from the title screen (**Talos**) - or from inside a game: the **Esc menu's Talos** button, or **F8** (in space or on a planet; Settings > Controls to rebind). Opened from a game, it opens **over the game**: the game stays loaded underneath, paused, and the rail's way out reads **Back** - leaving Talos (Back, Esc, or F8 again) puts you straight back in it, as it was, with whatever you changed in Talos already applied. Its parts:
- **The data editor** - the quest, its dialogue, lore, the citizens' lines, and a browser of every sprite. See [The data editor](doc:data-editor).
- **The Library** - every asset of the game, alive, in rooms. See [The Library](doc:zoo).
- **The Scenario Editor** - quests written as plain-sentence rules. See [Scenarios](doc:scenarios).
- **The Level Editor** - opened in the game (right-click on a planet or in space), to reshape maps. See [Level Editor](doc:level-editor).
- **The SVG Editor** - vector drawing, SVG files, PNG export. See [The SVG Editor](doc:svg).
- **Versions** - the game's patch notes: every version and its patches, what changed, as a summary and a step-by-step infographic. See [Versions](doc:patcher).

**The rail.** Down the left of every Talos screen runs one column of every tool, each an icon with its name: **Versions** at the top and the **Library** under it, the data editor's pages (**Dialogue**, **Chapters**, **Lore**, **Citizens**, **Sprites**), then **Scenarios** and **SVG**, and **Exit** (to the title screen) at the foot. The screen you're on is lit; the rail never moves or changes size. Click any of them to go straight there. Every tool stays as you left it while you're in another (it's built the first time you open it, then kept), so switching is instant and never asks about unsaved changes; **Exit** - or **Esc**, on any Talos screen, once there's nothing in it to cancel first (a selection, a room of the Library, a path being drawn) - does ask, tool by tool, for any unsaved work. The same from the keyboard anywhere in Talos: Ctrl+1 to Ctrl+5 for the data editor's pages, F3 Library, F4 Scenarios, F6 SVG, F7 Versions.

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
**Anywhere in Talos (the rail):** Ctrl+1 to Ctrl+5 the data editor's pages (Dialogue, Chapters, Lore, Citizens, Sprites) · F3 Library · F4 Scenarios · F6 SVG · F7 Versions.
**Data editor:** Ctrl+S save · Ctrl+R reload from file · Ctrl+P preview the stage's dialogue · Esc exits Talos (as the rail's Exit).
**Scenario Editor:** Ctrl+S save · Ctrl+R reload · Ctrl+N new scenario · F5 test in game · F1 documentation · Esc exits Talos.

**SVG Editor:** right-click: menu · S select · N nodes · R rectangle · E ellipse · * star · B pen · P pencil · T text · D colour picker · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+C / Ctrl+V / Ctrl+D copy, paste, duplicate · Delete · H / V flip · Page Up / Down, Home / End order · arrows nudge · 1 100% · 5 fit page · wheel zoom · middle click: zoom back · middle drag pan · Ctrl+S save · Ctrl+O open · Ctrl+E export PNG.

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
- **Objective** - shown in the HUD and the Ship Computer while the stage is active.
- **Station** - for docking stages: the exact name of the station to dock at.
- **Position (x, y)** - for "go to" stages: the place in the system, in world units.
- **Items needed** - for delivery stages: `id=amount` pairs separated by commas, e.g. `energy_cell=4, titanium_ore=6`.
- **Enemies** - for fights: ship class ids separated by commas, e.g. `traced_ember`.
- **Rewards** - drachmas, Data Cores and an equipment id, given when the stage completes (empty or 0: none).
- **Unlocks lore ids** - lore entries unlocked by the stage, ids separated by commas.

**Dialogue** plays when the stage starts. Each line has a **speaker** and the **text**, shown as the player will read it - bold, italic, colours. **Edit** (the button beside it) shows its source, with the formatting tags dimmed (`[b]bold[/b]`, `[i]italic[/i]`, `[color=gold]colour[/color]`); **Ctrl+B** / **Ctrl+I** (or the B / I buttons under Edit) wrap the selected words; **Done**, **Esc** or a click elsewhere shows it formatted again (Esc while typing ends the typing - press it again to leave Talos). The arrow buttons move a line up or down, the cross deletes it, the plus adds a line, and the play button in the header previews the whole dialogue (Ctrl+P). Each line's box is as tall as its text.

## quest | Chapter titles
The titles of the main quest's chapters, as shown in the Ship Computer's quest page. Each stage picks its chapter in [Dialogue](doc:dialogue).

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

# svg-ch | The SVG Editor
A vector drawing program inside the editor (Talos > SVG Editor, F6), in the spirit of Inkscape: draw shapes, paths and text, edit their nodes, style them, and save real SVG files or export PNG images.

## svg | Drawing | keywords: svg, vector, inkscape, shape, path, bezier, pen, pencil, node, fill, stroke
**Tools** (left; hover them for help):
- **Select** (S) - click a shape to select it (Shift adds), drag to move it (Ctrl: only across or only up / down), drag on empty space for a box selection. The square handles scale it (Ctrl or Shift keep its proportions); the round handle above rotates it (Ctrl: 15° steps). Double-click a shape to edit its nodes. The arrows nudge it (Shift: 10 px).
- **Nodes** (N) - drag a path's nodes, or their round handles to bend the curves (a smooth node keeps its handles in line; Shift breaks that). Shift-click or drag a box to select several nodes. Double-click a segment to add a node; Delete removes nodes. **Smooth** / **Sharp** change the selected nodes, **Close / open** closes the path. Rectangles, ellipses, stars and text become paths when you edit their nodes.
- **Rectangle** (R), **Ellipse** (E) - drag to draw (Ctrl: a square or circle). **Star / polygon** (*) - drag from the centre; set the corners, the spoke ratio and star or polygon in the panel.
- **Pen** (B) - click for sharp nodes, click and drag for smooth ones; click the first node to close the shape; Enter, right-click or a double-click finishes; Backspace removes the last node; Esc stops.
- **Pencil** (P) - drag to draw freehand; the line is smoothed into curves. End near the start to close it.
- **Text** (T) - click to place text, then type it in the panel (font size, bold). Text is drawn as outlines of the game's font.
- **Colour picker** (D) - click a shape to copy its fill onto the selection (Shift: its stroke too); with nothing selected it sets the colour new shapes get.
**The panel** (right) edits the selection: fill and stroke (untick for none; colours have transparency), stroke width, opacity, the name (its id in the file), corner radius, text, star settings; position and size (X, Y, W, H), rotate 90°, flip; **align** (to each other, or one shape to the page); **arrange** (to top, raise, lower, to bottom), duplicate, delete, **to path**; the **document** (page size, background, grid). With nothing selected it sets the style new shapes are drawn with.
**Objects** (bottom right) lists every shape, top first: click to select (Ctrl / Shift for several). Each row has an **eye** - click it to hide or show that shape (hidden shapes aren't drawn or exported) - and a **padlock** to lock it (locked shapes can't be clicked on the canvas); Shift+click either to change every selected object. **Hide**, **Lock**, **Up** and **Down** below act on the selection.
**Right-click** opens a menu for what's under the mouse (with each command's shortcut):
- on a shape: cut, copy, paste, duplicate, delete; edit nodes, object to path; raise to top, raise, lower, lower to bottom; flip, rotate 90°; hide, lock. (The shape is selected first.)
- with the Nodes tool, on a node or a segment: add a node here (on a segment), make smooth, make sharp, delete nodes, **break the path here** (a closed path opens at the node; an open one splits in two), close / open the path, select all nodes.
- on empty canvas: paste, select all, zoom to the page / 100%, grid and snapping, export PNG.
The view: the wheel zooms at the mouse, middle drag (or Space + drag) pans; 1 is 100%, 5 fits the page; the grid (#) and snapping to it (%) are in the toolbar. Undo / redo (Ctrl+Z, Ctrl+Y) cover every change.

## svg-files | Files and PNG export | keywords: save, open, export, png, scale, transparent
**Save** (Ctrl+S) writes a standard SVG file (by default in `art/svg/`); **Open** (Ctrl+O) reads SVG files from anywhere - rectangles, circles, ellipses, lines, polylines, polygons, paths (every command, arcs too), text and groups with their transforms, fill, stroke and opacity. Gradients and patterns aren't supported (they turn grey); text keeps its words but uses the game's font.
**Export PNG** (Ctrl+E): choose the **area** (the page, the whole drawing or the selection), the **scale** (the pixel size is shown) and a transparent or the page's background, then where to save it. What you see on the canvas is exactly what's exported: both are drawn by the same SVG renderer.

# patcher-ch | Versions
The game's patch notes, inside Talos (Talos > Versions, the top of the rail, F7). It always opens on the newest version's infographic.

## patcher | Reading a patch | keywords: Replay, Reload patches, Previous step, Next step, Code review, Infographic, diff
Every change to the game - code, art, data - gets a **patch** entry. The list on the left is a tree: each **version** with its patches under it (click the arrow to fold it), newest first, and any patches not in a version yet at the top (Up / Down to move between them all). A patch shows:
- **A summary** - one paragraph: what changed, and why it matters.
- **An infographic** - the change step by step, drawn as vector diagrams: each step's boxes, arrows, maps and charts appear in turn, with a caption underneath. **Next step** (Right or Space) and **Previous step** (Left) move through it, going round (Next on the last step shows the first, Previous on the first the last); **Replay** (R) plays the step's animation again.

**Code review** (the second tab, or Tab) - the change as code: the changed files - code first (scripts and tools), then the other text files, then the assets - each with how many lines were added and removed; pick one to read what changed in it and why, hunk by hunk, each with the diff itself (lines added in green, removed in red, unchanged ones grey for context). Assets are shown as what they are: pictures full size (with their size in pixels, on a checkerboard so transparency shows), sounds with a Play button, fonts as sample text, and text files without a diff as their contents; **All assets** (heading the assets in the list) shows every picture of the change together. **Explanation bubbles** sit beside the code, in the empty space to the right of it, each with an arrow to a line (outlined) and a few words on how that part of the code works; they fade in as you scroll to them. Text in the review can be selected and copied.

**Unpublished changes** - at the top of the list (marked ●) when running the game from its project folder (it appears a moment after Versions opens - finding the changes takes a scan of the project - without taking you away from what you're reading): everything changed since the last patch, not yet published - the change log and the changed files (new, modified, deleted). It's tracked in the project's `external/patcher/` folder (see `external/patcher/README.md`; `python3 tools/patch.py status` lists it too); when you're ready, ask Claude to publish it as a patch entry.

**Versions** - a version gathers patches into a release: it has its own one-paragraph summary and an infographic with a **page for each patch** - what that patch brought, at a glance. The counter says which patch a page is about; **Open this patch** (Enter) jumps to it, with its full steps and code review. A version has no code review of its own.

Patches are files in `data/patches/` (one JSON file each: an id, title, date, summary, the steps with their diagrams, and the code review), and so are versions (`version_<id>_<name>.json`: "kind": "version", the patch ids it holds, its summary and pages); **Reload patches** (Ctrl+R) reads them again. Esc exits Talos.

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
