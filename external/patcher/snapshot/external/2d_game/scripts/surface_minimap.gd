extends Control
## Planet-surface minimap: the terrain around you (VIEW tiles across, same
## isometric orientation as the view; the planet is far bigger) with markers
## for your ship, buildings, Minoan citizens and you. The planet map
## (SurfaceMap) shows the whole planet with the same drawing. Fog of war:
## what you haven't explored (surface.fog) is dark, with nothing shown in it.

## Tiles across the minimap.
const VIEW := 140.0
var surface: Node
var _tex: Texture2D
var _world_to_grid: Transform2D
var whole := false                  # the whole planet (the planet map), not around you
var whole_markers := true           # draw the plain markers (the planet map draws its own)


func setup(s: Node) -> void:
	surface = s
	clip_contents = true
	_tex = s.map_tex   # (made on the worker thread with the terrain)
	# World position -> fractional grid coordinates (inverse of map_to_local).
	var tm: TileMapLayer = s.tilemap
	var o := tm.map_to_local(Vector2i(0, 0))
	var bx := tm.map_to_local(Vector2i(1, 0)) - o
	var by := tm.map_to_local(Vector2i(0, 1)) - o
	_world_to_grid = Transform2D(bx, by, o).affine_inverse()


## Redrawn REDRAW_HZ times a second (drawing it costs about a millisecond:
## the map picture, every building, person and animal near you).
const REDRAW_HZ := 15.0
var _redraw_t := 0.0

func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / REDRAW_HZ
		queue_redraw()


## Grid -> minimap pixel (diamond: x right-down, y left-down): the whole
## planet fitted (whole), or VIEW tiles centred on you.
func _grid_xform() -> Transform2D:
	var n: float = surface.N
	if whole:
		var a := size.x / (2.0 * n)
		return Transform2D(Vector2(a, a * 0.5), Vector2(-a, a * 0.5), Vector2(size.x / 2.0, size.y / 2.0 - n * a * 0.5))
	var a := size.x / (2.0 * VIEW)
	var basis := Transform2D(Vector2(a, a * 0.5), Vector2(-a, a * 0.5), Vector2.ZERO)
	var me: Vector2 = _world_to_grid * surface.pilot.global_position + Vector2(0.5, 0.5)
	return Transform2D(basis.x, basis.y, size / 2.0 - basis.basis_xform(me))


func _to_map(world: Vector2) -> Vector2:
	return _grid_xform() * (_world_to_grid * world + Vector2(0.5, 0.5))


## A teleport gate's map icon: a glowing arch with a swirl in it, `r` px.
static func portal_icon(ci: CanvasItem, at: Vector2, r: float) -> void:
	var col := NeonTheme.HEAD
	ci.draw_circle(at, r * 1.6, Color(col, 0.22))
	var arch := PackedVector2Array([at + Vector2(-r, r)])
	for k in 9:
		arch.append(at + Vector2.from_angle(PI + k * PI / 8.0) * r)
	arch.append(at + Vector2(r, r))
	ci.draw_polyline(arch, Color(1.0, 0.85, 0.45), maxf(1.5, r * 0.35), true)
	var t := Time.get_ticks_msec() / 1000.0
	ci.draw_arc(at + Vector2(0, r * 0.15), r * 0.55, t * 3.0, t * 3.0 + PI * 1.4, 10, Color(col.lightened(0.4)), maxf(1.2, r * 0.25), true)


func _draw() -> void:
	if surface == null:
		return
	var n: float = surface.N
	var g := _grid_xform()
	var corners := PackedVector2Array([g * Vector2(0, 0), g * Vector2(n, 0), g * Vector2(n, n), g * Vector2(0, n)])
	var pad := PackedVector2Array()
	var c := size / 2.0
	if whole:   # frame behind the diamond
		for p in corners:
			pad.append(c + (p - c) * 1.06)
	else:
		pad = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	draw_colored_polygon(pad, Color(NeonTheme.BG, 0.9))
	# Terrain.
	draw_set_transform_matrix(g)
	draw_texture_rect(_tex, Rect2(0, 0, n, n), false)
	if surface.fog != null:
		draw_texture_rect(surface.fog.texture(), Rect2(0, 0, n, n), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_polyline(pad + PackedVector2Array([pad[0]]), Color(NeonTheme.HEAD, 0.7), 2.0, true)

	# Markers.
	# Buildings: their footprints (Minoan palace, warehouses, temples) - built or not yet.
	for r in surface.building_rects():
		if surface.fog != null and not surface.fog.explored(Vector2(r.get_center()) + Vector2(0.5, 0.5)):
			continue   # (in the fog)
		var pts := PackedVector2Array([g * Vector2(r.position), g * Vector2(r.end.x, r.position.y),
			g * Vector2(r.end), g * Vector2(r.position.x, r.end.y)])
		draw_colored_polygon(pts, NeonTheme.BG_LIGHT)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(NeonTheme.HEAD, 0.9), 1.0)
	if not whole_markers:
		return   # (the planet map draws the rest itself)
	# Teleport gates you've discovered: a small portal (an arch with its swirl).
	var gs = surface.get("gates")
	for gt in gs if gs is Array else []:
		var gc: Vector2 = Vector2(gt["cell"]) + Vector2(0.5, 0.5)
		if surface.fog != null and not surface.fog.explored(gc):
			continue
		portal_icon(self, g * gc, 7.0)
	for a in surface.npcs:
		if not surface.explored_at(a.global_position):
			continue
		var pirate: bool = a.get("species") == "pirate"
		draw_circle(_to_map(a.global_position), 3.0 if pirate else 2.5, Color(1.0, 0.25, 0.2) if pirate else Color(0.95, 0.75, 0.35))
	for cr in surface.get("creatures") if surface.get("creatures") is Array else []:   # (predators: red, like pirates)
		if is_instance_valid(cr) and cr.hostile and not cr.dead and surface.explored_at(cr.global_position):
			draw_circle(_to_map(cr.global_position), 2.5, Color(1.0, 0.25, 0.2))
	var lp := _to_map(surface.lander.global_position)
	draw_rect(Rect2(lp - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.55, 0.15))
	var pp := _to_map(surface.pilot.global_position)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(pp, 6.0, Color(1, 1, 1, 0.25 * pulse))
	draw_circle(pp, 3.5, Color.WHITE)
