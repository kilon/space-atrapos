class_name EditTarget
extends RefCounted
## Where Talos's tools (the mesh and animation editors) read and save: the game
## itself (res://, when it runs from its project folder) or a mod (the Mod Editor
## sets `mod_id`: user://mods/<id>/files/, laid out like the game - Mods lays it
## over the game as it starts).
##   EditTarget.write_path("res://art/x.glb")  -> where saving x.glb goes now
##   EditTarget.read_path("res://art/x.glb")   -> the mod's copy if it has one, else the game's

## "" - the game itself; else the mod being made.
static var mod_id := ""


static func is_mod() -> bool:
	return mod_id != ""


## The game's own files can be saved: running from the project folder (not an exported game).
static func game_writable() -> bool:
	return not OS.has_feature("template")


## Saving's possible now (a mod - always; the game - from its project folder).
static func writable() -> bool:
	return is_mod() or game_writable()


## The folder res:// maps to now.
static func root() -> String:
	return Mods.files_dir(mod_id) if is_mod() else "res://"


## Where `res_path` (res://...) is saved now (its folder made).
static func write_path(res_path: String) -> String:
	if not is_mod():
		return res_path
	var p := root() + res_path.trim_prefix("res://")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	return p


## Where `res_path` is read from now: the mod's copy, if it has one.
static func read_path(res_path: String) -> String:
	if is_mod():
		var p := root() + res_path.trim_prefix("res://")
		if FileAccess.file_exists(p):
			return p
	return res_path


## The mod has its own copy of `res_path`.
static func overridden(res_path: String) -> bool:
	return is_mod() and FileAccess.file_exists(root() + res_path.trim_prefix("res://"))


## Saving now goes to (for a tool's header): "the game" / "mod: <name>".
static func label() -> String:
	if not is_mod():
		return "the game" if game_writable() else "nowhere (an exported game: make a mod)"
	return "mod: " + str(Mods.info(mod_id).get("name", mod_id))
