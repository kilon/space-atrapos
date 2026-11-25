extends RefCounted
## The mesh editor's boolean operations between two parts - union, difference
## (A minus B), intersection, and slice (A cut by B into two parts: what's inside
## B and what's outside) - by Godot's CSG (its manifold-based solver): the two
## meshes as CSGMesh3Ds under a CSGCombiner3D, baked into one mesh. The nodes
## never enter the scene tree, so it runs on a worker thread (roots made ready
## a frame ahead: prepare() / take()). Each surface keeps
## its material (the faces B cuts into A carry B's materials). Both meshes must be
## closed (every edge shared by two faces): an open one is refused, with the reason.
##   MeshBool.run(a_mesh, b_mesh, b_in_a, "difference") -> {meshes: [ArrayMesh], error: ""}

const Shapes := preload("res://scripts/editor/mesh/shapes.gd")
const OPS := ["union", "difference", "intersection", "slice"]
const LABEL := {"union": "Union", "difference": "Difference", "intersection": "Intersection", "slice": "Slice"}


## Why `mesh` can't take part in a boolean ("" - it can).
static func problem(mesh: Mesh, who := "the part") -> String:
	if mesh == null or mesh.get_surface_count() == 0:
		return "%s has no mesh" % who
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return "%s isn't made of triangles" % who
	var open := Shapes.open_edges(mesh, 1e-5)
	if open > 0:
		return "%s isn't closed (%d open edge%s - a hole in its skin, or a flat sheet): a boolean needs a solid" % [who, open, "" if open == 1 else "s"]
	return ""


## Roots for run() on a worker - made here, on the main thread, a frame ahead (`n`: one for
## each pass - slice needs 2). A CSG root queues a deferred rebuild on the main thread the
## first time it's changed; were that queued from the worker, the main thread would rebuild
## it while the worker does - a crash. So each root is changed here first (queued, dirty),
## parented hidden under a holder (so the queued rebuild finds it isn't a root and does
## nothing - and the holder's own rebuild skips it, a hidden child: it stays dirty); then
## take() a frame later frees the holders: dirty roots that queue nothing more.
static func prepare(n: int) -> Array:
	var out := []
	for i in n:
		var holder := CSGCombiner3D.new()
		var r := CSGCombiner3D.new()
		r.operation = CSGShape3D.OPERATION_INTERSECTION
		r.operation = CSGShape3D.OPERATION_UNION
		r.visible = false
		holder.add_child(r)
		out.append([holder, r])
	return out


## The roots prepare() made (call it a frame later - after the queued calls ran), the holders freed.
static func take(prepared: Array) -> Array:
	var roots := []
	for hr in prepared:
		var holder: Node = hr[0]
		holder.remove_child(hr[1])
		holder.free()
		roots.append(hr[1])
	return roots


## The boolean `op` of mesh `a` and mesh `b` (placed by `b_in_a` in a's space): the
## result's meshes in a's space (slice: [inside B, outside B]) - or an error. On a worker:
## pass `roots` (prepare() / take()); without them it runs on the main thread.
static func run(a: Mesh, b: Mesh, b_in_a: Transform3D, op: String, roots := []) -> Dictionary:
	var why := problem(a, "A")
	if why == "":
		why = problem(b, "B")
	if why == "" and not op in OPS:
		why = "no such operation: " + op
	if why != "":
		for r in roots:
			(r as Node).free()
		return {"meshes": [], "error": why}
	var outs := []
	var ops: Array = [op] if op != "slice" else ["intersection", "difference"]
	var err := ""
	for k in ops.size():
		var o: String = ops[k]
		var m := _bake(a, b, b_in_a, o, roots[k] if k < roots.size() else null)
		if err != "":
			continue
		if m == null or m.get_surface_count() == 0:
			if op == "slice":
				err = "B doesn't cut A in two (nothing %s B)" % ("inside" if o == "intersection" else "outside")
			else:
				err = "nothing is left (the parts don't overlap)" if o == "intersection" else "nothing is left"
			continue
		outs.append(m)
	for k in range(ops.size(), roots.size()):
		(roots[k] as Node).free()
	if err != "":
		return {"meshes": [], "error": err}
	return {"meshes": outs, "error": ""}


static func _bake(a: Mesh, b: Mesh, b_in_a: Transform3D, op: String, root: CSGCombiner3D = null) -> ArrayMesh:
	if root == null:
		root = CSGCombiner3D.new()
	# (children parented before they're changed: their changes go to the root - dirty already)
	var ca := CSGMesh3D.new()
	root.add_child(ca)
	ca.mesh = a
	var cb := CSGMesh3D.new()
	root.add_child(cb)
	cb.operation = {"union": CSGShape3D.OPERATION_UNION, "difference": CSGShape3D.OPERATION_SUBTRACTION,
		"intersection": CSGShape3D.OPERATION_INTERSECTION}[op]
	cb.transform = b_in_a
	cb.mesh = b
	root.call("_update_shape")   # (out of the tree: built now, not deferred)
	var baked := root.bake_static_mesh()
	root.free()
	if baked == null:
		return null
	# each surface indexed (shared corners welded) - lighter, and edit mode welds less
	var out := ArrayMesh.new()
	for s in baked.get_surface_count():
		var arr := baked.surface_get_arrays(s)
		if (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.index()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		out.surface_set_material(out.get_surface_count() - 1, baked.surface_get_material(s))
	return out if out.get_surface_count() > 0 else null
