extends TestCase
## The characters' overrides (external/blender_overrides: your parts and clips
## layered over the generated characters at export): every exported character
## that took any reports no problems (a part on no bone, unknown vertex groups,
## a gap at a join, an unknown material), and the clips it added or replaced
## are in its model.


func test_exported_overrides_have_no_problems() -> void:
	var dir := DirAccess.open("res://art")
	check(dir != null, "the art folder")
	if dir == null:
		return
	var seen := 0
	for d in dir.get_directories():
		if not d.ends_with("_3d"):
			continue
		var path := "res://art/%s/model.json" % d
		if not FileAccess.file_exists(path):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not j is Dictionary or not (j as Dictionary).has("overrides"):
			continue
		var o: Dictionary = j["overrides"]
		seen += 1
		var problems: Array = o.get("problems", [])
		check(problems.is_empty(), "%s: no override problems (%s)" % [d, "; ".join(problems)])
		var clips: Dictionary = j.get("clips", {})
		for c in o.get("clips", {}):
			check(clips.has(c), "%s: the clip %s is in the model" % [d, c])
	check(seen >= 0, "exported characters looked at: %d" % seen)


## An override saved before a clip was made (the climb, the slide) gets it from
## the game's own model - its own clips kept.
func test_override_gets_the_models_new_clips() -> void:
	var MO: GDScript = load("res://scripts/world/models/model_override.gd")
	var path := "res://art/player_3d/player.glb"
	var root: Node = (load(path) as PackedScene).instantiate()
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var lib := AnimationLibrary.new()   # (an older save: no climb, its own walk)
	var own_walk: Animation = ap.get_animation("walk").duplicate()
	own_walk.length = 9.0   # (its own: told apart)
	for n in ap.get_animation_list():
		if n != "climb":
			lib.add_animation(n, own_walk if n == "walk" else ap.get_animation(n))
	ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	var old := PackedScene.new()
	old.pack(root)
	root.free()
	var ps: PackedScene = MO._with_base_clips(old, path)
	var inst: Node = ps.instantiate()
	var ap2: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	check(ap2.has_animation("climb"), "the model's climb added to it")
	check(not is_equal_approx(ap2.get_animation("walk").length, 9.0), "its old walk replaced by the model's current one (the moves follow the model)")
	inst.free()
