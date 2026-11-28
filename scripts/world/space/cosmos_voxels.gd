class_name CosmosVoxels
extends Node3D
## A planet's ground where it's been carved (digging, its caves), as voxels: the ground
## is solid below the heightfield except inside the carves (PlanetShape.
## density), sampled every VOXEL m in CHUNK m cubes on a grid fixed to the
## planet, and meshed by surface nets (a vertex in each voxel the surface
## crosses, at the mean of its crossings; a quad across each crossed edge) -
## pits, trenches, tunnels, overhangs. Only round the carves: a chunk's quads
## away from every carve are left out (the heightfield draws the ground there,
## and isn't drawn inside the carves - the terrain shader's `cuts`), so the two
## meet at the carves' rims. Drawn with the planet's own terrain material.
## Chunks built on workers (a few at once), again when a carve touches them;
## kept within KEEP of you (CosmosPlanet.update_lod: update), made for the
## carves within NEAR.

const CHUNK := 8.0
const VOXEL := 0.5
const N := 16                   # voxels a chunk side
const NEAR := 220.0             # m: the carves round you whose chunks are made
const KEEP := 320.0
const AT_ONCE := 3              # chunks building at once
const DEEP_SEEN := 60.0        # m: a chunk deep under the ground (a cave's) drawn within this
const RIM := 0.9                # m: a quad kept within this of a carve's sphere (past its roughest and the shader's cut: overlapping the heightfield)

var planet: CosmosPlanet
var chunks := {}                # Vector3i -> {mi, task, out, dirty}
var _queue: Array = []          # chunks to build (nearest first)
var _busy := 0
var _at := Vector3(INF, INF, INF)


func _ready() -> void:
	name = "Voxels"


func _exit_tree() -> void:
	for k in chunks:
		if int(chunks[k]["task"]) != -1:
			WorkerThreadPool.wait_for_task_completion(chunks[k]["task"])
			chunks[k]["task"] = -1


## A carve at `local`, `r` wide: every chunk it touches meshed again.
func carve(local: Vector3, r: float) -> void:
	var lo := ((local - Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	var hi := ((local + Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				_want(Vector3i(x, y, z), true)


func _want(key: Vector3i, again: bool) -> void:
	if not chunks.has(key):
		chunks[key] = {"mi": null, "task": -1, "dirty": true}
		_queue.append(key)
	elif again:
		if not chunks[key]["dirty"]:
			chunks[key]["dirty"] = true
			_queue.append(key)


## A few times a second (the planet's LOD visit): the chunks round you - made
## for the carves near, dropped far off.
func update(cam_local: Vector3) -> void:
	if cam_local.distance_to(_at) < 25.0:
		return
	_at = cam_local
	for c in planet.shape.cuts_near(cam_local, NEAR, 100000):
		carve_chunks(c[1], float(c[2]))
	for k in chunks.keys():
		var ch: Dictionary = chunks[k]
		if ((Vector3(k) + Vector3(0.5, 0.5, 0.5)) * CHUNK).distance_to(cam_local) > KEEP and int(ch["task"]) == -1:
			if ch["mi"]:
				(ch["mi"] as Node).queue_free()
			chunks.erase(k)
			_queue.erase(k)


## The chunks round a carve at `local`, `r` wide, all built (none waiting, none
## being made) - its dug ground drawn.
func ready_at(local: Vector3, r: float) -> bool:
	var lo := ((local - Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	var hi := ((local + Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				var ch = chunks.get(Vector3i(x, y, z))
				if ch != null and (int(ch["task"]) != -1 or bool(ch["dirty"])):
					return false
	return true


func carve_chunks(local: Vector3, r: float) -> void:
	var lo := ((local - Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	var hi := ((local + Vector3.ONE * (r + 1.0)) / CHUNK).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				_want(Vector3i(x, y, z), false)


func _process(_delta: float) -> void:
	# Done ones in; new ones started (the nearest the camera first).
	for k in chunks.keys():
		var ch: Dictionary = chunks[k]
		if int(ch["task"]) == -1 or not WorkerThreadPool.is_task_completed(ch["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(ch["task"])
		ch["task"] = -1
		_busy -= 1
		var arr: Array = ch["out"][0] if not (ch["out"] as Array).is_empty() else []
		ch.erase("out")
		if ch["mi"]:
			(ch["mi"] as Node).queue_free()
			ch["mi"] = null
		if not arr.is_empty():
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = planet.material
			mi.position = Vector3(k) * CHUNK
			var mid := mi.position + Vector3.ONE * CHUNK * 0.5
			if planet.radius + planet.shape.height(mid.normalized()) - mid.length() > CHUNK * 1.5:
				mi.visibility_range_end = DEEP_SEEN   # (all of it under the ground - a cave's: drawn only from near)
			add_child(mi)
			if not CosmosPlanet.COMPAT:
				mi.set_instance_shader_parameter("patch_info", Vector4(mi.position.x, mi.position.y, mi.position.z, 0.0))   # (its centre; the dug ground says so in its UVs)
			ch["mi"] = mi
		if ch["dirty"]:
			_queue.append(k)
	planet.cuts_settle()
	if _queue.is_empty() or _busy >= AT_ONCE:
		return
	var cam := get_viewport().get_camera_3d()
	var here: Vector3 = planet.to_local(cam.global_position) if cam else _at
	_queue.sort_custom(func(a, b): return (Vector3(a) * CHUNK).distance_squared_to(here) < (Vector3(b) * CHUNK).distance_squared_to(here))
	while not _queue.is_empty() and _busy < AT_ONCE:
		var k: Vector3i = _queue.pop_front()
		if not chunks.has(k):
			continue
		var ch: Dictionary = chunks[k]
		if int(ch["task"]) != -1:
			continue   # (still building: it goes again when done - dirty)
		ch["dirty"] = false
		var o := Vector3(k) * CHUNK
		var pk := planet.shape.digs_near(o + Vector3.ONE * CHUNK * 0.5, CHUNK + 1.0)
		if pk.is_empty():
			if ch["mi"]:
				(ch["mi"] as Node).queue_free()
			chunks.erase(k)
			continue
		var out := []
		ch["out"] = out
		var shape := planet.shape
		ch["task"] = WorkerThreadPool.add_task(func(): out.append(mesh_chunk(shape, o, pk)), true, "voxel chunk")
		_busy += 1


## Chunks being made (tests: wait for them).
func building() -> bool:
	return _busy > 0 or not _queue.is_empty()


## (Worker) A chunk's mesh arrays (vertices relative to its corner `o`), [] if
## nothing of it's drawn: the density on its grid (and a voxel round it, for
## the seams), the heights from a grid of their own over its patch of ground.
static func mesh_chunk(shape: PlanetShape, o: Vector3, pk: PackedFloat64Array) -> Array:
	var R := shape.radius
	var S := N + 3                   # samples a side: -1 .. N + 1
	# The ground's heights: on the chunk's tangent plane, every half voxel's
	# worth, bilinear between (a cube's few metres of ground: smooth enough).
	var cc := o + Vector3.ONE * CHUNK * 0.5
	var up := cc.normalized()
	var t1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := up.cross(t1)
	var HS := VOXEL
	var half := CHUNK * 0.95 + 1.5
	var HN := int(ceil(half * 2.0 / HS)) + 1
	var hg := PackedFloat32Array()
	hg.resize(HN * HN)
	var base := cc.normalized() * R
	for j in HN:
		for i in HN:
			var q := base + t1 * (-half + i * HS) + t2 * (-half + j * HS)
			hg[j * HN + i] = shape.height(q.normalized())
	var dens := PackedFloat32Array()
	dens.resize(S * S * S)
	for k in S:
		for j in S:
			for i in S:
				var p := o + Vector3(i - 1, j - 1, k - 1) * VOXEL
				var r0 := p.length()
				var d := p / r0 * R
				var a := clampf(((d - base).dot(t1) + half) / HS, 0.0, HN - 1.001)
				var b := clampf(((d - base).dot(t2) + half) / HS, 0.0, HN - 1.001)
				var ia := int(a)
				var ib := int(b)
				var fa := a - ia
				var fb := b - ib
				var h := lerpf(lerpf(hg[ib * HN + ia], hg[ib * HN + ia + 1], fa), lerpf(hg[(ib + 1) * HN + ia], hg[(ib + 1) * HN + ia + 1], fa), fb)
				dens[(k * S + j) * S + i] = shape.carve(p, r0 - (R + h), pk)
	# Surface nets: a vertex in each cell (cells -1 .. N) the surface crosses.
	var C := S - 1
	var vid := PackedInt32Array()
	vid.resize(C * C * C)
	vid.fill(-1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var corner := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for k in C:
		for j in C:
			for i in C:
				var v := PackedFloat32Array()
				v.resize(8)
				var inside := 0
				for q in 8:
					var cq: Vector3i = corner[q]
					v[q] = dens[((k + cq.z) * S + j + cq.y) * S + i + cq.x]
					if v[q] < 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var sum := Vector3.ZERO
				var n := 0
				for e in edges:
					var a: float = v[e[0]]
					var b: float = v[e[1]]
					if (a < 0.0) != (b < 0.0):
						var t := a / (a - b)
						sum += Vector3(corner[e[0]]).lerp(Vector3(corner[e[1]]), t)
						n += 1
				var lp := (Vector3(i - 1, j - 1, k - 1) + sum / n) * VOXEL
				# (its normal: the density's slope across the cell - out to the air)
				var g := Vector3((v[1] + v[3] + v[5] + v[7]) - (v[0] + v[2] + v[4] + v[6]),
					(v[2] + v[3] + v[6] + v[7]) - (v[0] + v[1] + v[4] + v[5]),
					(v[4] + v[5] + v[6] + v[7]) - (v[0] + v[1] + v[2] + v[3]))
				vid[(k * C + j) * C + i] = verts.size()
				verts.append(lp)
				norms.append(g.normalized() if g.length() > 0.0001 else (o + lp).normalized())
				uvs.append(Vector2((o + lp).length() - R, 1.0))   # (y 1: the carved ground - terrain.gdshader shows a vein's ore in it)
	# Quads: across each crossed edge this chunk owns (from samples 0 .. N-1 of it).
	var idx := PackedInt32Array()
	var near_carve := func(p: Vector3) -> bool:
		for c in range(0, pk.size(), 6):
			var m := Vector3(pk[c], pk[c + 1], pk[c + 2]) * (R + pk[c + 4])
			if p.distance_to(m) < pk[c + 3] + RIM:
				return true
		return false
	for k in range(1, N + 1):
		for j in range(1, N + 1):
			for i in range(1, N + 1):
				var d0 := dens[(k * S + j) * S + i]
				for ax in 3:
					var s1: Vector3i = Vector3i(i, j, k) + [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)][ax]
					var d1 := dens[(s1.z * S + s1.y) * S + s1.x]
					if (d0 < 0.0) == (d1 < 0.0):
						continue
					# (the four cells round the edge: the cell index = the sample's, less one along the other two axes)
					var cs: Array
					match ax:
						0: cs = [Vector3i(i, j - 1, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k)]
						1: cs = [Vector3i(i - 1, j, k - 1), Vector3i(i - 1, j, k), Vector3i(i, j, k), Vector3i(i, j, k - 1)]
						_: cs = [Vector3i(i - 1, j - 1, k), Vector3i(i, j - 1, k), Vector3i(i, j, k), Vector3i(i - 1, j, k)]
					var q4 := PackedInt32Array()
					for c: Vector3i in cs:
						q4.append(vid[(c.z * C + c.y) * C + c.x])
					if q4.has(-1):
						continue
					var mid := (verts[q4[0]] + verts[q4[1]] + verts[q4[2]] + verts[q4[3]]) * 0.25
					if not near_carve.call(o + mid):
						continue   # (the ground as it was: the heightfield's)
					var tri := [q4[0], q4[1], q4[2], q4[0], q4[2], q4[3]]
					var fn := (verts[q4[1]] - verts[q4[0]]).cross(verts[q4[2]] - verts[q4[0]])
					if fn.dot(norms[q4[0]] + norms[q4[2]]) > 0.0:
						tri = [q4[0], q4[2], q4[1], q4[0], q4[3], q4[2]]   # (Godot's front faces wind clockwise)
					idx.append_array(tri)
	if idx.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr
