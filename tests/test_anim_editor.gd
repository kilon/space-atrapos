extends TestCase
## Talos's animation editor (Talos > Animation, F7): it builds, shows a
## character's clips, keys bones, makes clips, undoes - and what it saves (a
## clip as art/<id>_3d/clips/<clip>.tres, here into a mod) is what the game's
## models play: Stage3D.use_clips puts it in the model's library in place of
## the model's own clip.

const SCENE := "res://scenes/editor/anim_editor.tscn"

var _mod := ""


func teardown() -> void:
	EditTarget.mod_id = ""
	Stage3D.forget_clips("player")
	if _mod != "":
		Mods.remove(_mod)
		_mod = ""


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	return ed


func test_builds_and_loads_player() -> void:
	var ed: Control = await _editor()
	check(ed.find_child("TalosNav", true, false) != null, "the rail's there (not embedded)")
	check_eq(ed.char_id, "player", "opens on the automaton")
	check(ed.characters().size() >= 5, "every character with a model is offered (%d)" % ed.characters().size())
	check(ed._sk != null and ed._sk.get_bone_count() > 10, "its skeleton's there")
	var d: Dictionary = ed._doc()
	check(d["order"].has("walk") and d["order"].has("draw"), "its clips are listed")
	ed.select_clip("walk")
	check_eq(ed.frames(), 30, "walk: 30 frames, a loop")
	check(ed.rows().size() == ed._sk.get_bone_count() and not (ed.rows()[ed._sk.find_bone("pelvis")] as PackedInt32Array).is_empty(), "the dope sheet has the pelvis's keys")
	ed.set_frame(10)
	check_eq(ed.frame, 10, "scrubbed to frame 10")
	ed.step(1)
	check_eq(ed.frame, 11, "a frame on")
	check(ed.dirty == false, "nothing changed yet")
	ed.free()
	# Embedded (the Mod Editor's): no rail.
	var em: Control = load(SCENE).instantiate()
	em.set("embedded", true)
	tree.root.add_child(em)
	await tree.process_frame
	check(em.find_child("TalosNav", true, false) == null, "embedded: no rail")
	em.free()


func test_key_new_clip_undo() -> void:
	var ed: Control = await _editor()
	ed.select_clip("walk")
	var orig: Animation = ed.anim()
	var b: int = ed._sk.find_bone("head")
	ed.select_bone("head")
	ed.set_frame(7)
	var q := Quaternion(Vector3.UP, 0.6) * Quaternion(Vector3.RIGHT, 0.3)
	ed.pose_bone(b, q)
	check(ed._sk.get_bone_pose_rotation(b).is_equal_approx(q), "the pose shows before it's keyed")
	ed.key_bone()
	var got = ed.key_value("head", 7)
	check(got is Quaternion and (got as Quaternion).is_equal_approx(q), "keyed head at frame 7 and read back (%s)" % str(got))
	check(ed.dirty, "an edit makes it dirty")
	check(ed.anim() != orig, "the edit is on a copy - the model's own clip untouched")
	var t: int = orig.find_track(NodePath(ed._prefix + ":head"), Animation.TYPE_ROTATION_3D)
	check(t >= 0 and not (orig.rotation_track_interpolate(t, 7.0 / 30.0) as Quaternion).is_equal_approx(q), "the game's walk unchanged")
	# Played back as Godot interpolates: between keys, slerped.
	ed.set_frame(7)
	check(ed._sk.get_bone_pose_rotation(b).is_equal_approx(q), "the keyed pose plays at its frame")
	# Undo takes it back, redo again.
	ed.undo()
	check(ed.anim() == orig and not ed.dirty, "undo: the clip as it was, nothing unsaved")
	ed.redo()
	check((ed.key_value("head", 7) as Quaternion).is_equal_approx(q) and ed.dirty, "redo: keyed again")
	# Keys moved, copied, pasted, deleted.
	ed.sel_keys = {Vector2i(b, 7): true}
	ed.move_keys(3)
	check((ed.key_value("head", 10) as Quaternion).is_equal_approx(q), "a key dragged 3 frames on")
	ed.copy()
	ed.set_frame(20)
	ed.paste()
	check((ed.key_value("head", 20) as Quaternion).is_equal_approx(q), "copied and pasted at frame 20")
	ed.sel_keys = {Vector2i(b, 20): true}
	ed.delete_keys()
	check(ed.key_value("head", 20) == null, "deleted")
	# New clips: empty, then a copy; rename; length; loop; delete.
	ed.new_clip(false)
	check_eq(ed.clip, "clip", "a new empty clip")
	check(ed.anim().get_track_count() == 0 and ed.frames() == 30, "empty, 30 frames")
	ed.key_all()
	check(ed.anim().get_track_count() >= ed._sk.get_bone_count(), "Key all keys every bone")
	ed.rename_clip("wave")
	check(ed._doc()["clips"].has("wave") and not ed._doc()["clips"].has("clip"), "renamed")
	ed.set_length(45)
	check_eq(ed.frames(), 45, "45 frames long")
	ed.set_loop(true)
	check(ed.anim().loop_mode == Animation.LOOP_LINEAR and ed.frames() == 45, "loops, still 45 frames")
	ed.select_clip("walk")
	ed.new_clip(true)
	check_eq(ed.clip, "walk_copy", "a copy of walk")
	check(ed.key_value("head", 10) != null, "with walk's keys")
	ed.delete_clip()
	check(not ed._doc()["clips"].has("walk_copy"), "your own clip deleted")
	ed.undo()
	check(ed._doc()["clips"].has("walk_copy"), "and undone")
	ed.rename_clip("x")
	ed.select_clip("walk")
	ed.rename_clip("stroll")
	check(ed._doc()["clips"].has("walk"), "the model's clips keep their names")
	ed.discard()
	check(not ed.dirty and not ed._doc()["clips"].has("wave"), "discard: back to as saved")
	ed.free()


func test_save_to_mod_replaces_the_clip_in_game() -> void:
	_mod = Mods.create("t")
	EditTarget.mod_id = _mod
	var ed: Control = await _editor()
	ed.select_clip("walk")
	var b: int = ed._sk.find_bone("head")
	var q := Quaternion(Vector3.FORWARD, 1.1)
	ed.set_frame(5)
	ed.pose_bone(b, q)
	ed.key_bone(b)
	ed.new_clip(false)
	ed.rename_clip("wave")
	ed.set_frame(0)
	ed.pose_bone(b, q)
	ed.key_bone(b)
	check(ed.save(), "saved")
	check(not ed.dirty, "nothing unsaved after")
	var p := Mods.files_dir(_mod) + "art/player_3d/clips/walk.tres"
	check(FileAccess.file_exists(p), "walk.tres written into the mod (%s)" % p)
	check(FileAccess.file_exists(Mods.files_dir(_mod) + "art/player_3d/clips/wave.tres"), "and the new clip")
	check(not FileAccess.file_exists("res://art/player_3d/clips/walk.tres"), "not into the game")
	ed.free()
	# A fresh model as the game makes one (CosmosWalker: loop_clips) plays the saved clip.
	Stage3D.forget_clips("player")
	var m: Node3D = Stage3D._scene("player").instantiate()
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	Stage3D.loop_clips(ap, "player", ["walk"])
	var a := ap.get_animation("walk")
	var t := a.find_track(NodePath("Rig/Skeleton3D:head"), Animation.TYPE_ROTATION_3D)
	check(t >= 0 and (a.rotation_track_interpolate(t, 5.0 / 30.0) as Quaternion).is_equal_approx(q), "the game's walk is the saved one")
	check(a.loop_mode == Animation.LOOP_LINEAR and absf(a.length - 1.0) < 0.001, "still a whole-cycle loop")
	check(ap.has_animation("wave"), "the new clip's in the model's library")
	# Back to the game's own once the mod's gone.
	EditTarget.mod_id = ""
	Stage3D.forget_clips("player")
	Mods.remove(_mod)
	_mod = ""
	var a2 := ap.get_animation("walk")
	check(a2 != a and not ap.has_animation("wave"), "without the mod: the model's own walk, no wave")
	Stage3D.use_clips(ap, "player")
	check(ap.get_animation("walk") == a2, "no clip files: nothing replaced")
	m.free()


func test_posing_in_the_view() -> void:
	var ed: Control = await _editor()
	ed.select_clip("idle")
	ed.onion = true
	for i in 3:
		await tree.process_frame   # (laid out, drawn: the skeleton, the ghosts, the dope sheet)
	var head: int = ed._sk.find_bone("head")
	var pts: Array = ed.screen_bones()
	check_eq(pts.size(), ed._sk.get_bone_count(), "every bone on screen")
	check_eq(ed.pick(pts[head] + Vector2(1, 0)), head, "clicking the head's bone picks it")
	ed.select_bone(head)
	var q0: Quaternion = ed._sk.get_bone_pose_rotation(head)
	ed.start_modal("rot")
	ed._modal["axis"] = 1
	ed._modal_update(ed._modal["start"] + Vector2(60, 0))   # (60 px: 30 degrees round its Y)
	ed.end_modal(true)
	var q: Quaternion = ed._sk.get_bone_pose_rotation(head)
	check(absf(rad_to_deg(q0.angle_to(q)) - 30.0) < 0.5, "R, Y and a drag turn it 30 degrees (%.1f)" % rad_to_deg(q0.angle_to(q)))
	check(ed.pose.has(head) and not ed.dirty, "posed, not keyed yet")
	ed.start_modal("rot")
	ed._modal_update(ed._modal["start"] + Vector2(40, 0))
	ed.end_modal(false)
	check(ed._sk.get_bone_pose_rotation(head).is_equal_approx(q), "Esc / right-click: the turn taken back")
	ed.auto_key = true
	var pelvis: int = ed._sk.find_bone("pelvis")
	ed.select_bone(pelvis)
	ed.start_modal("pos")
	ed._modal["axis"] = 1
	ed._modal_update(ed._modal["start"] + Vector2(100, 0))
	ed.end_modal(true)
	check(ed.key_value("pelvis", ed.frame, Animation.TYPE_POSITION_3D) != null and ed.dirty, "G moves the pelvis; Auto-key keys it")
	ed._rot[0].value = 20.0
	check(absf(rad_to_deg(ed._sk.get_bone_pose_rotation(pelvis).get_euler().x) - 20.0) < 0.1, "typing an angle poses the bone")
	ed.view("side")
	ed.view("top")
	ed.toggle_play()
	for i in 3:
		await tree.process_frame
	ed.toggle_play()
	check(not ed.playing, "plays and pauses")
	ed.free()
