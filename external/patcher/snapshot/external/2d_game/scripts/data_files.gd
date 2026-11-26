class_name DataFiles
extends RefCounted
## Editable game data (JSON text files in res://data/). When the game runs
## from the editor, Developer Mode saves straight into the project files; in
## an exported game it saves to user:// instead (which then takes priority).


static func user_path(res_path: String) -> String:
	return "user://" + res_path.get_file()


## Reads a data file; returns {} if it's missing or invalid. Each file is
## parsed once per version of it (its modified time) and kept; callers get a
## copy of their own (a new game read the same files again: ~17 ms).
static var _cache := {}   # path -> [modified time, data]
static func read(res_path: String) -> Dictionary:
	var paths := [res_path] if OS.has_feature("editor") else [user_path(res_path), res_path]
	for p in paths:
		if FileAccess.file_exists(p):
			var mt := FileAccess.get_modified_time(p)
			var known: Array = _cache.get(p, [])
			if not known.is_empty() and int(known[0]) == mt:
				return (known[1] as Dictionary).duplicate(true)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary:
				var d: Dictionary = _ints(parsed)
				_cache[p] = [mt, d]
				return d.duplicate(true)
			push_warning("Could not parse %s - using the built-in data." % p)
	return {}


## Writes a data file; returns the absolute path written ("" on failure).
static func write(res_path: String, data: Dictionary) -> String:
	var p := res_path if OS.has_feature("editor") else user_path(res_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(pretty(data) + "\n")
	f.close()
	_cache.erase(p)
	return ProjectSettings.globalize_path(p)


## JSON numbers load as floats: turn whole numbers back into ints.
static func _ints(v: Variant) -> Variant:
	if v is Dictionary:
		for k in v:
			v[k] = _ints(v[k])
	elif v is Array:
		for i in v.size():
			v[i] = _ints(v[i])
	elif v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e12:
		return int(roundf(v))
	return v


## Readable JSON: short arrays (dialogue lines, positions, spawns) stay on one
## line, everything else is indented.
static func pretty(v: Variant, indent := "") -> String:
	var inner := indent + "\t"
	if v is Dictionary:
		if v.is_empty():
			return "{}"
		var parts := []
		for k in v:
			parts.append(inner + JSON.stringify(str(k)) + ": " + pretty(v[k], inner))
		return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
	if v is Array:
		if v.is_empty():
			return "[]"
		var all_scalar := true
		var all_short := true
		for e in v:
			if e is Dictionary or e is Array:
				all_scalar = false
				if not (e is Array and e.all(func(x): return not (x is Dictionary or x is Array))):
					all_short = false
		if all_scalar:
			return "[" + ", ".join(v.map(func(e): return JSON.stringify(e))) + "]"
		var one_line := "[" + ", ".join(v.map(func(e): return pretty(e, inner))) + "]"
		if all_short and one_line.length() < 90:
			return one_line
		var lines := []
		for e in v:
			lines.append(inner + pretty(e, inner))
		return "[\n" + ",\n".join(lines) + "\n" + indent + "]"
	return JSON.stringify(v)
