class_name CosmosHull
extends RefCounted
## Procedural ship hulls for the 3D game's other ships (stage 4): a lofted
## fuselage of random sections, swept or straight wings (or none: a freighter's
## cargo pods instead), one to four engines, fins, a canopy - in a hull colour
## and an accent (the empire's), sized by class. Built into `root` (its
## forward is -z); returns the engine nozzles' positions (for their glows).
##   var nozzles := CosmosHull.build(node, rng, "trader", Color.ORANGE)

const SIZE := {"fighter": 1.0, "pirate": 1.1, "patrol": 1.4, "trader": 2.6, "freighter": 4.0}


static func build(root: Node3D, rng: RandomNumberGenerator, kind: String, accent: Color, hull_col := Color(0.75, 0.76, 0.78)) -> Array:
	var s: float = SIZE.get(kind, 1.0) * rng.randf_range(0.85, 1.2)
	var white := CosmosStation._mat(hull_col, 0.4, 0.45)
	var dark := CosmosStation._mat(Color(0.16, 0.17, 0.2), 0.6, 0.45)
	var paint := CosmosStation._mat(accent.darkened(0.15), 0.3, 0.45)
	var glass := CosmosStation._mat(Color(0.05, 0.1, 0.16), 0.9, 0.1, accent * 0.5)
	var length := rng.randf_range(14.0, 22.0)
	var width := rng.randf_range(1.4, 2.6) * (1.6 if kind in ["trader", "freighter"] else 1.0)
	var secs := []
	var n := 6
	for i in n:
		var t := float(i) / (n - 1)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var prof := sin(clampf(t * 1.15, 0.0, 1.0) * PI * 0.92 + 0.12)
		var w := width * prof * rng.randf_range(0.85, 1.1)
		secs.append([z * s, maxf(w, 0.05) * s, maxf(w * rng.randf_range(0.55, 0.9), 0.05) * s, 0.0])
	_add(root, CosmosShip._loft(secs, 10), white)
	_add(root, CosmosShip._loft([[-length * 0.3 * s, 0.6 * s, 0.4 * s, width * 0.5 * s], [-length * 0.12 * s, 0.75 * s, 0.5 * s, width * 0.6 * s],
		[length * 0.02 * s, 0.4 * s, 0.25 * s, width * 0.5 * s]], 8), glass)
	_add(root, CosmosShip._loft([[-length * 0.35 * s, 0.22 * s, 0.07 * s, width * 0.55 * s], [length * 0.4 * s, 0.25 * s, 0.07 * s, width * 0.62 * s]], 6), paint)
	var nozzles: Array = []
	var engines := rng.randi_range(1, 2) * 2 if kind != "fighter" else 2
	if kind in ["trader", "freighter"]:
		# Cargo pods along the flanks.
		for side in [-1.0, 1.0]:
			for k in rng.randi_range(1, 3):
				var pod := MeshInstance3D.new()
				pod.mesh = CosmosStation._box(Vector3(width * 1.1, width * 1.0, length * 0.22) * s)
				pod.material_override = paint if k % 2 == 0 else dark
				pod.position = Vector3(side * width * 1.4 * s, 0, (-0.15 + 0.25 * k) * length * s)
				root.add_child(pod)
	else:
		var sweep := rng.randf_range(0.0, 5.0)
		var span := rng.randf_range(6.0, 10.0)
		for side in [-1.0, 1.0]:
			_add(root, CosmosShip._wing(side, [Vector3(width * 0.8, 0, -2.0) * s, Vector3(width * 0.8, 0, 5.0) * s,
				Vector3(span, rng.randf_range(-0.6, 0.6), 5.5 + sweep * 0.3) * s, Vector3(span - 0.6, 0.0, 2.0 + sweep) * s], 0.28 * s), white)
			_add(root, CosmosShip._wing(side, [Vector3(0.6, 0.8, length * 0.2) * s, Vector3(0.6, 0.8, length * 0.45) * s,
				Vector3(1.6, 2.6, length * 0.5) * s, Vector3(1.4, 2.6, length * 0.4) * s], 0.16 * s), paint)
	for e in engines:
		var side := -1.0 if e % 2 == 0 else 1.0
		var off := float(e / 2)
		var x := side * (width * 0.9 + off * width * 0.8) * s
		var y := -0.3 * s + off * 0.6 * s
		var zt := length * 0.5 * s
		var eng := _add(root, CosmosShip._loft([[0.0, 0.5 * s, 0.5 * s, 0.0], [2.0 * s, 0.75 * s, 0.75 * s, 0.0], [length * 0.35 * s, 0.8 * s, 0.8 * s, 0.0],
			[length * 0.38 * s, 0.65 * s, 0.65 * s, 0.0]], 10), dark)
		eng.position = Vector3(x, y, zt - length * 0.38 * s)
		nozzles.append(Vector3(x, y, zt + 0.2))
	return nozzles


static func _add(root: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)
	return mi
