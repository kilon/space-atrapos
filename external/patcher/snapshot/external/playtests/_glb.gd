extends SceneTree
func _initialize() -> void:
	var ps: PackedScene = load("res://art/player_3d/player.glb")
	var n := ps.instantiate()
	root.add_child(n)
	_dump(n, 0)
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap:
		var names := ap.get_animation_list()
		print("ANIMS ", names.size(), " ", names)
		for a in ["idle", "walk", "jab", "leap", "ko"]:
			if ap.has_animation(a):
				var an := ap.get_animation(a)
				print(a, " len ", an.length, " tracks ", an.get_track_count(), " ", an.track_get_path(0), " type0 ", an.track_get_type(0), " keys ", an.track_get_key_count(0))
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	if sk:
		var bn := []
		for i in sk.get_bone_count():
			bn.append(sk.get_bone_name(i))
		print("BONES ", bn)
	quit()
func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		var mats := []
		for i in m.get_surface_count():
			mats.append(str(m.surface_get_material(i).resource_name if m.surface_get_material(i) else "-"))
		extra = " surfaces %d %s aabb %s skin %s" % [m.get_surface_count(), mats, m.get_aabb(), n.skin != null]
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", extra)
	if d < 3:
		for c in n.get_children():
			_dump(c, d + 1)
