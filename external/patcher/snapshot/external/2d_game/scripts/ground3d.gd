class_name Ground3D
extends Node2D
## A planet's tiled ground as actual 3D geometry (the second step of the game
## turning 3D, after the automaton's model: Stage3D). Instead of thousands of
## flat tile pictures laid over each other (the TileGround's layers, drawn as
## GroundChunks' pictures), the ground is 3D TILES, modelled as they're laid:
##   ground on level l   a patch at that height (LEVEL_H a level), its surface
##                       rolling a little (RELIEF: one smooth field over the
##                       whole world, so tiles and chunks meet), painted with
##                       the tile's own picture; a short bank under its front
##                       edges (seen where the ground in front is lower: a shore)
##   a cliff block       the patch, and its two front faces built of stone
##                       blocks - each one a bevelled block standing out of the
##                       wall by its own depth, in the set's stone
##   a ramp              the patch tilted up a level, stone under its sides
##   water               a sheet sunk below the shore (WATER_DROP)
## lit by a real sun (from the upper left, as the painted scenery is: tops
## bright, left faces lit, right faces in shade) that CASTS SHADOWS - cliffs and
## ledges shade the ground beside them.
##
## One mesh per generated chunk of the world (PlanetSurface's GEN x GEN tiles:
## add_chunk as each arrives - its arrays worked out on a worker thread, the
## mesh made when they're done). An orthographic Camera3D looks at it from the
## isometric angle (30 degrees above the horizon, turned 45: a tile's square is
## the 128 x 64 px diamond), kept on the 2D camera (sync); the picture - a
## SubViewport a little bigger than the window, drawn again only when the view
## leaves it, the zoom changes or the ground does (the camera slides along the
## ground: the picture just moves) - is shown by a sprite where the 2D ground
## was (z -10), so everything else of the 2D world is drawn over it as before.
##   Ground3D.enabled = false     the 2D ground again (GroundChunks: tests, a fallback)

static var enabled := OS.get_environment("SA_GROUND2D") == ""     # (SA_GROUND2D=1 godot ...: the 2D ground, to compare)

const TTILES := preload("res://scripts/terrain_tiles.gd")
const PPU := 90.50966799187809           # px on screen per world unit (a tile is 1 x 1: its diamond 128 px wide)
const ELEV := PI / 6.0                   # the camera above the horizon: the 2:1 diamonds
const LEVEL_H := TTILES.LEVEL_PX / (0.8660254037844387 * PPU)   # a level's height (units)
const MESHES_A_FRAME := 2                # chunk meshes made a frame (their arrays come from workers)
const MARGIN := 128.0                    # px drawn beyond the window on every side: walking on needn't draw it again
const RELIEF := 0.035                    # how far the ground rolls up and down (units: ~3 px)
const WATER_DROP := 0.32                 # the water's sheet below its level (of a level)
const BANK := 1.45                       # the bank under a patch's front edges (levels deep)
const CAM_BACK := 60.0                   # how far back the camera stands (it's orthographic: only what its shadows must reach)
const SUN := Vector3(-1.0, 1.6, 1.0)     # where the sun stands (from the upper left of the screen, a little toward you)
const FLAT := 0
const BLOCK := 1
const RAMP := 2
const WATER := 3

var surface: Node
var plot_lvl := 0
var _vp: SubViewport
var _cam: Camera3D
var _spr: Sprite2D
var _mat: StandardMaterial3D              # the patches: the tiles' pictures, lit
var _stone_mat: StandardMaterial3D        # the stone blocks and banks: their own colours, lit
var _stone := Color(0.8, 0.7, 0.6)
var _atlas: Texture2D
var _pieces: Array = []                  # per tile source: [kind, atlas x, atlas y, w, h, ramp dir]
var _chunks := {}                        # chunk id -> MeshInstance3D
var _cells := {}                         # chunk id -> its tiles' rectangle (grid)
var _tasks := {}                         # chunk id -> worker task
var _done := {}                          # chunk id -> [vertices, uvs, indices] (from the workers)
var _lock := Mutex.new()
var _drawn := Rect2()                    # the part of the world the picture shows (world px)
var _zoom := 0.0                         # ... at this zoom
var _dirty := true


## False if this tile set can't be drawn in 3D (its pieces not in one atlas): the 2D ground then.
func setup(surface_: Node, ts: TileSet, names: Array, plot_level: int) -> bool:
	surface = surface_
	plot_lvl = plot_level
	name = "Ground3D"
	z_index = -10
	for i in names.size():
		var src := ts.get_source(i) as TileSetAtlasSource if ts.has_source(i) else null
		if src == null or src.texture == null:
			_pieces.append([FLAT, 0.0, 0.0, 0.0, 0.0, 0])
			continue
		if _atlas == null:
			_atlas = src.texture
		elif src.texture != _atlas:
			return false
		var base := str(names[i]).substr(3)
		var set_ := str(names[i]).substr(0, 2)
		if TTILES.SETS.has(set_):
			_stone = TTILES.SETS[set_]["stone"]
		var kind := BLOCK
		var r := 0
		if TTILES.SETS.has(set_) and base != "" and (base == str(TTILES.SETS[set_].get("deep", "")) or base == str(TTILES.SETS[set_].get("shallow", ""))):
			kind = WATER
		elif base in TTILES.FLAT or base in TTILES.RIMS:
			kind = FLAT
		elif base.begins_with("ramp_"):
			kind = RAMP
			r = TTILES.RAMP_PIECES.find(base)
		_pieces.append([kind, float(src.margins.x), float(src.margins.y), float(src.texture_region_size.x), float(src.texture_region_size.y), r])
	if _atlas == null:
		return false
	_vp = SubViewport.new()
	_vp.name = "GroundWorld3D"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.positional_shadow_atlas_size = 0
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(16, 16)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.5
	_cam.far = 130.0
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.52
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0     # (as far as the camera sees: it stands CAM_BACK away)
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	_vp.add_child(sun)
	sun.look_at_from_position(SUN.normalized() * 10.0, Vector3.ZERO, Vector3.UP)
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = _atlas
	_mat.roughness = 1.0
	_mat.metallic_specular = 0.0
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_stone_mat = StandardMaterial3D.new()
	_stone_mat.vertex_color_use_as_albedo = true
	_stone_mat.vertex_color_is_srgb = true
	_stone_mat.roughness = 1.0
	_stone_mat.metallic_specular = 0.0
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture = _vp.get_texture()
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_spr)
	return true


## A chunk of the world's ground arrived: its tiles ([level, x, y, source] each)
## become a mesh - worked out on a worker, made when it's done (sync).
func add_chunk(id: int, tiles: PackedInt32Array, cells := Rect2i()) -> void:
	_cells[id] = cells
	if _tasks.has(id):
		WorkerThreadPool.wait_for_task_completion(_tasks[id])
		_tasks.erase(id)
	if tiles.is_empty():
		return
	_tasks[id] = WorkerThreadPool.add_task(_work.bind(id, tiles))


## Chunks whose meshes aren't made yet.
func pending() -> int:
	return _tasks.size()


func chunk_count() -> int:
	return _chunks.size()


## The ground's roll at a point of the world (units): one smooth field, the same
## for every tile and chunk - neighbours meet.
static func relief(x: float, z: float) -> float:
	return RELIEF * (0.6 * sin(x * 1.7 + z * 0.9) * cos(z * 1.3 - x * 0.6) + 0.4 * sin(x * 3.9 + 1.3) * sin(z * 4.3 + 0.7))


static func _rnd(a: float, b: float, c: float) -> float:
	return fposmod(sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453, 1.0)


## (worker thread) A chunk's tiles as 3D ones: [[the patches' vertices, normals,
## texture coordinates, triangles], [the stone's vertices, normals, colours, triangles]].
func _work(id: int, tiles: PackedInt32Array) -> void:
	var tv := PackedVector3Array()
	var tn := PackedVector3Array()
	var tu := PackedVector2Array()
	var ti := PackedInt32Array()
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var sc := PackedColorArray()
	var si := PackedInt32Array()
	var aw := float(_atlas.get_width())
	var ah := float(_atlas.get_height())
	var lpx: float = TTILES.LEVEL_PX
	var bank := Color(_stone.r * 0.62, _stone.g * 0.56, _stone.b * 0.5)
	for e in range(0, tiles.size(), 4):
		var pc: Array = _pieces[tiles[e + 3]]
		if pc[3] <= 0.0:
			continue
		var x := float(tiles[e + 1])
		var z := float(tiles[e + 2])
		var lvl: int = tiles[e]
		var y0: float = (lvl - plot_lvl) * LEVEL_H
		var kind := int(pc[0])
		# Where the tile's centre is in its piece's picture, and how the patch tilts (a ramp).
		var ax: float = pc[1] + pc[3] * 0.5
		var ay: float = pc[2] + pc[4] * 0.5
		var d := Vector2i.ZERO
		if kind == BLOCK:
			ay = pc[2] + 32.0
		elif kind == RAMP:
			ax = pc[1] + 66.0
			ay = pc[2] + TTILES.RAMP_TOP + 32.0
			d = TTILES.RAMP_DIRS[int(pc[5])]
		if kind == WATER:
			y0 -= WATER_DROP * LEVEL_H
		# The patch: 3 x 3 points, rolling with the world's relief (not water: a flat sheet).
		var n0 := tv.size()
		for b in 3:
			for a in 3:
				var du := a * 0.5 - 0.5
				var dv := b * 0.5 - 0.5
				var up := clampf(du * d.x + dv * d.y + 0.5, 0.0, 1.0) if kind == RAMP else 0.0
				var wx := x + du
				var wz := z + dv
				var h := 0.0
				var nrm := Vector3.UP
				if kind != WATER:
					h = relief(wx, wz)
					nrm = Vector3(-(relief(wx + 0.05, wz) - h) / 0.05 - d.x * LEVEL_H, 1.0, -(relief(wx, wz + 0.05) - h) / 0.05 - d.y * LEVEL_H).normalized()
				tv.append(Vector3(wx, y0 + up * LEVEL_H + h, wz))
				tn.append(nrm)
				tu.append(Vector2((ax + 64.0 * (du - dv)) / aw, (ay + 32.0 * (du + dv) - up * lpx) / ah))
		for b in 2:
			for a in 2:
				var p := n0 + b * 3 + a
				ti.append(p)
				ti.append(p + 1)
				ti.append(p + 4)
				ti.append(p)
				ti.append(p + 4)
				ti.append(p + 3)
		if kind == WATER:
			continue
		# Its two front sides (toward +x and +z: the ones the camera sees).
		for side in 2:
			var p0 := Vector3(x + 0.5, y0, z - 0.5) if side == 0 else Vector3(x - 0.5, y0, z + 0.5)
			var p1 := Vector3(x + 0.5, y0, z + 0.5)
			var out := Vector3.RIGHT if side == 0 else Vector3.BACK
			var t0 := 0.0
			var t1 := 0.0
			if kind == RAMP:
				t0 = clampf((p0.x - x) * d.x + (p0.z - z) * d.y + 0.5, 0.0, 1.0) * LEVEL_H
				t1 = clampf(0.5 * d.x + 0.5 * d.y + 0.5, 0.0, 1.0) * LEVEL_H
				if t0 <= 0.0 and t1 <= 0.0:
					continue
			p0.y += t0 + relief(p0.x, p0.z)
			p1.y += t1 + relief(p1.x, p1.z)
			if kind == BLOCK:
				_wall(sv, sn, sc, si, p0, p1, y0 - LEVEL_H, out, lvl * 2 + side)
			else:      # (a bank under the edge - or the stone under a ramp's side)
				var bottom := y0 - (BANK * LEVEL_H if kind == FLAT else 0.0)
				_face(sv, sn, sc, si, [p0, p1, Vector3(p1.x, bottom, p1.z), Vector3(p0.x, bottom, p0.z)], out,
					bank if kind == FLAT else _stone.darkened(0.12))
	_lock.lock()
	_done[id] = [[tv, tn, tu, ti], [sv, sn, sc, si]]
	_lock.unlock()


## A flat face of the stone surface: 4 corners, the way it faces, its colour
## (wound to face that way, whatever order they come in).
func _face(sv: PackedVector3Array, sn: PackedVector3Array, sc: PackedColorArray, si: PackedInt32Array, c: Array, out: Vector3, col: Color) -> void:
	var n := sv.size()
	var flip: bool = ((c[1] as Vector3) - (c[0] as Vector3)).cross((c[2] as Vector3) - (c[0] as Vector3)).dot(out) > 0.0
	for p in c:
		sv.append(p)
		sn.append(out)
		sc.append(col)
	for k in ([0, 2, 1, 0, 3, 2] if flip else [0, 1, 2, 0, 2, 3]):
		si.append(n + k)


## A cliff face from the edge p0 - p1 down to `bottom`, facing `out`: the wall
## (dark, the mortar between) and stone blocks in two courses - each a bevelled
## block standing out of it by its own depth, in its own shade of the stone.
func _wall(sv: PackedVector3Array, sn: PackedVector3Array, sc: PackedColorArray, si: PackedInt32Array,
		p0: Vector3, p1: Vector3, bottom: float, out: Vector3, salt: int) -> void:
	var along := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var dir := along.normalized()
	_face(sv, sn, sc, si, [p0, p1, Vector3(p1.x, bottom, p1.z), Vector3(p0.x, bottom, p0.z)], out, Color(_stone.r * 0.42, _stone.g * 0.38, _stone.b * 0.36))
	var rows := [[0.0, 0.5, 1.0], [0.0, 0.27, 0.74, 1.0]]
	for r in 2:
		var cuts: Array = rows[r]
		for k in cuts.size() - 1:
			var ta: float = cuts[k]
			var tb: float = cuts[k + 1]
			var seed_ := p0.x * 3.1 + p0.z * 7.7 + salt * 13.0 + r * 5.0 + k
			var depth := 0.035 + 0.05 * _rnd(seed_, 1.0, 2.0)
			var shade := 0.86 + 0.26 * _rnd(seed_, 3.0, 4.0)
			var col := Color(_stone.r * shade, _stone.g * shade, _stone.b * shade)
			# (the block's base on the wall: its part of the edge, its course - a gap all round)
			var top_a := lerpf(p0.y, p1.y, ta)
			var top_b := lerpf(p0.y, p1.y, tb)
			var a := p0 + along * (ta + 0.015)
			var b := p0 + along * (tb - 0.015)
			var base := [Vector3(a.x, lerpf(top_a, bottom, r * 0.5) - 0.012, a.z), Vector3(b.x, lerpf(top_b, bottom, r * 0.5) - 0.012, b.z),
				Vector3(b.x, lerpf(top_b, bottom, (r + 1) * 0.5) + 0.012, b.z), Vector3(a.x, lerpf(top_a, bottom, (r + 1) * 0.5) + 0.012, a.z)]
			var bev := 0.035
			var w := dir * bev
			var front := [base[0] + w + Vector3(0, -bev, 0) + out * depth, base[1] - w + Vector3(0, -bev, 0) + out * depth,
				base[2] - w + Vector3(0, bev, 0) + out * depth, base[3] + w + Vector3(0, bev, 0) + out * depth]
			_face(sv, sn, sc, si, front, out, col)
			_face(sv, sn, sc, si, [base[0], base[1], front[1], front[0]], (out + Vector3.UP).normalized(), col.lightened(0.06))
			_face(sv, sn, sc, si, [base[3], base[2], front[2], front[3]], (out + Vector3.DOWN).normalized(), col.darkened(0.2))
			_face(sv, sn, sc, si, [base[0], base[3], front[3], front[0]], (out - dir).normalized(), col)
			_face(sv, sn, sc, si, [base[1], base[2], front[2], front[1]], (out + dir).normalized(), col)


## Takes the workers' finished chunks in (`most` a call - the surface calls it
## every frame, more under the landing's veil; `all`: every one, waited for).
func collect(most := MESHES_A_FRAME, all := false) -> void:
	var made := 0
	for id in _tasks.keys():
		var task: int = _tasks[id]
		if not all and (made >= most or not WorkerThreadPool.is_task_completed(task)):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_tasks.erase(id)
		_lock.lock()
		var res: Array = _done.get(id, [])
		_done.erase(id)
		_lock.unlock()
		if _chunks.has(id):
			(_chunks[id] as Node).queue_free()
			_chunks.erase(id)
		if res.is_empty() or (res[0][0] as PackedVector3Array).is_empty():
			continue
		var mesh := ArrayMesh.new()
		var top := []
		top.resize(Mesh.ARRAY_MAX)
		top[Mesh.ARRAY_VERTEX] = res[0][0]
		top[Mesh.ARRAY_NORMAL] = res[0][1]
		top[Mesh.ARRAY_TEX_UV] = res[0][2]
		top[Mesh.ARRAY_INDEX] = res[0][3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top)
		mesh.surface_set_material(0, _mat)
		if not (res[1][0] as PackedVector3Array).is_empty():
			var stone := []
			stone.resize(Mesh.ARRAY_MAX)
			stone[Mesh.ARRAY_VERTEX] = res[1][0]
			stone[Mesh.ARRAY_NORMAL] = res[1][1]
			stone[Mesh.ARRAY_COLOR] = res[1][2]
			stone[Mesh.ARRAY_INDEX] = res[1][3]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, stone)
			mesh.surface_set_material(1, _stone_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		_vp.add_child(mi)
		_chunks[id] = mi
		made += 1
		if _shows(id):          # (a chunk out of sight - the world's made all round you - needn't draw the picture again)
			_dirty = true


## Is a chunk (or might it be: its levels lift it up the screen) in the picture as drawn?
func _shows(id: int) -> bool:
	var r: Rect2i = _cells.get(id, Rect2i())
	if r.size == Vector2i.ZERO or not _drawn.has_area() or surface == null:
		return true
	var g2w: Transform2D = surface._g2w
	var box := Rect2(g2w * Vector2(r.position), Vector2.ZERO)
	for c in [Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)]:
		box = box.expand(g2w * c)
	return box.grow(TTILES.LEVEL_PX * 22.0).intersects(_drawn)


## The ground changed some other way (its atlas took new pictures): drawn again.
func redraw() -> void:
	_dirty = true


## Every frame, just before it's drawn: the 3D
## camera put where the 2D one is (same centre, same zoom), the picture drawn
## again if the view or the ground changed, and laid over the view.
func sync() -> void:
	if _vp == null or surface == null or not is_inside_tree():
		return
	var size: Vector2 = surface.get_viewport_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return
	var xf: Transform2D = surface.get_canvas_transform()
	var inv := xf.affine_inverse()
	var zoom := xf.get_scale().x
	var view := Rect2(inv * Vector2.ZERO, size / zoom)
	# The picture is of more than the window (MARGIN round it) and stays where
	# it is in the world: while the view's inside it - walking on a little -
	# nothing's drawn again (the camera only looks along the ground: the
	# picture just slides). Drawn again when the view leaves it, the zoom
	# changes, or the ground does.
	if _dirty or not is_equal_approx(zoom, _zoom) or not _drawn.encloses(view):
		_dirty = false
		_zoom = zoom
		var full := size + Vector2(MARGIN, MARGIN) * 2.0
		if Vector2(_vp.size) != full:
			_vp.size = Vector2i(full)
		_drawn = view.grow(MARGIN / zoom)
		var g: Vector2 = surface._world_to_grid * _drawn.get_center()
		var target := Vector3(g.x, 0.0, g.y)
		var back := Vector3(cos(ELEV) * 0.7071067811865476, sin(ELEV), cos(ELEV) * 0.7071067811865476)
		_cam.size = full.y / (zoom * PPU)
		_cam.look_at_from_position(target + back * CAM_BACK, target, Vector3.UP)
		_cam.force_update_transform()   # (now: a 3D node's move reaches the renderer a step later else - the picture drawn from where the camera WAS, shown where it is: the ground slid about)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_spr.global_position = _drawn.position
		_spr.scale = Vector2.ONE / zoom


func _exit_tree() -> void:
	for id in _tasks:      # (worker tasks are always waited for)
		WorkerThreadPool.wait_for_task_completion(_tasks[id])
	_tasks.clear()
