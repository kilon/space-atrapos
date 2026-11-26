extends SceneTree
## Every game script compiles? Run by LiveLink in a fresh process before a
## live restart (after an import, so new class_names are known):
##   godot --headless --path . -s res://tools/live_check.gd
## Exit code 0: all compile; 1: some don't (their paths printed, "BROKEN <path>").

const DIRS := ["res://scripts"]


func _initialize() -> void:
	var bad := []
	var n := 0
	var stack: Array = DIRS.duplicate()
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			var p := d.path_join(f)
			n += 1
			var s: Script = load(p)
			if s == null or not s.can_instantiate():
				bad.append(p)
	for p in bad:
		print("BROKEN ", p)
	print("live_check: %d scripts, %d broken" % [n, bad.size()])
	quit(1 if not bad.is_empty() else 0)
