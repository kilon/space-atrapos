class_name Icons
## Small GUI icons (checkboxes, switches, slider grabbers, the reset arrow)
## painted straight into images: filled polygons and stroked lines,
## supersampled 4x for smooth edges.

const SS := 4


## layers: [{"pts": PackedVector2Array, "fill": Color, "stroke": Color,
## "width": float, "closed": bool}, ...] in icon pixels; drawn in order.
static func paint(w: int, h: int, layers: Array) -> ImageTexture:
	# Painted once ever: the picture is kept on disk under a hash of what it
	# draws (painting one in script takes ~10 ms - a screen of icons, half a
	# second - loading it back, a fraction of a millisecond).
	var key := "%s%d_%d_%d_%d.png" % [CACHE_DIR, VERSION, w, h, var_to_str(layers).hash()]
	if FileAccess.file_exists(key):
		var cached := Image.load_from_file(key)
		if cached != null and cached.get_width() == w and cached.get_height() == h:
			return ImageTexture.create_from_image(cached)
	var img := _paint(w, h, layers)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	img.save_png(key)
	return ImageTexture.create_from_image(img)


## Paints an icon not yet on disk on a worker thread (the painter only uses
## Images: safe off the main thread), so paint() finds it there later.
static func warm(w: int, h: int, layers: Array) -> void:
	if layers.is_empty():
		return
	var key := "%s%d_%d_%d_%d.png" % [CACHE_DIR, VERSION, w, h, var_to_str(layers).hash()]
	if FileAccess.file_exists(key):
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	tasks.append(WorkerThreadPool.add_task(func():
		var img := _paint(w, h, layers)
		img.save_png(key + ".tmp")
		DirAccess.rename_absolute(key + ".tmp", key)))   # (whole or not at all: paint() never reads half a file)


## The painting tasks (waited for at exit: Settings).
static var tasks: Array = []

static func wait_all() -> void:
	for t in tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	tasks.clear()


const CACHE_DIR := "user://cache/icons/"
const VERSION := 1   # (raise it if the painter changes how things look)


static func _paint(w: int, h: int, layers: Array) -> Image:
	var big := Image.create_empty(w * SS, h * SS, false, Image.FORMAT_RGBA8)
	# Each layer only where it can touch: its bounds (and half its stroke).
	var boxes := []
	for l in layers:
		var pts: PackedVector2Array = l["pts"]
		var r := Rect2(pts[0], Vector2.ZERO) if not pts.is_empty() else Rect2()
		for q in pts:
			r = r.expand(q)
		boxes.append(r.grow(float(l.get("width", 0.0)) * 0.5 + 0.5))
	for y in h * SS:
		for x in w * SS:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / SS
			var c := Color(0, 0, 0, 0)
			for li in layers.size():
				if not (boxes[li] as Rect2).has_point(p):
					continue
				var l: Dictionary = layers[li]
				var pts: PackedVector2Array = l["pts"]
				var closed: bool = l.get("closed", true)
				var fill: Color = l.get("fill", Color(0, 0, 0, 0))
				if closed and fill.a > 0.0 and Geometry2D.is_point_in_polygon(p, pts):
					c = c.blend(fill)
				var sw: float = l.get("width", 0.0)
				if sw > 0.0:
					var n := pts.size() if closed else pts.size() - 1
					for i in n:
						var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
						if p.distance_to(q) <= sw * 0.5:
							c = c.blend(l["stroke"])
							break
			big.set_pixel(x, y, c)
	big.resize(w, h, Image.INTERPOLATE_CUBIC)
	return big


static func poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0], p[1]))
	return out


static func arc(c: Vector2, r: float, a0: float, a1: float, n := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r)
	return out
