extends Node
## The mesh editor's previews (its models; the shape library's shapes): each thing drawn
## as a TURNTABLE - FRAMES pictures of it turned round, in one strip - once, in the
## background, kept on disk (user://cache/mesh_thumbs/, by its key: a file's path and
## time, a shape's recipe) and in memory. One at a time: the thing read or made on a
## worker, then one frame of it drawn each tick into a small lit world - never more than
## a few milliseconds in a frame. A list shows frame 0; hovered, it turns (frames()).

signal made(key: String, tex: Texture2D)

const SIZE := 128
const FRAMES := 24
const DIR := "user://cache/mesh_thumbs/"
const VERSION := 2

var _mem := {}            # key -> Array of AtlasTexture (the turntable)
var _queue: Array = []    # [key, Callable -> Node3D or Mesh (on a worker), disk file]
var _busy := ""           # the key being made
var _busy_disk := ""
var _task := -1
var _read: Array = []
var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _pivot: Node3D
var _strip: Image
var _frame := 0
var _wait := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _read_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_read_task)
		_read_task = -1


## Frame 0 of `key`'s turntable if it's made (else null - ask() for it). `file`: a model's file.
func get_thumb(key: String, file := "") -> Texture2D:
	var f := frames(key, file)
	return f[0] if not f.is_empty() else null


## `key`'s turntable (FRAMES pictures), or [] - not in memory yet: one made before is read from
## disk in the background (made() when it's in - a list of a hundred previews opens at once).
func frames(key: String, file := "") -> Array:
	if _mem.has(key):
		return _mem[key]
	if not _reading.has(key):
		var disk := _disk(key, file)
		if FileAccess.file_exists(disk):
			_reading[key] = disk
			_read_queue.append(key)
	return []


var _reading := {}        # key -> its disk file (being read, or waiting to be)
var _read_queue: Array = []
var _read_task := -1
var _read_out: Array = []   # [[key, Image]...] (the worker's)
var _read_done: Array = []  # read, waiting to become textures


## The disk reads: a few at a time on a worker; their textures made here as they come in.
func _pump_reads() -> void:
	if _read_task >= 0:
		if not WorkerThreadPool.is_task_completed(_read_task):
			return
		WorkerThreadPool.wait_for_task_completion(_read_task)
		_read_task = -1
		_read_done.append_array(_read_out)
		_read_out = []
	# (two a frame made into textures: a batch at once was a 40 ms frame)
	for i in mini(2, _read_done.size()):
		var e: Array = _read_done.pop_front()
		var key: String = e[0]
		_reading.erase(key)
		var img: Image = e[1]
		if img and img.get_width() == SIZE * FRAMES:
			_mem[key] = _cut(ImageTexture.create_from_image(img))
			made.emit(key, _mem[key][0])
	if _read_queue.is_empty() or _read_task >= 0 or _read_done.size() > 8:
		return
	var batch: Array = []
	while not _read_queue.is_empty() and batch.size() < 8:
		var k: String = _read_queue.pop_front()
		batch.append([k, _reading[k]])
	_read_task = WorkerThreadPool.add_task(func():
		var out := []
		for b in batch:
			out.append([b[0], Image.load_from_file(ProjectSettings.globalize_path(b[1]))])
		_read_out = out, false, "mesh editor: previews from disk")


func _cut(strip: Texture2D) -> Array:
	var out := []
	for i in FRAMES:
		var a := AtlasTexture.new()
		a.atlas = strip
		a.region = Rect2(i * SIZE, 0, SIZE, SIZE)
		out.append(a)
	return out


## A model file's turntable to be made, in turn (made() when it is).
func ask(path: String, file: String) -> void:
	var MeshIO: GDScript = load("res://scripts/editor/mesh/mesh_io.gd")
	_enqueue(path, func(): return MeshIO.read(file), _disk(path, file))


## Something made by `maker` (on a worker: a Node3D or a Mesh) - a shape - under `key`.
func ask_mesh(key: String, maker: Callable) -> void:
	_enqueue(key, maker, _disk(key, ""))


func _enqueue(key: String, maker: Callable, disk: String) -> void:
	if _mem.has(key) or _reading.has(key) or key == _busy or DisplayServer.get_name() == "headless":
		return   # (in memory, on its way from disk, or being drawn)
	for q in _queue:
		if q[0] == key:
			return
	_queue.append([key, maker, disk])


## Forget the queue (the list changed): only what's asked again is made.
func clear_queue() -> void:
	_queue.clear()


func _disk(key: String, file: String) -> String:
	var t := FileAccess.get_modified_time(file) if file != "" and FileAccess.file_exists(file) else 0
	return DIR + ("%d|%s|%d" % [VERSION, key, t]).md5_text() + ".png"


func _process(_dt: float) -> void:
	_pump_reads()
	if _busy == "":
		if _queue.is_empty():
			return
		var q: Array = _queue.pop_front()
		_busy = q[0]
		_busy_disk = q[2]
		var maker: Callable = q[1]
		_read = []
		_task = WorkerThreadPool.add_task(func(): _read = [maker.call()], false, "mesh editor: a preview")
		return
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var n = _read[0] if not _read.is_empty() else null
		if n is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = n
			n = mi
		if not n is Node3D:
			if n is Node:
				n.free()
			_busy = ""
			return
		_model = n
		_pivot.rotation = Vector3.ZERO
		_pivot.add_child(_model)
		_aim()
		_strip = Image.create_empty(SIZE * FRAMES, SIZE, false, Image.FORMAT_RGBA8)
		_frame = 0
		_shoot()
		return
	_wait -= 1
	if _wait > 0:
		return
	var img := _vp.get_texture().get_image()
	if img and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		_strip.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i(_frame * SIZE, 0))
	_frame += 1
	if _frame < FRAMES:
		_shoot()
		return
	var key := _busy
	_model.queue_free()
	_model = null
	_busy = ""
	_strip.save_png(_busy_disk)
	_mem[key] = _cut(ImageTexture.create_from_image(_strip))
	_strip = null
	made.emit(key, _mem[key][0])


## The next frame: the thing turned on, drawn once.
func _shoot() -> void:
	_pivot.rotation.y = TAU * float(_frame) / FRAMES
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2


## The camera framing the thing (centred on the turntable's axis): from the front,
## a little above, far enough for it to stay in view all the way round.
func _aim() -> void:
	var box := AABB()
	var first := true
	for v in _model.find_children("*", "VisualInstance3D", true, false) + ([_model] if _model is VisualInstance3D else []):
		var vi := v as VisualInstance3D
		var b: AABB = vi.global_transform * vi.get_aabb() if vi.is_inside_tree() else vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var c := box.get_center()
	_model.position -= Vector3(c.x, 0, c.z)   # (turning about its own middle)
	var r := maxf(Vector2(box.size.x, box.size.z).length() * 0.5, box.size.y * 0.5)
	r = maxf(Vector3(r, box.size.y * 0.5, r).length() * 0.8, 0.05)
	var dir := Vector3(0.0, 0.32, 1.0).normalized()
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.02
	var look := Vector3(0, c.y, 0)
	_cam.look_at_from_position(look + dir * dist, look, Vector3.UP)
	_cam.near = maxf(dist * 0.01, 0.001)
	_cam.far = dist * 4.0
