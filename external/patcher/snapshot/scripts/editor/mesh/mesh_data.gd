extends RefCounted
## A mesh's surfaces as plain arrays - what EdgeNet's tracing and meshing read (get_surface_count,
## surface_get_arrays, as an ArrayMesh answers them) - safe to hand to a worker: nothing asked of the
## renderer there (a worker asking it for a mesh's arrays while the main thread waits for the worker
## would never be answered).

var surfaces: Array = []


static func of(m: Mesh) -> RefCounted:
	var d = load("res://scripts/editor/mesh/mesh_data.gd").new()
	for si in m.get_surface_count():
		if m.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
			d.surfaces.append(m.surface_get_arrays(si))
	return d


func get_surface_count() -> int:
	return surfaces.size()


func surface_get_arrays(i: int) -> Array:
	return surfaces[i]
