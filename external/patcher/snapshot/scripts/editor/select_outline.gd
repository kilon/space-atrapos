class_name SelectOutline
extends RefCounted
## A selection's outline - the mesh editor's selected part, the Live Editor's pick: a
## material overlay (shaders/outline.gdshader) on each of its drawn meshes, the
## overlay they had put back when it's no longer selected.

static var _mats := {}   # colour -> ShaderMaterial


static func material(col := Color(1.0, 0.42, 0.0), width := 3.5) -> ShaderMaterial:
	var key := "%s|%s" % [col, width]
	if not _mats.has(key):
		# (two passes: the shape's own pixels marked, then the line round it where they aren't - no line
		# over its folds, holes or what of it is hidden behind its front)
		var mark := ShaderMaterial.new()
		mark.shader = preload("res://shaders/outline_mark.gdshader")
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/outline.gdshader")
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("width", width)
		m.render_priority = 1
		mark.next_pass = m
		_mats[key] = mark
	return _mats[key]


## Outlines `n` (its meshes; under it too when `deep`) or takes the outline off.
static func show(n: Node, on: bool, col := Color(1.0, 0.42, 0.0), deep := true) -> void:
	if n == null or not is_instance_valid(n):
		return
	var all: Array = [n] if n is GeometryInstance3D else []
	if deep:
		all += n.find_children("*", "GeometryInstance3D", true, false).slice(0, 200)
	for g in all:
		var gi := g as GeometryInstance3D
		if not gi is MeshInstance3D:
			continue   # (a scatter, a sprite: their box shows them)
		if on:
			if not gi.has_meta("outline_was"):
				gi.set_meta("outline_was", gi.material_overlay)
			gi.material_overlay = material(col)
		elif gi.has_meta("outline_was"):
			gi.material_overlay = gi.get_meta("outline_was")
			gi.remove_meta("outline_was")
