class_name LodKit
extends RefCounted
## The game's levels of detail for every kind of 3D asset (the plants have their
## own, finer chain on top of it: FloraLods). Each mesh gets a chain of simpler
## versions of itself - meshoptimizer through ImporterMesh, seams and skin
## weights kept - stored with the mesh's surfaces, so the renderer picks, per
## instance and per frame, the coarsest one whose error stays under a pixel on
## screen (Viewport.mesh_lod_threshold): a far station, a far herd, a far crowd
## drawn with a fraction of their triangles, and the shadow passes too; nothing
## visibly changes - each step is under a pixel.
##
## Meshes are given their chains off the main thread and once each (most are
## shared): the builder hands over the arrays it made the mesh from -
##   LodKit.later(mesh, [arrays...])          # (main thread) chain made on a worker,
##                                            # the mesh's surfaces swapped for ones with it, a few a frame
##   var lods := LodKit.lods(arrays)          # (worker) the chain, for add_surface_from_arrays
##   LodKit.reach(node, size_m)               # visibility range by size: small things stop drawing far out
## LodKit.pump() (each frame, Cosmos) swaps the finished ones in within the frame's budget.

const MERGE_ANGLE := 25.0       # (normals merged under this angle: seams kept above it)
const SPLIT_ANGLE := 60.0
const MIN_TRIS := 64            # (smaller meshes: no chain - nothing to gain)
const PUMP_US := 600            # main-thread time a frame swapping chains in
const REACH_PER_M := 600.0      # a thing stops drawing this many of its sizes away

static var _done := {}          # mesh instance id -> true (has its chain or is being given one)
static var _lock := Mutex.new()  # (meshes are made on workers too)
static var _jobs: Array = []    # [task id, mesh (weak), arrays per surface, out]
static var _quitting := false
static var made := 0            # (chains made: tests, the HUD's debug line)
static var tris_in := 0         # (their full triangles / their coarsest levels' - the saving at a distance)
static var tris_low := 0


## (Worker) The chain for `arrays` (one surface): {screen error: index array, ...}
## as ArrayMesh.add_surface_from_arrays takes it ({} when too small or no gain).
## `fmt`: the surface's extra format flags (custom channels).
static func lods(arrays: Array, fmt := 0) -> Dictionary:
	var ix = arrays[Mesh.ARRAY_INDEX]
	if ix == null or (ix as PackedInt32Array).size() < MIN_TRIS * 3:
		return {}
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", fmt)
	im.generate_lods(MERGE_ANGLE, SPLIT_ANGLE, [])
	var out := {}
	for i in im.get_surface_lod_count(0):
		out[im.get_surface_lod_size(0, i)] = im.get_surface_lod_indices(0, i)
	return out


## The coarsest level's triangles in a chain (or `full` without one).
static func coarsest(chain: Dictionary, full: int) -> int:
	var n := full
	for k in chain:
		n = mini(n, (chain[k] as PackedInt32Array).size() / 3)
	return n


## (Main thread) Give `mesh` its chain: `surfaces` - the arrays each of its surfaces
## was made from (in order) - simplified on a worker, then the surfaces swapped for
## ones with the chain (materials kept) by pump(), a few a frame. Once per mesh.
static func later(mesh: ArrayMesh, surfaces: Array, fmt := 0) -> void:
	if mesh == null or surfaces.is_empty():
		return
	var id := mesh.get_instance_id()
	_lock.lock()
	if _done.has(id):
		_lock.unlock()
		return
	_done[id] = true
	var job := [-1, weakref(mesh), surfaces, [], fmt]
	job[0] = WorkerThreadPool.add_task(_work.bind(job), false, "lod chain")
	_jobs.append(job)
	_lock.unlock()


static func _work(job: Array) -> void:
	var out: Array = job[3]
	for arr: Array in job[2]:
		if _quitting:
			return   # (leaving: a task waited for before it began runs on the waiting thread - nothing to do)
		out.append(lods(arr, int(job[4])))


## (Each frame) Chains made swapped in, within PUMP_US.
static func pump() -> void:
	if _jobs.is_empty():
		return
	var until := Time.get_ticks_usec() + PUMP_US
	var i := 0
	while true:
		_lock.lock()
		if i >= _jobs.size():
			_lock.unlock()
			return
		var job: Array = _jobs[i]
		if not WorkerThreadPool.is_task_completed(job[0]):
			_lock.unlock()
			i += 1
			continue
		if Time.get_ticks_usec() > until:
			_lock.unlock()
			return
		_jobs.remove_at(i)
		_lock.unlock()
		WorkerThreadPool.wait_for_task_completion(job[0])
		var mesh: ArrayMesh = (job[1] as WeakRef).get_ref()
		if mesh == null:
			continue
		_swap(mesh, job[2], job[3], int(job[4]))


static func _swap(mesh: ArrayMesh, surfaces: Array, chains: Array, fmt: int) -> void:
	if mesh.get_surface_count() != surfaces.size() or chains.size() != surfaces.size():
		return   # (changed meanwhile: left as it is)
	var any := false
	for c: Dictionary in chains:
		any = any or not c.is_empty()
	if not any:
		return
	var mats: Array = []
	var names: Array = []
	for s in mesh.get_surface_count():
		mats.append(mesh.surface_get_material(s))
		names.append(mesh.surface_get_name(s))
	var bs := mesh.get_blend_shape_count()
	if bs > 0:
		return   # (blend shapes: kept as they are)
	mesh.clear_surfaces()
	for s in surfaces.size():
		var arr: Array = surfaces[s]
		var full := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] != null else 0
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], chains[s], fmt)
		mesh.surface_set_material(s, mats[s])
		mesh.surface_set_name(s, names[s])
		made += 1
		tris_in += full
		tris_low += coarsest(chains[s], full)


## A SurfaceTool's mesh (indexed), given its chain as later() does.
static func commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	var arr := st.commit_to_arrays()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	later(m, [arr])
	return m


## Wait for every chain under way (leaving the game: no task left in the pool).
static func finish_tasks() -> void:
	_quitting = true
	_lock.lock()
	var jobs := _jobs.duplicate()
	_jobs.clear()
	_lock.unlock()
	for job: Array in jobs:
		WorkerThreadPool.wait_for_task_completion(job[0])
	_quitting = false


## Chains still being made.
static func pending() -> int:
	return _jobs.size()


## A thing `size_m` across stops drawing REACH_PER_M of its sizes away - a pixel or
## two on screen by then: small things go first, big ones are seen far.
## `at_least` / `at_most` bound it (m).
static func reach(gi: GeometryInstance3D, size_m: float, at_least := 60.0, at_most := 40000.0) -> void:
	if gi == null:
		return
	gi.visibility_range_end = clampf(size_m * REACH_PER_M, at_least, at_most)
