class_name CosmosBoom
extends RefCounted
## A ship blowing up in the 3D game: the effect "explosion" (data/effects.json -
## Fx: a flash, a fireball burning out into smoke, sparks, hull shards glowing as
## they cool, a shockwave and a flash of light), made for a 10 m blast and scaled
## to `size`. Pooled: a dogfight's explosions reuse the same nodes.

const EFFECT := "explosion"


static func at(c: Node, p: Vector3, size: float) -> void:
	if c == null or c.get("world") == null:
		return
	Fx.spawn(EFFECT, c.world, p, size / 10.0)
