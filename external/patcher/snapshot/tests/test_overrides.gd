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


## An override saved before the rifle folded (no "gun.*" bones, no hip compartment, its own old rifle on the
## "gun" bone) shows the model's rifle and hip compartment instead (ModelOverride._graft): the bones added, its
## old rifle gone, the model's in - once, not twice - and the clips' tracks for the new bones kept.
func test_override_gets_the_models_rifle_and_hip_box() -> void:
	var MO: GDScript = load("res://scripts/world/models/model_override.gd")
	var path := "res://art/player_3d/player.glb"
	var root: Node = (load(path) as PackedScene).instantiate()
	var bsk: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var body: MeshInstance3D = root.find_child("Body", true, false)
	check(bsk.find_bone("gun.fore") >= 0 and bsk.find_bone("holster.R.lid") >= 0, "the model has the rifle's folding bones and the hip box's")
	var base_on := _tris_on_grafted(MO, body.mesh, body.skin, bsk)
	check(base_on > 1000, "the model's rifle and box: %d triangles" % base_on)
	# An old override: the skeleton without the new bones, the Body without the rifle, an old rifle part of its own.
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for b in bsk.get_bone_count():
		var n := bsk.get_bone_name(b)
		if n != "gun" and MO.grafted(n):
			continue
		var i := sk.get_bone_count()
		sk.add_bone(n)
		if bsk.get_bone_parent(b) >= 0:
			sk.set_bone_parent(i, sk.find_bone(bsk.get_bone_name(bsk.get_bone_parent(b))))
		sk.set_bone_rest(i, bsk.get_bone_rest(b))
	var skin := Skin.new()
	for b in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(b), sk.get_bone_global_rest(b).affine_inverse())
	var old_root := Node3D.new()
	old_root.name = "Model"
	old_root.add_child(sk)
	sk.owner = old_root
	var mk := func(nm: String, bone: String) -> MeshInstance3D:
		var a := BoxMesh.new().get_mesh_arrays()
		var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var bs := PackedInt32Array()
		var ws := PackedFloat32Array()
		for v in nv:
			bs.append_array([skin.get_bind_count() - 1 if bone == "" else sk.find_bone(bone), 0, 0, 0])
			ws.append_array([1.0, 0.0, 0.0, 0.0])
		a[Mesh.ARRAY_BONES] = bs
		a[Mesh.ARRAY_WEIGHTS] = ws
		a[Mesh.ARRAY_TANGENT] = null
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = m
		mi.skin = skin
		sk.add_child(mi)
		mi.owner = old_root
		mi.skeleton = NodePath("..")
		return mi
	mk.call("Body", "chest")
	mk.call("Gun", "gun")
	var ap: AnimationPlayer = (root.find_child("AnimationPlayer", true, false) as AnimationPlayer).duplicate()
	old_root.add_child(ap)
	ap.owner = old_root
	var old := PackedScene.new()
	old.pack(old_root)
	old_root.free()
	var inst: Node = MO._with_base_clips(old, path).instantiate()
	var sk2: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	check(sk2.find_bone("gun.fore") >= 0 and sk2.find_bone("gun.grip") >= 0 and sk2.find_bone("holster.R.lid") >= 0,
		"the model's new bones added to the old override's skeleton")
	var lid := sk2.find_bone("holster.R.lid")
	check(lid >= 0 and sk2.get_bone_parent(lid) == sk2.find_bone("holster.R") and sk2.get_bone_parent(sk2.find_bone("holster.R")) == sk2.find_bone("thigh.R"),
		"the box's bones under the right thigh, as in the model")
	check(inst.find_child("Gun", true, false) == null, "its old rifle taken out")
	var g: MeshInstance3D = inst.find_child("Grafted", true, false)
	check(g != null, "the model's rifle and hip box put in")
	if g:
		var b2: MeshInstance3D = inst.find_child("Body", true, false)
		check_eq(_tris_on_grafted(MO, g.mesh, g.skin, sk2), base_on, "all of the model's rifle and box, once")
		check(b2.skin == g.skin, "drawn with the Body's skin (one merge)")
	var ap2: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var draw: Animation = ap2.get_animation("draw")
	var has_lid := false
	for t in draw.get_track_count():
		if str(draw.track_get_path(t)).ends_with(":holster.R.lid"):
			has_lid = true
	check(has_lid, "its draw opens the box's lid (the track kept)")
	inst.free()
	root.free()


func _tris_on_grafted(MO: GDScript, mesh: Mesh, skin: Skin, sk: Skeleton3D) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var per := bs.size() / (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for t in range(0, ix.size(), 3):
			var all := true
			for c in 3:
				var v := ix[t + c]
				for j in per:
					if ws[v * per + j] > 0.0:
						var nm := str(skin.get_bind_name(bs[v * per + j]))
						if nm == "":
							nm = sk.get_bone_name(skin.get_bind_bone(bs[v * per + j]))
						if not MO.grafted(nm):
							all = false
			if all:
				n += 1
	return n
