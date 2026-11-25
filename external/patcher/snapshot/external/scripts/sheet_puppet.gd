class_name SheetPuppet
extends Node2D
## A character drawn from static sprite sheets: one picture per direction
## (8 views) for each pose, art/<id>/<id>_<pose>_<dir>.png. The citizens drive
## it through set_facing, walk, phase, stride, aim, raise_amt, cooling, release
## and muzzle(). Poses: "idle" (relaxed, also used walking, with a
## bob and sway) and "aim" (shown while raise_amt > 0.5, with a recoil kick on
## release and the muzzle glowing while it cools).
## The guard: art/guard/, from the "relaxed" and "aiming" sheets of the Minoan
## android guard (external/images/minoan_npc_guard_idle.png / _aim.png).
## You on foot: art/player/ (external/images/player_on_foot_idle.png / _aim.png).
## Pirates: art/pirate/ - 4 attack frames (idle - rifle down, raise1 - across the
## body, raise2 - at the hip, aim), cut from the four reference sheets
## (external/images/npc_pirate_frame_1..4.png) by tools/character_sheets.py; no walk
## frames - they bob and sway. (Until 2026-11-09 they were rendered in Blender from
## a rigged 3D model, with a 28-frame walk: external/blender/pirate/.)
## Walking: sheets with walk frames (<id>_walk1_ .. _walkN_) play them through
## a walk cycle (one cycle per `stride` walked: phase 0..TAU) instead of the
## bob and sway. Rendered sheets come with <id>_anchors.json - the point each
## picture stands on (where the character turns, on the ground), so the frames
## don't jitter; otherwise the anchor is the middle of the feet.
##
## Clip mode (since 2026-11-21): a character with art/<id>_clips/clips.json is
## drawn from ANIMATIONS rendered in Blender at 30 fps, 8 views each
## (external/blender/automaton/: one android skeleton, a skin per character -
## the automaton "player", the pirate android "pirate"), packed into atlas
## pages by tools/puppet_atlas.py: every frame a region of a page, with the
## point it stands on. The same controls drive it - walk / phase pick a frame
## of the walk or run cycle (`gait`), raise_amt of the "raise" clip, release of
## "fire" - with the rifle in hand (`armed`) or without (`stance`: "idle",
## or "guard" - the fighting stance); play() runs a clip once (a strike, a
## leap, a spell: Skills) over them, `air()` is how high it has jumped.
## The hand-drawn sheets stay as the backup: Settings.character_graphics (the
## settings page: "Characters drawn from") draws those again.
##
## Model mode (since 2026-11-21, the first step to a 3D game): a character
## with art/<id>_3d/ (the automaton) is its actual 3D MODEL, drawn live on the
## Stage3D - one cell of the stage's picture shown by this puppet's sprite. The
## same controls and clips (model.json has their marks and heights), but posed
## at any moment in time (60 times a second, between the 30 keyed frames), the
## change from one clip to the next blended, and it turns smoothly to any
## direction - not just the 8 views. If the stage is full, or `model3d` is off
## (Settings: "rendered sprites"), the clips' pictures are used instead.

const DIRS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
## Height of the pictures on screen (px), unless set before setup().
const HEIGHT := 122.0

## Clip mode's data: id -> {fps, stand_h, pages: [Texture2D], clips: {name: {loop, gun, marks, air, points, frames}}, portrait}.
static var _sets := {}
## The hand-drawn sheets instead of the clips (Settings.character_graphics "classic"; tests).
static var classic := false
## 3D models where a character has one (off: its rendered sprites - "sprites").
static var model3d := OS.get_environment("SA_SPRITES") == ""      # (SA_SPRITES=1 godot ...: to compare)
## What a missing clip falls back on.
const FALLBACK := {"run": "walk", "gun_run": "gun_walk", "idle": "guard", "guard": "idle", "walk": "gun_walk", "gun_walk": "walk",
	"gun_idle": "idle"}

static var _cache := {}             # "id/pose/dir" -> {tex, anchor, muzzle}
static var _anchors := {}           # id -> {"<pose>_<dir>": [x, y]} (from <id>_anchors.json)

var rig_id := ""
var walk := 0.0
var phase := 0.0
var stride := 64.0
var aim := 0.0
var raise_amt := 0.0
var cooling := 0.0
var release := 0.0
var height := HEIGHT
var glow_color := Color(0.75, 1.0, 0.3)
var _view := ""                     # the direction shown ("e"... "ne")
var _pose := "idle"
var _sprite: Sprite2D
var _k := 0.5

# --- Clip mode ---
var clip_mode := false
## The rifle in its hands (the gun_ clips) - else bare hands.
var armed := true
## Bare hands, standing: "idle", or "guard" (the fighting stance).
var stance := "idle"
## How it moves: "walk" or "run" (the cycle played as `phase` goes round).
var gait := "walk"
## A hit pause (s): the picture holds still (a blow landing).
var frozen := 0.0
var _set := {}
var _one := ""                      # the clip playing once
var _one_t := 0.0
var _one_speed := 1.0
var _one_hold := false
var _one_reverse := false
var _loop_t := 0.0
var _clip := ""                     # the clip and frame shown
var _fi := -1
var _ft := 0.0                      # ... and the moment in it (s)

# --- Model mode ---
var model_mode := false
var _stage: Stage3D
var _cell := {}                     # the stage's cell: {slot, model, skeleton, anim, gun}
var _yaw := 0.0                     # the way the model faces now (its turn about the vertical), easing to _yaw_to
var _yaw_to := 0.0
var _posed := ""                    # the clip the skeleton is in
var _blend := 0.0                   # s left of blending from the pose before (a change of clip)
var _from: Array = []               # that pose: [position, rotation] per bone
const BLEND := 0.11
const TURN := 16.0                  # how fast it turns (1 / s)


## Citizens whose rig name differs from their sheets' folder.
const SHEETS := {"gunner": "guard"}


## The poses raising the weapon, in order: idle .. aim (raise_amt picks one);
## sheets with in-between frames (<id>_raise1_, _raise2_...) animate the raise.
var sequence: Array = ["idle", "aim"]
## How many walk frames the sheets have (0: walking shows idle, with a bob).
var walk_frames := 0


## Every character sheet's pictures worked out (their feet and muzzles found
## by scanning the pixels) while the loading screen shows - the first time a
## village's people appeared, that was a 15-35 ms frame in the landing.
## Awaitable (a few ms a frame).
static func warm(tree: SceneTree) -> void:
	var t := Time.get_ticks_usec()
	for rig in DirAccess.get_directories_at("res://art"):
		if not ResourceLoader.exists("res://art/%s/%s_idle_s.png" % [rig, rig]):
			continue
		var p := new()
		p.rig_id = rig
		var poses := ["idle", "aim"]
		var k := 1
		while ResourceLoader.exists("res://art/%s/%s_raise%d_s.png" % [rig, rig, k]):
			poses.append("raise%d" % k)
			k += 1
		k = 1
		while ResourceLoader.exists("res://art/%s/%s_walk%d_s.png" % [rig, rig, k]):
			poses.append("walk%d" % k)
			k += 1
		if not _anchors.has(rig):
			var ap := "res://art/%s/%s_anchors.json" % [rig, rig]
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(ap)) if FileAccess.file_exists(ap) else null
			_anchors[rig] = parsed if parsed is Dictionary else {}
		for pose in poses:
			for dir in DIRS:
				p._frame(pose, dir)
				if Time.get_ticks_usec() - t > 6000:
					await tree.process_frame
					t = Time.get_ticks_usec()
		p.free()


func setup(id: String) -> void:
	rig_id = SHEETS.get(id, id)
	if has_model(rig_id) and _setup_model():
		return
	if has_clips(rig_id):
		_set = clip_set(rig_id)
		clip_mode = true
		sequence = ["idle", "raise", "aim"]
		walk_frames = int(_set["clips"].get("gun_walk", _set["clips"].get("walk", {})).get("n", 0))
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.region_enabled = true
		_sprite.use_parent_material = true
		_sprite.show_behind_parent = true
		add_child(_sprite)
		_k = height / float(_set["stand_h"])
		_sprite.scale = Vector2(_k, _k)
		_view = "s"
		_loop_t = randf() * 2.0
		_process(0.0)
		return
	sequence = ["idle"]
	var k := 1
	while ResourceLoader.exists("res://art/%s/%s_raise%d_s.png" % [rig_id, rig_id, k]):
		sequence.append("raise%d" % k)
		k += 1
	sequence.append("aim")
	walk_frames = 0
	while ResourceLoader.exists("res://art/%s/%s_walk%d_s.png" % [rig_id, rig_id, walk_frames + 1]):
		walk_frames += 1
	if not _anchors.has(rig_id):
		var ap := "res://art/%s/%s_anchors.json" % [rig_id, rig_id]
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ap)) if FileAccess.file_exists(ap) else null
		_anchors[rig_id] = parsed if parsed is Dictionary else {}
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.use_parent_material = true
	_sprite.show_behind_parent = true   # (the muzzle glow is drawn on top)
	add_child(_sprite)
	_k = height / float(_frame("idle", "s")["tex"].get_height())
	_sprite.scale = Vector2(_k, _k)
	_view = "s"
	_show()


## One picture: its texture, the point between the feet and the muzzle (pixels).
func _frame(pose: String, dir: String) -> Dictionary:
	if clip_mode:   # (the standing picture on its own: outlines, portraits)
		var t: Texture2D = portrait(rig_id) if model_mode else _set.get("portrait")
		return {"tex": t, "anchor": Vector2(t.get_width() * 0.5, t.get_height()) if t else Vector2.ZERO, "muzzle": Vector2.ZERO}
	var key := "%s/%s/%s" % [rig_id, pose, dir]
	if not _cache.has(key):
		var path := "res://art/%s/%s_%s_%s.png" % [rig_id, rig_id, pose, dir]
		var shown := pose
		if not ResourceLoader.exists(path):   # (a one-pose sheet: the relaxed pictures for everything)
			path = "res://art/%s/%s_idle_%s.png" % [rig_id, rig_id, dir]
			shown = "idle"
		var tex: Texture2D = load(path)
		_cache[key] = {"tex": tex, "anchor": Vector2(tex.get_width() * 0.5, tex.get_height()), "muzzle": Vector2.ZERO}
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			# The feet: the middle of what's opaque in the bottom rows.
			var lo := w
			var hi := 0
			for y in range(int(h * 0.9), h):
				for x in w:
					if img.get_pixel(x, y).a > 0.5:
						lo = mini(lo, x)
						hi = maxi(hi, x)
			var anchor := Vector2((lo + hi) * 0.5 if hi >= lo else w * 0.5, h - 3)
			var given = _anchors.get(rig_id, {}).get("%s_%s" % [shown, dir])
			if given is Array and given.size() == 2:
				anchor = Vector2(given[0], given[1])
			# The muzzle: the far end of the rifle (in the side views), else
			# the middle of the chest where the barrel points at you.
			var dv := Vector2.from_angle(DIRS.find(dir) * PI / 4.0)
			var muzzle := Vector2(anchor.x, h * 0.31)
			if pose == "aim" and absf(dv.x) > 0.3:
				var best := -INF
				for y in range(int(h * 0.2), int(h * 0.42)):
					for x in w:
						if img.get_pixel(x, y).a > 0.5 and x * signf(dv.x) > best:
							best = x * signf(dv.x)
							muzzle = Vector2(x, y)
			_cache[key]["anchor"] = anchor
			_cache[key]["muzzle"] = muzzle
	return _cache[key]


func set_facing(d: Vector2) -> void:
	if d.length_squared() < 0.0001:
		return
	var v: String = DIRS[posmod(roundi(d.angle() / (PI / 4.0)), 8)]
	if model_mode:       # (any direction: it turns to it)
		_view = v
		_yaw_to = PI / 2.0 - d.angle()
		return
	if v != _view:
		_view = v
		_show()


func facing_left() -> bool:
	return _view in ["w", "sw", "nw"]


func _show() -> void:
	if _sprite == null:
		return
	if clip_mode:
		_fi = -1
		_process(0.0)
		return
	var f := _frame(_pose, _view)
	_sprite.texture = f["tex"]
	_sprite.offset = -f["anchor"]


## Where a shot leaves the barrel (local space).
func muzzle() -> Vector2:
	if clip_mode:
		return point("raise", "muzzle")
	var f := _frame("aim", _view)
	return (f["muzzle"] - f["anchor"]) * _k + _sprite.position


func _process(delta: float) -> void:
	if clip_mode:
		_process_clips(delta)
		return
	var step := clampi(roundi(raise_amt * (sequence.size() - 1)), 0, sequence.size() - 1)
	var pose: String = sequence[step]
	var cycle := walk_frames > 0
	if cycle and step == 0 and walk > 0.3:   # walking with the weapon down: the walk cycle
		pose = "walk%d" % (posmod(floori(phase / TAU * walk_frames), walk_frames) + 1)
	if pose != _pose:
		_pose = pose
		_show()
	release = move_toward(release, 0.0, delta * 6.0)
	var dv := Vector2.from_angle(DIRS.find(_view) * PI / 4.0)
	# (the walk frames have their own bob and sway; otherwise faked here)
	var stepping := 0.0 if cycle else walk
	var bob := absf(sin(phase)) * 3.0 * stepping + sin(Time.get_ticks_msec() / 650.0) * 0.6 * (1.0 - walk)
	_sprite.position = Vector2(0, -bob) - dv * Vector2(1.0, 0.5) * release * 5.0
	_sprite.rotation = sin(phase) * 0.03 * stepping
	queue_redraw()


func _draw() -> void:
	if clip_mode:
		if raise_amt > 0.9 and cooling > 0.01 and _one == "":
			var mz := muzzle()
			for i in 3:
				draw_circle(mz, (3.0 + i * 3.0) * (0.6 + 0.4 * cooling), Color(glow_color, 0.22 * cooling))
		return
	if _pose == "aim" and cooling > 0.01:   # the barrel glowing as it cools
		var m := muzzle()
		for i in 3:
			draw_circle(m, (3.0 + i * 3.0) * (0.6 + 0.4 * cooling), Color(glow_color, 0.22 * cooling))


# --- Clip mode -------------------------------------------------------------------------

static func clips_dir(id: String) -> String:
	return "res://art/%s_clips/%s" % [id, "web/" if OS.has_feature("web") else ""]


## Is this character drawn from rendered clips (and not the classic sheets)?
static func has_clips(id: String) -> bool:
	return not classic and (_sets.has(id) or FileAccess.file_exists(clips_dir(id) + "clips.json"))


## A character's standing picture, facing you (portraits, outlines): the
## rendered one, or the classic sheet's.
static func portrait(id: String) -> Texture2D:
	var path := "res://art/%s/%s_idle_s.png" % [id, id]
	if has_clips(id) and ResourceLoader.exists(clips_dir(id) + "%s_idle_s.png" % id):
		path = clips_dir(id) + "%s_idle_s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


## A character's clips (read and its pages loaded now, unless warm() did).
static func clip_set(id: String) -> Dictionary:
	if not _sets.has(id):
		var d := _read_set(id)
		for i in int(d["page_count"]):
			d["pages"].append(load(clips_dir(id) + "p%02d.png" % i))
		_sets[id] = d
	return _sets[id]


## clips.json, made ready: each clip's frame count ("n"), its frames as they are.
static func _read_set(id: String) -> Dictionary:
	var dir := clips_dir(id)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "clips.json"))
	var d: Dictionary = parsed if parsed is Dictionary else {"clips": {}, "pages": 0, "fps": 30, "stand_h": 190}
	for name in d["clips"]:
		var c: Dictionary = d["clips"][name]
		c["n"] = (c["frames"]["s"] as Array).size()
	d["page_count"] = int(d.get("pages", 0))
	d["pages"] = []
	d["fps"] = float(d.get("fps", 30))
	var pp := dir + "%s_idle_s.png" % id
	d["portrait"] = load(pp) if ResourceLoader.exists(pp) else null
	return d


## Every clip character's pages loaded in the background, one at a time
## (awaitable: the loading screen) - never in play.
static func warm_clips(tree: SceneTree) -> void:
	if classic:
		return
	for rig in DirAccess.get_directories_at("res://art"):
		if not rig.ends_with("_clips"):
			continue
		var id := rig.trim_suffix("_clips")
		if _sets.has(id) or not FileAccess.file_exists(clips_dir(id) + "clips.json"):
			continue
		if DisplayServer.get_name() == "headless":   # (tests: no window, nothing to keep smooth)
			clip_set(id)
			continue
		var task := WorkerThreadPool.add_task(func(): _reading[id] = _read_set(id))
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var d: Dictionary = _reading[id]
		_reading.erase(id)
		for i in int(d["page_count"]):
			var path := clips_dir(id) + "p%02d.png" % i
			ResourceLoader.load_threaded_request(path)
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
			d["pages"].append(ResourceLoader.load_threaded_get(path))
			await tree.process_frame
		_sets[id] = d

static var _reading := {}


func _has(clip: String) -> bool:
	return _set["clips"].has(clip)


## The clip to show for `name` (itself, or what stands in for it).
func _resolve(name: String) -> String:
	var n := name
	for _i in 4:
		if _has(n):
			return n
		n = FALLBACK.get(n, "")
		if n == "":
			break
	return (_set["clips"] as Dictionary).keys()[0]


## Plays a clip once, over walking and standing (speed: x; hold: stay on its
## last frame until stop(); reverse: backwards - getting up is falling, undone).
## False if the character hasn't got it.
func play(name: String, speed := 1.0, hold := false, reverse := false) -> bool:
	if not clip_mode or not _has(name):
		return false
	_one = name
	_one_t = 0.0
	_one_speed = speed
	_one_hold = hold
	_one_reverse = reverse
	_process(0.0)
	return true


func stop() -> void:
	_one = ""


## The clip playing once now ("" - none: walking / standing).
func playing() -> String:
	return _one


## Has the one-off clip reached its last frame (held there)?
func held() -> bool:
	return _one != "" and _one_hold and _one_t * float(_set["fps"]) >= clip_frames(_one) - 1


func clip_frames(name: String) -> int:
	return int(_set["clips"][name]["n"]) if clip_mode and _has(name) else 0


## A clip's length (s) at speed 1.
func clip_time(name: String) -> float:
	return clip_frames(name) / float(_set["fps"]) if clip_mode else 0.0


## When a clip's mark comes (s from its start at speed 1; -1: it has none).
func mark_time(name: String, mark: String) -> float:
	if not clip_mode or not _has(name) or not (_set["clips"][name]["marks"] as Dictionary).has(mark):
		return -1.0
	return float(_set["clips"][name]["marks"][mark]) / float(_set["fps"])


## How far into the one-off clip (s, at speed 1).
func clip_pos() -> float:
	return _one_t


## How high it's off the ground now (px on screen): a leap, a flying kick.
func air() -> float:
	if not clip_mode or _clip == "" or _fi < 0:
		return 0.0
	var a: Array = _set["clips"][_clip]["air"]
	return float(a[mini(_fi, a.size() - 1)]) * (_m if model_mode else _k)


## A marked point of a clip in the view shown (local space): "muzzle" of
## "raise", "hands" of a spell...; the chest if the clip hasn't got it.
func point(clip: String, name: String) -> Vector2:
	if model_mode and _has(clip):
		var p3: Dictionary = _set["clips"][clip]["points"]
		if p3.has(name):
			return _project(p3[name])
		return Vector2(0, -height * 0.62)
	if clip_mode and _has(clip):
		var pts: Dictionary = _set["clips"][clip]["points"]
		if pts.has(name):
			var v: Array = pts[name][_view]
			return Vector2(v[0], v[1]) * _k
	return Vector2(0, -height * 0.62)


## The clip shown now.
func shown() -> String:
	return _clip


## One walk / run cycle's length on the ground (m: moves.py's cycles).
const CYCLE_M := {"walk": 1.07, "run": 2.39}

## Px walked per cycle of the gait shown (classic sheets: `stride`).
func stride_px() -> float:
	if not clip_mode:
		return stride
	if model_mode:
		return float(CYCLE_M.get(gait, 1.07)) * _m
	return float(CYCLE_M.get(gait, 1.07)) * float(_set.get("px_per_m", 100.0)) * _k


func _process_clips(delta: float) -> void:
	if frozen > 0.0:
		frozen -= delta
		return
	var fps: float = _set["fps"]
	var clip := ""
	var f := 0
	var ft := 0.0        # (the moment in the clip, s: the model is posed between frames)
	if _one != "":
		_one_t += delta * _one_speed
		var n := clip_frames(_one)
		f = int(_one_t * fps)
		ft = minf(_one_t, (n - 1) / fps)
		if f >= n:
			if _one_hold:
				f = n - 1
			else:
				_one = ""
		if _one != "":
			clip = _one
			if _one_reverse:
				f = n - 1 - f
				ft = (n - 1) / fps - ft
	if clip == "":
		_loop_t += delta
		release = move_toward(release, 0.0, delta * 5.0)
		if raise_amt > 0.02 and _has("raise"):
			if raise_amt >= 0.99 and release > 0.02 and _has("fire"):
				clip = "fire"
				f = clampi(int((1.0 - release) * clip_frames("fire")), 0, clip_frames("fire") - 1)
				ft = (1.0 - release) * (clip_frames("fire") - 1) / fps
			else:
				clip = "raise"
				f = clampi(roundi(raise_amt * (clip_frames("raise") - 1)), 0, clip_frames("raise") - 1)
				ft = raise_amt * (clip_frames("raise") - 1) / fps
		elif walk > 0.3:
			clip = _resolve(("gun_" if armed else "") + gait)
			var n := clip_frames(clip)
			f = posmod(floori(phase / TAU * n), n)
			ft = fposmod(phase / TAU, 1.0) * n / fps
		else:
			clip = _resolve("gun_idle" if armed else stance)
			f = int(_loop_t * fps) % clip_frames(clip)
			ft = fposmod(_loop_t, clip_frames(clip) / fps)
	if model_mode:       # (the stage poses the model from these, 60 times a second)
		_clip = clip
		_fi = f
		_pose = clip
		_ft = ft
	elif clip != _clip or f != _fi or _fi < 0:
		_clip = clip
		_fi = f
		_pose = clip
		var fr: Array = _set["clips"][clip]["frames"][_view][f]
		var pg: Array = _set["pages"]
		if int(fr[0]) < pg.size():
			_sprite.texture = pg[int(fr[0])]
		_sprite.region_rect = Rect2(fr[1], fr[2], fr[3], fr[4])
		_sprite.offset = Vector2(fr[5], fr[6])
		_sprite.position = Vector2(0, -air())
	if cooling > 0.01 or _glowed:
		_glowed = cooling > 0.01
		queue_redraw()

var _glowed := false


# --- Model mode -------------------------------------------------------------------------

var _m := 67.7                      # px on screen per metre of the model


## Has this character a 3D model to be drawn from (and not sprites)?
const MODEL_IDS := ["player"]


static func has_model(id: String) -> bool:
	# (the 2D game draws only the automaton live - Stage3D has a few cells; the
	# pirate's model, art/pirate_3d, is for the 3D game: CosmosNpc)
	return not classic and model3d and id in MODEL_IDS and Stage3D.has_model(id)


## Takes a cell of the 3D stage; false if there's none free (the sprites then).
func _setup_model() -> bool:
	_stage = Stage3D.stage(get_tree())
	var c := _stage.claim(rig_id, _pose_model)
	if c.is_empty():
		return false
	_cell = c
	_set = Stage3D.info(rig_id)
	model_mode = true
	clip_mode = true
	sequence = ["idle", "raise", "aim"]
	walk_frames = int(_set["clips"].get("gun_walk", _set["clips"].get("walk", {})).get("n", 0))
	_m = height / float(_set["stand_m"])
	_k = _m / Stage3D.PX_PER_M
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = _stage.viewport.get_texture()
	_sprite.region_enabled = true
	_sprite.region_rect = _stage.region(int(c["slot"]))
	_sprite.offset = -Stage3D.ANCHOR
	_sprite.scale = Vector2(_k, _k)
	_sprite.use_parent_material = true
	_sprite.show_behind_parent = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	_view = "s"
	_yaw = 0.0
	_yaw_to = 0.0
	_loop_t = randf() * 2.0
	_process(0.0)
	_pose_model(0.0)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and model_mode and _stage != null and is_instance_valid(_stage) and not _cell.is_empty():
		_stage.release(int(_cell["slot"]))
		_cell = {}


## A point of the model (m: to its left, back, up - as the model was built) on
## the screen, from the way it faces now (local space of this puppet).
func _project(p: Array) -> Vector2:
	var el := deg_to_rad(Stage3D.ELEVATION)
	var x := float(p[0]) * cos(_yaw_to) - float(p[1]) * sin(_yaw_to)
	var y := float(p[0]) * sin(_yaw_to) + float(p[1]) * cos(_yaw_to)
	return Vector2(x, -(y * sin(el) + float(p[2]) * cos(el))) * _m


## Poses the model for the stage's next picture: turned the way it faces, its
## skeleton at the moment `_ft` of clip `_clip` - blended from the pose before
## for a moment after a change of clip; the rifle out of sight in clips without it.
func _pose_model(dt: float) -> void:
	if _cell.is_empty() or _clip == "":
		return
	var model: Node3D = _cell["model"]
	var sk: Skeleton3D = _cell["skeleton"]
	var anim: AnimationPlayer = _cell["anim"]
	_yaw = lerp_angle(_yaw, _yaw_to, minf(1.0, dt * TURN)) if dt > 0.0 else _yaw_to
	model.rotation.y = _yaw
	if not anim.has_animation(_clip):
		return
	var n := sk.get_bone_count()
	if _clip != _posed:
		if _posed != "" and dt > 0.0:        # (from where it is now, not a jump)
			_from.resize(n)
			for i in n:
				_from[i] = [sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i)]
			_blend = BLEND
		_posed = _clip
		anim.play(_clip)
		anim.pause()
	anim.seek(_ft, true)
	if _blend > 0.0 and _from.size() == n:
		_blend -= dt
		var w := clampf(1.0 - _blend / BLEND, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		for i in n:
			sk.set_bone_pose_position(i, (_from[i][0] as Vector3).lerp(sk.get_bone_pose_position(i), w))
			sk.set_bone_pose_rotation(i, (_from[i][1] as Quaternion).slerp(sk.get_bone_pose_rotation(i), w))
	var gun := int(_cell["gun"])
	if gun >= 0:
		sk.set_bone_pose_scale(gun, Vector3.ONE if bool(_set["clips"][_clip].get("gun", false)) else Vector3(0.0001, 0.0001, 0.0001))
