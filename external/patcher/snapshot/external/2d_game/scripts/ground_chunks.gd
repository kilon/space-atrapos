class_name GroundChunks
extends Node2D
## A planet's tiled ground drawn as pictures: the ground tile layers
## (TileGround - a dozen or more layers, tens of thousands of tiles) live in a
## world of their own that's never drawn to the screen; CHUNK x CHUNK px
## squares of it are rendered once each into small off-screen viewports as
## they come near the view, and those pictures are what's shown - a handful of
## big quads a frame instead of thousands of tiles (the ground cost 1-1.6 ms
## of the CPU's drawing a frame; it never changes once built).
## The ground is drawn exactly as before (same layers, same order); the
## pictures are 1:1 with the world (zoomed like the tiles were).
##   var g := GroundChunks.new(); surface.add_child(g); g.host(tile_ground)
##   g.update(view_rect)            (each frame: renders what's coming into view)
##   g.update(view_rect, true)      (everything in view at once - after a jump)
##   g.redraw_all()                 (the tiles changed: hot reload)

## Off: the tile layers drawn live as before (comparisons, a fallback).
static var enabled := true

const CHUNK := 1024
const MARGIN := 4                 # px rendered round each square (filtering at its edges sees real ground)
const AHEAD := 0.6                # of a CHUNK beyond the view: rendered before it's seen
const PER_FRAME := 2              # renders a frame at most (walking about)
const MAX_POOL := 56

var ground: Node2D                # the tile layers' holder (in _host's world)
var _world := World2D.new()
var _host: SubViewport
var _pool: Array = []             # [{vp, spr, key, ready}]
var _by_key := {}
var _mat := CanvasItemMaterial.new()
var _frame := 0


func _init() -> void:
	name = "GroundChunks"
	_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA   # (a transparent render target holds premultiplied colour)
	_host = SubViewport.new()
	_host.name = "GroundWorld"
	_host.size = Vector2i(2, 2)
	_host.world_2d = _world
	_host.transparent_bg = true
	_host.disable_3d = true
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_host)


## Takes the tile layers' holder (not yet in the tree) into the ground's world.
func host(holder: Node2D) -> void:
	ground = holder
	z_index = holder.z_index
	holder.z_index = 0
	_host.add_child(holder)


## (`per_frame`: renders this frame at most - more under a fade, before the
## world is shown: settled() says when the view's all there.)
func update(view: Rect2, all_now := false, per_frame := PER_FRAME) -> void:
	_frame += 1
	for e in _pool:
		if not e["ready"] and _frame >= e["at"]:
			e["ready"] = true
			e["spr"].visible = true
	if not view.has_area():
		return
	var r := view.grow(CHUNK * AHEAD)
	var lo := Vector2i((r.position / CHUNK).floor())
	var hi := Vector2i((r.end / CHUNK).floor())
	var want := {}
	var order := []
	var c := view.get_center()
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var k := Vector2i(x, y)
			want[k] = true
			if not _by_key.has(k):
				order.append(k)
	if order.is_empty():
		return
	order.sort_custom(func(a, b): return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(c / CHUNK) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(c / CHUNK))
	var free := _pool.filter(func(e): return not want.has(e["key"]))
	var n := 0
	for k in order:
		if not all_now and n >= per_frame:
			break
		var e: Dictionary
		if not free.is_empty():
			e = free.pop_back()
			_by_key.erase(e["key"])
		elif _pool.size() < MAX_POOL:
			e = _new_entry()
		else:
			break
		_assign(e, k)
		n += 1


## Every square of `view` rendered and shown?
func settled(view: Rect2) -> bool:
	if not view.has_area():
		return false
	var lo := Vector2i((view.position / CHUNK).floor())
	var hi := Vector2i((view.end / CHUNK).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var e: Dictionary = _by_key.get(Vector2i(x, y), {})
			if e.is_empty() or not e["ready"]:
				return false
	return true


## The squares over `area` (world px) rendered again - new ground came in there
## (a chunk of a streamed planet). Their old pictures stay shown till then.
func refresh(area: Rect2) -> void:
	for e in _pool:
		if e["key"] == null:
			continue
		var sq := Rect2(Vector2(e["key"]) * CHUNK, Vector2(CHUNK, CHUNK))
		if sq.intersects(area):
			var vp: SubViewport = e["vp"]
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Every square shown is rendered again (the tiles changed).
func redraw_all() -> void:
	for e in _pool:
		if e["key"] != null:
			_assign(e, e["key"])


func chunk_count() -> int:
	return _by_key.size()


func _new_entry() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(CHUNK + 2 * MARGIN, CHUNK + 2 * MARGIN)
	vp.world_2d = _world
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = vp.get_texture()
	spr.region_enabled = true
	spr.region_rect = Rect2(MARGIN, MARGIN, CHUNK, CHUNK)
	spr.material = _mat
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.visible = false
	add_child(spr)
	var e := {"vp": vp, "spr": spr, "key": null, "ready": false, "at": 0}
	_pool.append(e)
	return e


func _assign(e: Dictionary, k: Vector2i) -> void:
	e["key"] = k
	_by_key[k] = e
	var origin := Vector2(k) * CHUNK
	var vp: SubViewport = e["vp"]
	vp.canvas_transform = Transform2D(0.0, -(origin - Vector2(MARGIN, MARGIN)))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var spr: Sprite2D = e["spr"]
	spr.position = origin
	# (Shown once it's been rendered - the frame after next; until then the
	# square's old picture would show the wrong ground.)
	spr.visible = false
	e["ready"] = false
	e["at"] = _frame + 2
