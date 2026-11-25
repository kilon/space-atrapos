extends TestCase
## The characters move smoothly: a body turns round (never snapped - a reversal a
## half-second turn, one way round), clips cross-fade, looping clips are a whole
## cycle long (no jump at the seam), and the clips' glitches - a bone flipping
## away for a frame or two, a pose jumping in one frame - are mended as they load.


## Turned from facing +z to facing -z (straight behind): how long, its largest step a frame.
func _reversal(turn: SmoothTurn, dt: float) -> Array:
	var f := Vector3(0, 0, 1)
	var t := 0.0
	var biggest := 0.0
	var sides := {}
	while t < 3.0:
		var g := turn.step(f, Vector3(0, 0, -1), Vector3.UP, dt)
		biggest = maxf(biggest, f.angle_to(g))
		if f.angle_to(g) > 0.0001:
			sides[signf(f.cross(g).y)] = true
		f = g
		t += dt
		if f.angle_to(Vector3(0, 0, -1)) < 0.01:
			break
	return [t, biggest, sides.size()]


func test_turning_round_is_smooth() -> void:
	for dt in [1.0 / 60.0, 1.0 / 600.0]:
		var r := _reversal(SmoothTurn.new(8.0, 7.5, 14.0), dt)
		check(r[0] > 0.3 and r[0] < 1.0, "a reversal turns round in about half a second (%.2f s at %d FPS)" % [r[0], roundi(1.0 / dt)])
		check(r[1] <= 7.5 * dt + 0.001, "never more than its top turn speed a frame - no snap (%.1f deg)" % rad_to_deg(r[1]))
		check_eq(r[2], 1, "round one way, not flickering between the two")
	# A small change of way: done quickly, and eased in (its first frame a small part of it).
	var turn := SmoothTurn.new(8.0, 7.5, 14.0)
	var f := turn.step(Vector3(0, 0, 1), Vector3(1, 0, 1).normalized(), Vector3.UP, 1.0 / 60.0)
	check(rad_to_deg(Vector3(0, 0, 1).angle_to(f)) < 5.0, "a turn starts gently (%.1f deg the first frame)" % rad_to_deg(Vector3(0, 0, 1).angle_to(f)))


func test_clips_loop_whole_and_have_no_glitches() -> void:
	for id in ["player", "minoan", "kilon", "pirate"]:
		if not Stage3D.has_model(id):
			continue
		var m: Node3D = Stage3D._scene(id).instantiate()
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		Stage3D.loop_clips(ap, id)
		var d := Stage3D.info(id)
		var flips := 0
		for name in ap.get_animation_list():
			var a := ap.get_animation(name)
			var c: Dictionary = d["clips"].get(name, {})
			if bool(c.get("loop", false)):
				check(a.loop_mode == Animation.LOOP_LINEAR and absf(a.length - float(c["n"]) / float(d["fps"])) < 0.001, "%s %s: loops, a whole cycle long" % [id, name])
			for t in a.get_track_count():
				if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				for k in range(1, a.track_get_key_count(t)):
					if (a.track_get_key_value(t, k - 1) as Quaternion).angle_to(a.track_get_key_value(t, k)) > deg_to_rad(120.0):
						flips += 1
		check_eq(flips, 0, "%s: no bone flipping over 120 degrees in a frame" % id)
		m.free()


func test_clips_cross_fade() -> void:
	var W: GDScript = load("res://scripts/world/player/cosmos_walker.gd")
	check(float(W.BLENDS.get("walk", 0.3)) >= 0.25 and float(W.BLENDS.get("idle", 0.3)) >= 0.25, "walking and standing cross-fade a quarter second or more")
	check(float(W.BLENDS["jump"]) < 0.2, "a jump's spring quicker")
