# Your work on the characters: overrides

The characters (the automaton, the pirate, Kilon, the androids) are **generated**: Blender scripts in
`external/blender/automaton/` build them, and they're rebuilt whenever they change, so anything done by
hand in those `.blend` files is lost. **Your** work goes here instead, one file per character, and the
export layers it over the generated character. You keep your work; the generated base keeps improving
underneath it.

```
external/blender/automaton/automaton.blend                     generated - don't edit
external/blender_overrides/automaton/automaton_overrides.blend  yours
```

## What's in your file

| Collection / data | What it is |
|---|---|
| **Reference** | A copy of the generated character: its rig `Rig`, its parts `gen:Head`, `gen:Torso`, `gen:Arm.L`, `gen:Arm.R`, `gen:Leg.L`, `gen:Leg.R`, `gen:Rifle`, and every clip as an action `gen:walk`, `gen:swim`, ... Look, don't edit: a refresh replaces it. |
| **Overrides** | Your parts. |
| Actions without `gen:` | Your clips. |

A generated part you've overridden is hidden in the Reference, so you see yours in its place.

## The rules

- **Parts.** A mesh in *Overrides* named like a generated part (`Head`) **replaces** it. Any other name
  (`Head_Crest`, `Backpack`) is **added**. Hide a part's render (the camera icon) to leave it out for now.
- **Rigging.** Parent your part to `Rig`, then either:
  - skin it: an *Armature* modifier on `Rig` and vertex groups named after bones (`head`; a part spanning
    bones can have several, e.g. `chest`, `spine`); or
  - put it on one bone (*Parent > Bone*, e.g. the `head` bone).

  It then follows every animation. Bones: `pelvis spine chest head`, `pauldron/upper/fore/hand/fingers.L/.R`,
  `thigh/shin/foot.L/.R`, `gun`.
- **Materials.** Use the existing ones (`AUT_Armor`, `AUT_Armor2`, `AUT_Joint`, `AUT_Red`, `AUT_Red2`,
  `AUT_Grey`, `AUT_Glow`, `AUT_GlowY`, `AUT_VisorGunmetal`, `AUT_Gun`, `AUT_GunOrange`). The game knows their
  metal and roughness, the `AUT_Armor`/`AUT_Red`/`AUT_Glow` slots are recolourable, and anything named
  `AUT_Glow*` glows. A new material works but gets a plain look until the game is taught it (ask).
- **Joins.** Keep the joins where the generated ones are: the head's neck at about 1.57 m, so there's no
  gap at the collar. The export warns when your part's bottom sits higher than the generated one's.
- **Clips.** An action named like a clip (`walk`) **replaces** it; a new name (`wave`) **adds** one (the
  game plays it once code asks for it). To start from a generated clip, duplicate `gen:walk` and rename
  the copy `walk`. Custom properties on the action: `loop` (true/false), `gun` (rifle in hand). A clip you
  replace keeps those from the generated one unless you set them. Names starting `_` are scratch and aren't
  exported. Animate the `Rig`'s bones, 30 fps.
- **Modifiers.** Use any (a Mirror on half a part, a Subdivision, a Bevel...): the export applies every modifier
  except the Armature into the game's copy of your part (your file keeps them live). Put the Mirror (or any
  shape modifier) above the Armature in the stack. A left part (`Arm.L`, `Leg.L`) with an X Mirror modifier makes
  the right one too: the generated `Arm.R` is left out (and hidden in the Reference). Give it the right side's
  vertex groups (`upper.R`...) - the Mirror's *Vertex Groups* option puts the mirrored half on them.
- **Size.** About the generated part's triangle count (the head: ~1,200) keeps it cheap - after its modifiers.

## The workflow

1. Open `automaton_overrides.blend`. It starts with **your `Head`**: a copy of the generated head, ready to
   change. Delete it to go back to the generated head.
2. Model, sculpt or retopo it. Play the Rig's actions (Action editor: `gen:walk` ...) to see it move.
3. **Export to the game:** Text editor > `export_to_game` > *Run Script* (Alt+P). It saves the file, runs
   the generated character's export with your overrides merged in (into `art/player_3d/`) and runs Godot's
   import. The console lists what it took (`OVERRIDE part Head: replaced`) and any problems
   (`OVERRIDE PROBLEM: ...`). Restart the game to see it.
4. When the generated character has changed: Text editor > `refresh_reference` > *Run Script*. The
   Reference is brought up to date; your parts and actions aren't touched.

From a terminal (the project folder):

```
blender -b external/blender/automaton/automaton.blend --python external/blender/automaton/build.py -- automaton export
godot --headless --import
blender -b external/blender_overrides/automaton/automaton_overrides.blend --python external/blender_overrides/overrides.py -- automaton refresh
blender -b --python external/blender_overrides/overrides.py -- automaton check      # what the export would take, problems
```

The exported `art/player_3d/model.json` records what was overridden (`"overrides"`), and the game's tests
fail if it lists a problem.

## Other characters

`blender -b --python external/blender_overrides/overrides.py -- pirate init` makes `pirate/pirate_overrides.blend`
the same way (any skin with a generated `.blend`: `pirate`, `kilon`, `minoan`, `guard`, ...).
