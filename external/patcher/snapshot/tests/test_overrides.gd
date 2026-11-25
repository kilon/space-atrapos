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
