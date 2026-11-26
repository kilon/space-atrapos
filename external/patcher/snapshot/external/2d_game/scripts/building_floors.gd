class_name BuildingFloors
## Upper floors and staircases for the explorable Minoan buildings.
##
## A building at least 4 x 4 tiles big gets a walkable upper floor one storey
## up: the roof terrace over the whole building, with an upper-storey room on
## the inner tiles (its own walls and open doorways; two rooms on big
## buildings) - the same upper storey its roof shows from outside. A
## staircase inside the ground floor climbs to it: three tiles in a row -
## the approach, the bottom and the top of the stairs - rising toward the
## north-east to a landing tile upstairs; upstairs the two stair tiles are the
## stairwell (you see the stairs below through it).
##
## The pilot's position always stays on the ground plane; upstairs only the
## drawing is lifted one storey (Pilot.lift). PlanetSurface asks these
## functions for walkability and paths on the floor the pilot is on.

const LIFT := float(SurfaceTiles.WALL_H)
## Grid directions a flight can climb toward (screen: up-right / up-left).
const RUN := {"j": Vector2i(0, -1), "i": Vector2i(-1, 0)}


## One building's upper floor: its node (drawn one storey up), walls and
## nav grid, and its staircase.
class Floor extends RefCounted:
	var node: Node2D              # floor tiles and walls, drawn LIFT px up
	var room := Rect2i()          # the upper-storey room (cells)
	var segments: Array = []      # blocking wall lines (doorways open)
	var front_walls: Array = []   # fade when you're in the room
	var doorways: Array = []      # [start, dir] of the open doorways
	var axis := "j"               # the flight climbs toward -j (north-east) or -i (north-west)
	var stair_a := Vector2i()     # approach tile (ground)
	var stair_0 := Vector2i()     # bottom stair tile
	var stair_1 := Vector2i()     # top stair tile
	var landing := Vector2i()     # where the stairs arrive upstairs
	var up_thing: Node2D          # click to climb (ground)
	var down_thing: Node2D        # click to go down (upstairs)
	var solid := PackedVector2Array()   # the staircase's footprint (blocks the ground floor)
	var astar: AStarGrid2D
	var furniture: Array = []     # Furniture pieces upstairs (on node, lifted)
	var blocks: Array = []        # their footprints (ground-plane polygons: block walking upstairs)


## The staircase (ground floor): steps rising from the bottom tile's
## south-west edge to the top tile's north-east edge. Click to climb.
class Stairs extends SurfaceProps.Thing:
	var surface: Node
	var building: RefCounted
	var c0 := Vector2.ZERO        # bottom tile centre
	var axis := "j"
	var approach_at := Vector2.ZERO
	var top_at := Vector2.ZERO    # the top of the steps, ground plane
	var down := false             # the stairwell upstairs (invisible, click to go down)
	var stone := Color(0.93, 0.86, 0.7)
	var trim := Color(0.95, 0.75, 0.3)

	func _ready() -> void:
		title = "Stairs  -  click to go %s" % ("down" if down else "up")
		click_radius = 70.0
		height = 0.0

	func click_center() -> Vector2:
		if down:
			return global_position + Vector2(0, -LIFT)
		return (c0 + top_at) / 2.0 - Vector2(0, LIFT * 0.45)

	func approach() -> Vector2:
		return approach_at

	func interact(s: Node) -> void:
		s.climb(building, not down)

	func _draw() -> void:
		if down:
			return
		BuildingFloors.draw_flight(self, c0 - position, axis, stone, trim)


## Draws a flight of stairs: bottom tile centred at c0 (in ci's coordinates),
## climbing LIFT over two tiles toward axis j (north-east) or i (north-west).
## `drop` lowers everything (the view from upstairs, where the floor is at 0).
static func draw_flight(ci: CanvasItem, c0: Vector2, axis: String, stone: Color, trim: Color, drop := 0.0) -> void:
	var steps := 9
	var D := Vector2(0, drop)
	# The bottom tile's front edge (B0 its nearest corner) and the flight's run.
	var L0 := c0 + (Vector2(-64, 0) if axis == "j" else Vector2(64, 0)) + D
	var B0 := c0 + Vector2(0, 32) + D
	var run := Vector2(128, -64) if axis == "j" else Vector2(-128, -64)
	# The side of the flight (facing the viewer), under the steps.
	var side := PackedVector2Array([B0])
	for k in steps:
		var h := LIFT * (k + 1) / steps
		side.append(B0 + run * (float(k) / steps) - Vector2(0, h))
		side.append(B0 + run * (float(k + 1) / steps) - Vector2(0, h))
	side.append(B0 + run)
	ci.draw_colored_polygon(side, stone.darkened(0.32))
	ci.draw_polyline(side, stone.darkened(0.55), 1.5, true)
	# Treads and risers, top step first (lower steps are nearer).
	for k in range(steps - 1, -1, -1):
		var u0 := float(k) / steps
		var u1 := float(k + 1) / steps
		var h0 := LIFT * k / steps
		var h1 := LIFT * (k + 1) / steps
		var riser := PackedVector2Array([L0 + run * u0 - Vector2(0, h0), B0 + run * u0 - Vector2(0, h0),
			B0 + run * u0 - Vector2(0, h1), L0 + run * u0 - Vector2(0, h1)])
		ci.draw_colored_polygon(riser, stone.darkened(0.15))
		var tread := PackedVector2Array([L0 + run * u0 - Vector2(0, h1), B0 + run * u0 - Vector2(0, h1),
			B0 + run * u1 - Vector2(0, h1), L0 + run * u1 - Vector2(0, h1)])
		ci.draw_colored_polygon(tread, stone.lightened(0.04 * (k % 2)))
		ci.draw_line(tread[0], tread[1], trim, 1.5, true)
	# A red Minoan runner down the middle.
	var mid0 := L0.lerp(B0, 0.38)
	var mid1 := L0.lerp(B0, 0.62)
	for k in steps:
		var u0 := float(k) / steps
		var u1 := float(k + 1) / steps
		var h1 := LIFT * (k + 1) / steps
		ci.draw_colored_polygon(PackedVector2Array([mid0 + run * u0 - Vector2(0, h1), mid1 + run * u0 - Vector2(0, h1),
			mid1 + run * u1 - Vector2(0, h1), mid0 + run * u1 - Vector2(0, h1)]), Color(0.7, 0.12, 0.1, 0.85))


## The stairwell seen from upstairs: the opening in the floor (dark below),
## the flight of steps going down inside it (clipped to the opening), and a
## bronze rim around the edge.
class Stairwell extends Polygon2D:
	var c0 := Vector2.ZERO
	var axis := "j"

	func _ready() -> void:
		color = Color(0.03, 0.03, 0.05)
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var steps := Node2D.new()
		steps.draw.connect(func(): BuildingFloors.draw_flight(steps, c0, axis, Color(0.93, 0.86, 0.7).darkened(0.25), Color(0.95, 0.75, 0.3).darkened(0.2), LIFT))
		add_child(steps)
		# The rim, in the floor's layer (walls in front still hide it), drawn
		# after the floor tiles around it.
		var rim := Line2D.new()
		var low := -INF
		for p in polygon:
			low = maxf(low, p.y)
		rim.position = Vector2(0, low)
		var pts := PackedVector2Array()
		for p in polygon:
			pts.append(p - rim.position)
		rim.points = pts
		rim.closed = true
		rim.width = 4.0
		rim.default_color = Color(0.72, 0.5, 0.22)
		rim.z_index = -1
		get_parent().add_child.call_deferred(rim)


## Big enough for an upper floor: a flight of stairs (four tiles in a row,
## counting the approach and the landing) must fit along one side.
static func can_have(b: RefCounted) -> bool:
	var sz: Vector2i = b.rect.size
	return b.material == "minoan" and MinoanTiles.available() and mini(sz.x, sz.y) >= 3 and maxi(sz.x, sz.y) >= 4


## Adds an upper floor and its stairs to building b (if it's big enough and
## a staircase fits). Call once the building's walls, doors and columns exist.
static func add(s: Node, b: RefCounted) -> void:
	if not can_have(b):
		return
	var r: Rect2i = b.rect
	var room := Rect2i(r.position + Vector2i.ONE, r.size - Vector2i(2, 2))
	var spot := _stair_spot(s, b, room)
	if spot.is_empty():
		return
	var f := Floor.new()
	f.room = room
	f.stair_a = spot[0]
	f.stair_0 = spot[1]
	f.stair_1 = spot[2]
	f.landing = spot[3]
	f.axis = spot[4]
	b.upper = f
	# The staircase (ground floor) and its footprint.
	var c0: Vector2 = s._cell_pos(f.stair_0)
	var c1: Vector2 = s._cell_pos(f.stair_1)
	if f.axis == "j":
		f.solid = PackedVector2Array([c0 + Vector2(-64, 0), c0 + Vector2(0, 32), c1 + Vector2(64, 0), c1 + Vector2(0, -32)])
	else:
		f.solid = PackedVector2Array([c0 + Vector2(64, 0), c0 + Vector2(0, 32), c1 + Vector2(-64, 0), c1 + Vector2(0, -32)])
	var st := Stairs.new()
	st.surface = s
	st.building = b
	st.c0 = c0
	st.axis = f.axis
	st.position = c0 + Vector2(0, 32)        # its nearest corner: sorts in front of what's behind it
	st.approach_at = s._cell_pos(f.stair_a)
	st.top_at = c1 + (Vector2(64, -32) if f.axis == "j" else Vector2(-64, -32)) * 0.5
	s.objects.add_child(st)
	f.up_thing = st
	var dn := Stairs.new()
	dn.down = true
	dn.surface = s
	dn.building = b
	dn.position = s._cell_pos(f.landing)
	dn.approach_at = s._cell_pos(f.landing)
	s.objects.add_child(dn)
	f.down_thing = dn
	# The floor itself, drawn one storey up (above everything on the ground).
	var node := Node2D.new()
	node.y_sort_enabled = true
	node.z_index = 2
	node.position = Vector2(0, -LIFT)
	node.visible = false
	s.objects.add_child(node)
	f.node = node
	# The stairwell: an opening in the floor showing the stairs below.
	var well := Stairwell.new()
	well.polygon = f.solid
	well.c0 = c0
	well.axis = f.axis
	well.z_index = -1
	node.add_child(well)
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			var cell := Vector2i(i, j)
			if cell == f.stair_0 or cell == f.stair_1:
				continue   # the stairwell
			var sp := Sprite2D.new()
			sp.texture = MinoanTiles.floor_tile("minoan", (i * 7 + j * 3) % 3, b.style) if room.has_point(cell) \
				else MinoanTiles.roof_tile((i + j) % 2, b.style)
			MinoanTiles.tag(sp, ["floor", "minoan", (i * 7 + j * 3) % 3, b.style] if room.has_point(cell) else ["roof", (i + j) % 2, b.style])
			sp.position = s._cell_pos(cell)
			sp.z_index = -1
			node.add_child(sp)
	# The upper room's walls: doorways onto the terrace on its front sides,
	# and a dividing wall with a doorway on big buildings.
	var x0 := room.position.x
	var y0 := room.position.y
	var x1 := room.end.x - 1
	var y1 := room.end.y - 1
	var doors := [[Vector2i(x0 + room.size.x / 2, y1), "sw"], [Vector2i(x1, y0 + room.size.y / 2), "se"]]
	for i in range(x0, x1 + 1):
		for j in range(y0, y1 + 1):
			var cell := Vector2i(i, j)
			var sides := []
			if i == x0: sides.append("nw")
			if j == y0: sides.append("ne")
			if i == x1: sides.append("se")
			if j == y1: sides.append("sw")
			for side in sides:
				var kind := "door" if [cell, side] in doors else ("window" if (i + j) % 2 == 0 else "plain")
				_wall(s, b, f, cell, side, kind)
	if room.size.x >= 5:
		var wx := x0 + room.size.x / 2
		for j in range(y0, y1 + 1):
			_wall(s, b, f, Vector2i(wx, j), "nw", "door" if j == y0 + room.size.y / 2 else "plain")


static func _wall(s: Node, b: RefCounted, f: Floor, cell: Vector2i, side: String, kind: String) -> void:
	var c: Vector2 = s._cell_pos(cell)
	var h := SurfaceTiles.WALL_H
	var start: Vector2
	var dir: Vector2
	var orient := "x"
	match side:
		"ne": start = c + Vector2(0, -32); dir = Vector2(64, 32)
		"sw": start = c + Vector2(-64, 0); dir = Vector2(64, 32)
		"nw": start = c + Vector2(-64, 0); dir = Vector2(64, -32); orient = "y"
		"se": start = c + Vector2(0, 32); dir = Vector2(64, -32); orient = "y"
	var front := side == "se" or side == "sw"
	var w: Sprite2D = s._wall_sprite(b, start, orient, kind, s._variant(cell, side + "^"))
	var mid := start + dir * 0.5
	w.position = Vector2(mid.x, c.y + (40.0 if front else -40.0))
	var top_left := start - Vector2(0, h) if orient == "x" else start - Vector2(0, h + 32)
	w.offset = (top_left - w.position) / w.scale.x
	s._slice_wall(w, start, dir, front)
	f.node.add_child(w)
	if front:
		f.front_walls.append(w)
	if kind == "door":
		f.doorways.append([start, dir])
		f.segments.append([start, start + dir * SurfaceTiles.DOOR.x])
		f.segments.append([start + dir * SurfaceTiles.DOOR.y, start + dir])
	else:
		f.segments.append([start, start + dir])


## [approach, bottom, top, landing, axis] tiles for the stairs, or [] if none fit:
## all inside the building, on one floor tile row, not through a wall, a
## doorway or a column, and all four on the same side of the upper room's
## walls; as far from the doors as possible.
static func _stair_spot(s: Node, b: RefCounted, room: Rect2i) -> Array:
	var r: Rect2i = b.rect
	var door_cells: Array = b.spec.get("doors", []).map(func(d): return Vector2i(d[0], d[1]))
	var best := []
	var best_score := -INF
	var crossed := {}
	for axis in RUN:
		for i in range(r.position.x, r.end.x):
			for j in range(r.position.y, r.end.y):
				var a := Vector2i(i, j)
				var step: Vector2i = RUN[axis]
				var c := [a, a + step, a + step * 2, a + step * 3]
				var ok := true
				for k in 4:
					if not r.has_point(c[k]):
						ok = false
				if not ok:
					continue
				# (Each test only while all before it passed - the cheap ones first:
				# the walls' crossings, for every spot, stalled the landing.)
				var inside: bool = room.has_point(c[1])
				for k in range(1, 4):
					if room.has_point(c[k]) != inside:
						ok = false
				if not ok:
					continue
				var at: Array = c.map(func(q): return s._cell_pos(q))
				for k in 3:
					if c[k] in door_cells:
						ok = false
						break
					# Keep clear of every doorway (outer doors and the dividing walls').
					for dr in b.doors:
						if (dr.start + dr.dir * 0.5).distance_to(at[k]) < 60.0:
							ok = false
							break
					if not ok:
						break
					for p in b.pillars:
						if (p as Vector2).distance_to(at[k]) < 50.0:
							ok = false
							break
					if not ok:
						break
				if not ok:
					continue
				for k in 3:
					# (Spots share most of their steps: each pair of cells tested once.)
					var pair := [c[k], c[k + 1]]
					if not crossed.has(pair):
						crossed[pair] = _crosses(at[k], at[k + 1], b.segments)
					if crossed[pair]:
						ok = false
						break
				if not ok:
					continue
				var score := 0.0
				for d in door_cells:
					score += minf(6.0, Vector2(c[1] - d).length())
				# Where the stairwell can be seen from upstairs: inside the upper room
				# best, on the front terrace next; never behind the room's back walls.
				if inside:
					score += 4.0
				else:
					var behind := false
					for k in range(1, 4):
						var cc: Vector2i = c[k]
						if cc.x < room.position.x or cc.y < room.position.y:
							behind = true
					score += -6.0 if behind else 1.0
				if score > best_score:
					best_score = score
					best = c + [axis]
	return best


static func _crosses(a: Vector2, b: Vector2, segments: Array) -> bool:
	for seg in segments:
		if Geometry2D.segment_intersects_segment(a, b, seg[0], seg[1]) != null:
			return true
	return false


# --- Walking upstairs -------------------------------------------------------------------

## Walkable on b's upper floor (ground-plane coordinates): inside the building,
## not over the stairwell, clear of the upper walls.
static func walkable(s: Node, b: RefCounted, world: Vector2, clear := 6.0) -> bool:
	var f: Floor = b.upper
	var g: Vector2 = s._world_to_grid * world
	var m := clear / 45.0
	var r: Rect2i = b.rect
	if g.x < r.position.x - 0.5 + m or g.y < r.position.y - 0.5 + m or g.x > r.end.x - 0.5 - m or g.y > r.end.y - 0.5 - m:
		return false
	for sc in [f.stair_0, f.stair_1]:
		if absf(g.x - sc.x) < 0.5 + m and absf(g.y - sc.y) < 0.5 + m:
			return false
	for seg in f.segments:
		if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, seg[0], seg[1])) < clear * clear:
			return false
	var blocks = f.get("blocks")   # (furniture - absent on floors built before a hot reload)
	for poly in blocks if blocks is Array else []:
		if Geometry2D.is_point_in_polygon(world, poly):
			return false
		for k in poly.size():
			if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, poly[k], poly[(k + 1) % poly.size()])) < clear * clear:
				return false
	return true


static func clear_line(s: Node, b: RefCounted, a: Vector2, c: Vector2, clear := 9.0) -> bool:
	var steps := maxi(1, ceili(a.distance_to(c) / 5.0))
	for k in range(1, steps + 1):
		if not walkable(s, b, a.lerp(c, float(k) / steps), clear):
			return false
	return true


## A route on b's upper floor (its own small nav grid, built on first use).
static func path(s: Node, b: RefCounted, from: Vector2, to: Vector2) -> PackedVector2Array:
	if clear_line(s, b, from, to):
		return PackedVector2Array([to])
	var f: Floor = b.upper
	var S: int = s.NAV_S
	var xg: Transform2D = s.nav_xf_global()   # (whole-map nav coordinates)
	if f.astar == null:
		f.astar = AStarGrid2D.new()
		f.astar.region = Rect2i(b.rect.position * S, b.rect.size * S)
		f.astar.cell_size = Vector2.ONE
		f.astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		f.astar.update()
		for x in range(f.astar.region.position.x, f.astar.region.end.x):
			for y in range(f.astar.region.position.y, f.astar.region.end.y):
				if not walkable(s, b, xg * Vector2(x, y), s.NAV_CLEAR):
					f.astar.set_point_solid(Vector2i(x, y), true)
		# A guaranteed lane through every doorway (as on the ground floor).
		for dw in f.doorways:
			var start: Vector2 = dw[0]
			var dir: Vector2 = dw[1]
			var along := dir.normalized()
			var nrm := along.orthogonal()
			var lo := SurfaceTiles.DOOR.x * dir.length() + 1.5
			var hi := SurfaceTiles.DOOR.y * dir.length() - 1.5
			var c: Vector2i = s.nav_point_global(start + dir * 0.5)
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var q := c + Vector2i(dx, dy)
					if not f.astar.is_in_boundsv(q) or not f.astar.is_point_solid(q):
						continue
					var w: Vector2 = xg * Vector2(q)
					var t := (w - start).dot(along)
					if t > lo and t < hi and absf((w - start).dot(nrm)) < 16.0 and walkable(s, b, w, 5.0):
						f.astar.set_point_solid(q, false)
	var pa := _nearest(f.astar, s.nav_point_global(from))
	var pb := _nearest(f.astar, s.nav_point_global(to))
	var ids := f.astar.get_id_path(pa, pb, true)
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(xg * Vector2(id))
	if not pts.is_empty() and walkable(s, b, to) and clear_line(s, b, pts[-1], to, 6.0):
		pts.append(to)
	return pts


static func _nearest(astar: AStarGrid2D, p: Vector2i) -> Vector2i:
	p = p.clamp(astar.region.position, astar.region.end - Vector2i.ONE)
	if not astar.is_point_solid(p):
		return p
	for rr in range(1, 12):
		for dx in range(-rr, rr + 1):
			for dy in range(-rr, rr + 1):
				var q := p + Vector2i(dx, dy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return p
