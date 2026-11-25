# Patch tracking (for the Patcher: Talos > Patcher)

Everything changed since the last published patch entry (data/patches/) is
tracked here until it's published as a new patch.

- `snapshot/` + `manifest.json` - the game as it was at the last published patch
  (a copy of every text file; a fingerprint of every file, art included).
  Changes are found by comparing the project with it - automatically, however
  the files were changed (by Claude, by hand, by a tool). Don't edit these.
- `history/<id>.md` - the log as it was when patch <id> was published.
- `pending.md` - the log: what changed and why, change by change, with the
  numbers worth showing in an infographic. Add a section for every change.

    python3 tools/patch.py status          what changed since the last patch
    python3 tools/patch.py notes-template n.json   notes to fill in, one per hunk
    python3 tools/patch.py review n.json data/patches/<id>_<name>.json
                                           adds the code review to a patch entry
    python3 tools/patch.py baseline <id>   after publishing: start tracking anew

The Patcher shows the unpublished changes at the top of its list (the log and
the changed files) when running from the project (not in exported builds).

This folder is external/patcher/: Godot doesn't import it (it has a .gdignore -
its snapshot holds copies of the game's scripts, which must not be loaded as
scripts), and builds leave out all of external/ (export_presets.cfg exclude filter).
