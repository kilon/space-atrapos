extends RefCounted
## A model's override: the mesh editor saves an edited model (and a character's material table,
## model.json) beside the game's own, in res://art/overrides/ (laid out like res://), and never
## writes over the original. An override has VARIANTS - versions of it, numbered 1, 2, 3... - each a
## folder of its own files:
##   res://art/overrides/art/pirate_3d/pirate.glb.variants/3/pirate.glb   (+ model.json)
## The LATEST (the highest number) is the active one: the game uses it. A file a variant lacks (a
## model.json never edited) is read from the original. No variants: the original is used. (A Blender
## rebuild of a character writes the original: the variants stay.) Read from their own files as the
## game runs (glTF read at run time), so a save shows at once, imported or not.
##   const ModelOverride := preload("res://scripts/world/models/model_override.gd")

const DIR := "res://art/overrides/"

## Where overrides live: DIR (tests point it at a folder of their own - never the game's).
static var dir := DIR

static var _scenes := {}   # variant file -> PackedScene (read once)


## The folder of `model_path`'s variants.
static func root_of(model_path: String) -> String:
	return dir + model_path.trim_prefix("res://") + ".variants/"


## `model_path`'s variants' numbers, oldest first ([] - none: the original is used).
static func variants(model_path: String) -> Array:
	var out := []
	var root := root_of(model_path)
	if not DirAccess.dir_exists_absolute(root):
		return out
	for d in DirAccess.get_directories_at(root):
		if d.is_valid_int() and int(d) > 0:
			out.append(int(d))
	out.sort()
	return out


## The active variant: the latest (0 - none, the original).
static func active(model_path: String) -> int:
	var v := variants(model_path)
	return v[-1] if not v.is_empty() else 0


## `model_path` has an override (a variant).
static func has(model_path: String) -> bool:
	return active(model_path) > 0


## Variant `n`'s file `name` (the model's own file if no name). n = 0: the original's.
static func file_of(model_path: String, n: int, name := "") -> String:
	var f := name if name != "" else model_path.get_file()
	if n <= 0:
		return model_path.get_base_dir().path_join(f)
	return root_of(model_path) + str(n) + "/" + f


## The file to read for `model_path`'s file `name` (the model's own if none) in variant `n` (-1: the
## active one): the variant's if it has it, else the original's.
static func read(model_path: String, name := "", n := -1) -> String:
	if n < 0:
		n = active(model_path)
	var f := file_of(model_path, n, name)
	return f if n > 0 and FileAccess.file_exists(f) else file_of(model_path, 0, name)


## A new variant (the latest - so the active one): a copy of variant `from`'s files (0 - empty: its
## files read from the original till it's saved). Its number.
static func add(model_path: String, from := 0) -> int:
	var v := variants(model_path)
	var n: int = (v[-1] if not v.is_empty() else 0) + 1
	var dir := root_of(model_path) + str(n) + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	if from > 0:
		var src := root_of(model_path) + str(from) + "/"
		for f in DirAccess.get_files_at(src):
			DirAccess.copy_absolute(src + f, dir + f)
	forget(model_path)
	return n


## Variant `n` deleted (the one before it becomes active if it was the latest).
static func erase(model_path: String, n: int) -> void:
	var dir := root_of(model_path) + str(n) + "/"
	if n <= 0 or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)
	_prune(root_of(model_path))
	forget(model_path)


## Empty folders left by erasing removed, up to art/overrides/ itself.
static func _prune(folder: String) -> void:
	var top := dir.trim_suffix("/")
	var d := folder.trim_suffix("/")
	while d.length() >= top.length() and DirAccess.dir_exists_absolute(d) \
			and DirAccess.get_files_at(d).is_empty() and DirAccess.get_directories_at(d).is_empty():
		DirAccess.remove_absolute(d)
		if d == top:
			break
		d = d.get_base_dir()


## When variant `n` was last saved (Unix time; 0 - never).
static func saved_at(model_path: String, n: int) -> int:
	var f := file_of(model_path, n)
	return FileAccess.get_modified_time(f) if n > 0 and FileAccess.file_exists(f) else 0


## `model_path` as a scene: its active variant (read as glTF at run time), else the game's own.
static func scene(model_path: String) -> PackedScene:
	var p := read(model_path)
	if p == model_path and not stale(model_path):
		return load(model_path)
	if _scenes.has(p):
		return _scenes[p]
	var ps := build(model_path)
	_scenes[p] = ps
	return ps


## The override's scene read from its file - nothing remembered (safe on a worker: Stage3D.warm reads
## them there; remember() keeps it).
static func build(model_path: String) -> PackedScene:
	var p := read(model_path)
	if p == model_path and not stale(model_path):
		return load(model_path)
	var ps: PackedScene = null
	if p.get_extension().to_lower() in ["glb", "gltf"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(p, st) == OK:
			var root := doc.generate_scene(st)
			if root:
				_own(root, root)
				ps = PackedScene.new()
				ps.pack(root)
				root.free()
	if ps == null and ResourceLoader.exists(p):
		ps = load(p)   # (an exported game: the imported override)
	if ps == null:
		return load(model_path)
	return _with_base_clips(ps, model_path, p != model_path)


## An override with the game's own model's clips: an override's clips are the ones it
## was saved with - copies (the clips you edit are files of their own: Stage3D.custom_clips,
## over these) - so the model's, as they are now, take their place (a new draw, the folded
## rifle's holster...); its tracks for bones the override hasn't got left out. Its own
## clips the model hasn't got kept. Its own scene untouched; a new one packed. And the model's rifle
## and hip compartment in place of its own (_graft).
static func _with_base_clips(ps: PackedScene, model_path: String, graft := true) -> PackedScene:
	if not ResourceLoader.exists(model_path):
		return ps
	var root := ps.instantiate()
	var base := (load(model_path) as PackedScene).instantiate()
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var bap: AnimationPlayer = base.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var added := _graft(root, base) if graft else 0
	if ap and bap:
		if not ap.has_animation_library(""):
			ap.add_animation_library("", AnimationLibrary.new())
		var lib := ap.get_animation_library("")
		for n in bap.get_animation_list():
			var a: Animation = bap.get_animation(n)
			if sk:   # (its tracks for bones this skeleton hasn't got: left out)
				var keep_all := true
				for t in a.get_track_count():
					var bone := str(a.track_get_path(t).get_concatenated_subnames())
					if bone != "" and sk.find_bone(bone) < 0:
						keep_all = false
						break
				if not keep_all:
					a = a.duplicate(true)
					for t in range(a.get_track_count() - 1, -1, -1):
						var bone2 := str(a.track_get_path(t).get_concatenated_subnames())
						if bone2 != "" and sk.find_bone(bone2) < 0:
							a.remove_track(t)
			if lib.has_animation(n):
				lib.remove_animation(n)
			lib.add_animation(n, a)
			added += 1
	base.free()
	if added == 0:
		root.free()
		return ps
	var out := PackedScene.new()
	out.pack(root)
	root.free()
	return out


## The bones whose parts always come from the game's own model, whatever an override has (by name: the bone or its
## prefix) - the automaton's rifle and its folding pieces ("gun", "gun.*": automaton.py GUN_FOLD) and the hip's
## compartment it's put away in ("holster.*": automaton.py POD): an override made before they changed shows them as
## they are now - a model's mechanism, rebuilt with it, not a shape edited.
const GRAFT := ["gun", "gun.", "holster."]


static func grafted(bone: String) -> bool:
	for g in GRAFT:
		if bone == g or (g.ends_with(".") and bone.begins_with(g)):
			return true
	return false


## The game's own model's rifle and hip compartment put in the override `root` in place of its own (GRAFT): the
## bones it lacks added (as the model has them, under the same parents), its parts on those bones taken out (a
## part all on them), the model's parts on them added - one mesh ("Grafted"), skinned to the override's skeleton
## with the Body's skin (the binds it lacks added). The number of things changed (0: none).
static func _graft(root: Node, base: Node) -> int:
	var sk: Skeleton3D = root.find_child("Skeleton3D", true, false)
	var bsk: Skeleton3D = base.find_child("Skeleton3D", true, false)
	var body: MeshInstance3D = root.find_child("Body", true, false)
	var bbody: MeshInstance3D = base.find_child("Body", true, false)
	if sk == null or bsk == null or body == null or bbody == null or body.skin == null or bbody.skin == null \
			or not bbody.mesh is ArrayMesh or bsk.find_bone("holster.R") < 0:
		return 0   # (only a model whose rifle folds into its hip's compartment: the automaton)
	var changed := 0
	for b in bsk.get_bone_count():   # (its bones the override lacks: parents come first)
		var n := bsk.get_bone_name(b)
		if sk.find_bone(n) >= 0:
			continue
		var i := sk.get_bone_count()
		sk.add_bone(n)
		var par := bsk.get_bone_parent(b)
		if par >= 0:
			sk.set_bone_parent(i, sk.find_bone(bsk.get_bone_name(par)))
		sk.set_bone_rest(i, bsk.get_bone_rest(b))
		sk.set_bone_pose(i, bsk.get_bone_rest(b))
		changed += 1
	# The Body's skin with a bind for every bone the model's grafted parts use.
	var skin: Skin = body.skin.duplicate()
	var bind_of := {}
	for k in skin.get_bind_count():
		var nm := str(skin.get_bind_name(k))
		bind_of[nm if nm != "" else sk.get_bone_name(skin.get_bind_bone(k))] = k
	var bskin: Skin = bbody.skin
	var map := PackedInt32Array()   # (the model's bind -> the override's; -1 not grafted)
	for k in bskin.get_bind_count():
		var nm := str(bskin.get_bind_name(k))
		if nm == "":
			nm = bsk.get_bone_name(bskin.get_bind_bone(k))
		if not grafted(nm):
			map.append(-1)
			continue
		if not bind_of.has(nm):
			bind_of[nm] = skin.get_bind_count()
			skin.add_named_bind(nm, bskin.get_bind_pose(k))
		map.append(bind_of[nm])
	# Its own parts on those bones out (its old rifle): a part all on them goes, the Body (or a part) partly on them
	# keeps the rest.
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var kept = _without_grafted(mi.mesh, mi.skin, sk)
		if kept == null:
			continue
		changed += 1
		if (kept as ArrayMesh).get_surface_count() == 0 and mi != body:
			mi.get_parent().remove_child(mi)
			mi.free()
		else:
			mi.mesh = kept
	# The model's parts on them in.
	var src: ArrayMesh = bbody.mesh
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var a := src.surface_get_arrays(i)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if a[Mesh.ARRAY_BONES] == null or vs.is_empty():
			continue
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bs.size() / vs.size()
		var keep := PackedByteArray()
		keep.resize(vs.size())
		for v in vs.size():
			var ok := true
			for j in per:
				if ws[v * per + j] > 0.0 and (bs[v * per + j] >= map.size() or map[bs[v * per + j]] < 0):
					ok = false
					break
			keep[v] = 1 if ok else 0
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var tri := PackedInt32Array()
		for t in range(0, ix.size(), 3):
			if keep[ix[t]] and keep[ix[t + 1]] and keep[ix[t + 2]]:
				tri.append_array([ix[t], ix[t + 1], ix[t + 2]])
		if tri.is_empty():
			continue
		var used := {}    # (old vertex -> new)
		var ord := PackedInt32Array()
		for v in tri:
			if not used.has(v):
				used[v] = ord.size()
				ord.append(v)
		var b := []
		b.resize(Mesh.ARRAY_MAX)
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
			if a[k] == null:
				continue
			var col = a[k].duplicate()
			col.resize(ord.size())
			for j in ord.size():
				col[j] = a[k][ord[j]]
			b[k] = col
		var nb := PackedInt32Array()
		var nw := PackedFloat32Array()
		nb.resize(ord.size() * per)
		nw.resize(ord.size() * per)
		for j in ord.size():
			for q in per:
				var w := ws[ord[j] * per + q]
				nb[j * per + q] = map[bs[ord[j] * per + q]] if w > 0.0 else 0
				nw[j * per + q] = w
		b[Mesh.ARRAY_BONES] = nb
		b[Mesh.ARRAY_WEIGHTS] = nw
		var ni := PackedInt32Array()
		ni.resize(tri.size())
		for j in tri.size():
			ni[j] = used[tri[j]]
		b[Mesh.ARRAY_INDEX] = ni
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	body.skin = skin
	if out.get_surface_count() > 0:
		var g := MeshInstance3D.new()
		g.name = "Grafted"
		g.mesh = out
		g.skin = skin
		body.get_parent().add_child(g)
		g.owner = root
		g.transform = body.transform
		g.skeleton = g.get_path_to(sk)
		changed += 1
	return changed


## `mesh` without its triangles all on GRAFT's bones (its skin's names) - null: it has none.
static func _without_grafted(mesh: Mesh, skin: Skin, sk: Skeleton3D):
	var g := PackedByteArray()   # (bind -> on a grafted bone)
	var anyg := false
	for k in skin.get_bind_count():
		var nm := str(skin.get_bind_name(k))
		if nm == "":
			nm = sk.get_bone_name(skin.get_bind_bone(k))
		g.append(1 if grafted(nm) else 0)
		anyg = anyg or grafted(nm)
	if not anyg:
		return null
	var out := ArrayMesh.new()
	var cut := false
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix = a[Mesh.ARRAY_INDEX]
		if a[Mesh.ARRAY_BONES] == null or vs.is_empty() or ix == null:
			return null
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bs.size() / vs.size()
		var on := PackedByteArray()
		on.resize(vs.size())
		for v in vs.size():
			var all := true
			for j in per:
				if ws[v * per + j] > 0.0 and (bs[v * per + j] >= g.size() or g[bs[v * per + j]] == 0):
					all = false
					break
			on[v] = 1 if all else 0
		var tri := PackedInt32Array()
		for t in range(0, (ix as PackedInt32Array).size(), 3):
			if on[ix[t]] and on[ix[t + 1]] and on[ix[t + 2]]:
				cut = true
			else:
				tri.append_array([ix[t], ix[t + 1], ix[t + 2]])
		if tri.is_empty():
			continue
		a[Mesh.ARRAY_INDEX] = tri
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(i))
		out.surface_set_name(out.get_surface_count() - 1, mesh.surface_get_name(i))
	return out if cut else null


## A scene build() made (on a worker) kept as `model_path`'s override.
static func remember(model_path: String, ps: PackedScene) -> void:
	var p := read(model_path)
	if p != model_path and ps != null:
		_scenes[p] = ps


## `model_path`'s variants forgotten (saved again, added, erased): read anew next time.
static func forget(model_path: String) -> void:
	var root := root_of(model_path)
	for k in _scenes.keys():
		if str(k).begins_with(root) or str(k) == model_path:
			_scenes.erase(k)


## The model's own file saved over (the editor's Save) since the game imported it: read as glTF at run time
## till it's imported again - a save shows at once. (An exported game: never - its files can't change.)
static func stale(model_path: String) -> bool:
	if not model_path.get_extension().to_lower() in ["glb", "gltf"] or not FileAccess.file_exists(model_path + ".import"):
		return false
	var cf := ConfigFile.new()
	if cf.load(model_path + ".import") != OK:
		return false
	var imp := str(cf.get_value("remap", "path", ""))
	if imp == "":
		return false
	if not FileAccess.file_exists(imp):
		return true
	return FileAccess.get_modified_time(model_path) > FileAccess.get_modified_time(imp) + 1


static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
