extends Node
## Preview in game (the mesh editor's toolbar, Talos opened over a game): the model as it is in
## the editor - unsaved edits too - set down in the game world in front of the camera, Talos hidden
## and the game running, to walk or fly round it; F8 or Esc: it's gone and you're back in the editor
## as you left it. Only a look: the copy is a node of the scene, never in the save, never written
## to the game's files.
## Talos opened from the title (no game under it): launch() carries Talos itself - the model, its
## unsaved edits and undo history - into your latest save (a new game if there's none) under the
## loading veil, sets it back down over the game and previews the model there.
##   ModelPreview.start(mesh_editor)    (null: no game under Talos to preview in)
##   ModelPreview.launch(mesh_editor)   (from the title: into a game first)

const BADGE_LAYER := 390   # (above the game's HUD, under Talos)

var copy: Node3D
var badge: CanvasLayer
var _overlay: CanvasLayer
var _overlay_mode := Node.PROCESS_MODE_ALWAYS
var _mouse := Input.MOUSE_MODE_VISIBLE
## (launch: the model carried across the scene change - {model, path, variant, curves, nid, dirty})
var carried := {}
var _wait := 0
var _ed: Node


## The game world under Talos (null: Talos isn't over a game, or it has no 3D world).
static func world(tree: SceneTree) -> Node3D:
	if SaveGame.talos_overlay() == null:
		return null
	var g := tree.current_scene
	var w = g.get("world") if g else null
	return w if w is Node3D and (w as Node3D).is_inside_tree() else null


## Starts previewing `ed`'s model in the game under Talos (the running preview, or null).
static func start(ed: Node) -> Node:
	var tree := ed.get_tree()
	var w := world(tree)
	if w == null or ed.get("model") == null:
		return null
	var cam := _game_camera(tree)
	if cam == null:
		return null
	var p: Node = load("res://scripts/editor/mesh/model_preview.gd").new()
	p.name = "ModelPreview"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(p)
	p.call("_begin", ed, w, cam)
	return p


## The game's 3D camera (the root viewport's - Talos's own 3D views are in sub-viewports).
static func _game_camera(tree: SceneTree) -> Camera3D:
	return tree.root.get_camera_3d()


func _begin(ed: Node, w: Node3D, cam: Camera3D) -> void:
	_ed = ed
	var src: Node3D = ed.get("model")
	copy = src.duplicate() as Node3D
	copy.name = "Preview_" + str(src.name)
	copy.set_meta("model_preview", true)
	SelectOutline.show(copy, false)   # (the editor's selection outline: not on the copy)
	w.add_child(copy)
	# (in front of the camera, facing it - as far as it takes to see it whole)
	var box := _bounds(copy)
	var up := cam.global_basis.y.normalized()
	var fwd := -cam.global_basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized() if absf(fwd.dot(up)) < 0.95 else fwd.normalized()
	var r := maxf(0.25, box.size.length() * 0.5)
	var at := cam.global_position + fwd * maxf(2.0, r * 2.5)
	copy.global_basis = Basis.looking_at(fwd, up) * Basis.from_scale(src.basis.get_scale())   # (its front, +Z, to you)
	var mid := copy.global_transform * box.get_center() if box.size != Vector3.ZERO else copy.global_position
	copy.global_position += at - mid
	# Talos hidden (and deaf), the game running
	_overlay = SaveGame.talos_overlay()
	if _overlay:
		_overlay_mode = _overlay.process_mode
		_overlay.visible = false
		_overlay.process_mode = Node.PROCESS_MODE_DISABLED
		# (its own layers - the starfield, the opaque ground - aren't hidden with it: hidden too)
		for l in _overlay.find_children("*", "CanvasLayer", true, false):
			if (l as CanvasLayer).visible:
				l.set_meta("preview_hid", true)
				(l as CanvasLayer).visible = false
	_mouse = Input.mouse_mode
	get_tree().paused = false
	badge = CanvasLayer.new()
	badge.layer = BADGE_LAYER
	var nm := str(ed.get("path")).get_file().get_basename() if str(ed.get("path")) != "" else ("your model" if str(src.name).begins_with("@") else str(src.name))
	var l := UI.label("Preview: %s  ·  F8 / Esc: back to the editor" % nm, 14, UI.GOLD)
	l.position = Vector2(16, 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)
	add_child(badge)


## The copy's meshes' bounds in its own space.
static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := (inv * mi.global_transform) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = (n as MeshInstance3D).get_aabb() if first else out.merge((n as MeshInstance3D).get_aabb())
	return out


func _input(event: InputEvent) -> void:
	if copy == null:
		return   # (the launch runner: no preview yet)
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or Keybinds.pressed(event, "talos")):
		get_viewport().set_input_as_handled()
		stop()


## The preview over: the copy gone, Talos back as it was (the game paused under it).
func stop() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(copy):
		copy.queue_free()
	if is_instance_valid(_overlay):
		_overlay.visible = true
		_overlay.process_mode = _overlay_mode
		for l in _overlay.find_children("*", "CanvasLayer", true, false):
			if l.has_meta("preview_hid"):
				l.remove_meta("preview_hid")
				(l as CanvasLayer).visible = true
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _mouse == Input.MOUSE_MODE_CAPTURED else _mouse
	if is_instance_valid(_ed) and _ed.has_method("_say"):
		_ed._say("Back from the preview.")
	queue_free()


func _exit_tree() -> void:
	if carried.get("host") is Node and is_instance_valid(carried["host"]) and not (carried["host"] as Node).is_inside_tree():
		(carried["host"] as Node).queue_free()   # (the launch never got there: Talos freed, not leaked)
	if is_instance_valid(copy) and not copy.is_queued_for_deletion():
		copy.queue_free()   # (whatever ends it: the copy never outlives the preview)


# --- from the title: into a game first --------------------------------------------------------

## Talos itself - the mesh editor with its model, undo history and selection, every other tool as it
## is - carried into the latest save (a new game if there's none), set back down over it and the
## model previewed there: nothing of Talos is lost on the way.
static func launch(ed: Node) -> void:
	var tree := ed.get_tree()
	var scene := tree.current_scene
	if scene == null:
		return
	var r: Node = load("res://scripts/editor/mesh/model_preview.gd").new()
	r.name = "ModelPreviewLaunch"
	r.process_mode = Node.PROCESS_MODE_ALWAYS
	r.carried = {"host": scene, "ed": ed}
	tree.root.add_child(r)   # (the root's: it outlives the scene change)
	r.call_deferred("_detach", scene)   # (after this click: Talos taken out whole, kept)
	Cosmos.arrive_from = ""
	if not SaveGame.read_save(-1).is_empty():
		LoadVeil.change_to(Cosmos.SCENE, "Preview", func(_progress): CosmosGame.begin(true), "Loading your save")
	else:
		LoadVeil.change_to(Cosmos.SCENE, "Preview", func(progress):
			await Galaxy.new_game_async(progress, true)
			CosmosGame.begin(false)
			CosmosGame.start_on_foot(), "Charting the galaxy")


func _detach(scene: Node) -> void:
	var tree := get_tree()
	if scene.get_parent():
		scene.get_parent().remove_child(scene)
	var stand_in := Node.new()   # (the scene the change frees in its place)
	stand_in.name = "TalosAway"
	tree.root.add_child(stand_in)
	tree.current_scene = stand_in


## (launch's runner) The game ready - the veil gone - Talos put back over it as it was, on the mesh
## editor, and the preview started.
func _process(_dt: float) -> void:
	if carried.is_empty():
		return
	var tree := get_tree()
	if tree.root.get_node_or_null("LoadVeil") != null or not world_ready(tree):
		_wait = 0
		return
	_wait += 1
	if _wait < 10:
		return   # (a few frames for the world to settle)
	var host: Node = carried["host"]
	var ed: Node = carried["ed"]
	if not is_instance_valid(host) or not is_instance_valid(ed):
		carried = {}
		queue_free()
		return
	if SaveGame.talos_overlay() == null:
		if not SaveGame.open_talos(host):
			return
	if host.has_method("show_tool"):
		host.show_tool("mesh")
	if not ed.is_visible_in_tree():
		return
	carried = {}
	start(ed)
	queue_free()


static func world_ready(tree: SceneTree) -> bool:
	var g := tree.current_scene
	if g == null or not g.has_method("get_save_data") or SaveGame.travelling:
		return false
	return not g.has_method("build_settled") or g.build_settled()
