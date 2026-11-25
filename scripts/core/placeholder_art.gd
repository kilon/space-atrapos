class_name PlaceholderArt
extends RefCounted
## Procedural placeholders: what a sprite looks like before its picture is
## loaded - a simple, low-detail shape for its kind (a ship's hull, a station's
## ring, a beast, a building's block, a figure, a glow...) in the sprite's own
## two main colours, fitted to where its picture is opaque (data/sprites/
## sizes.json: tools/sprite_sizes.py). Made in microseconds (each kind's shape a
## 48 px mask drawn once; a placeholder is two masked blits), so every sprite
## has one long before the pictures load: ProcArt draws them all first, then
## loads the real pictures, each replacing its placeholder in place.

const RES := 48

## [key prefix, kind]: the first that matches.
const KINDS := [
	["ship_", "hull"], ["station_", "station"], ["monster_", "beast"], ["creature_", "beast"],
	["npc_", "figure"], ["tile_", "block"], ["gate_", "ring"],
	["nav_", "diamond"], ["fx_", "glow"], ["sky_", "band"],
]

static var _masks := {}   # kind -> [base, top] (Images, RES x RES, alpha the shape)


static func kind_of(key: String) -> String:
	for k in KINDS:
		if key.begins_with(k[0]):
			return k[1]
	return "slab"


## The placeholder's picture (RES x RES; drawn at the sprite's size). `meta`:
## sizes.json's [w, h, main, shade, x0, y0, x1, y1].
static func make(key: String, meta: Array) -> Image:
	var m: Array = _mask(kind_of(key))
	var x0 := int(RES * float(meta[4]) / 100.0) if meta.size() > 7 else 0
	var y0 := int(RES * float(meta[5]) / 100.0) if meta.size() > 7 else 0
	var x1 := int(ceil(RES * float(meta[6]) / 100.0)) if meta.size() > 7 else RES
	var y1 := int(ceil(RES * float(meta[7]) / 100.0)) if meta.size() > 7 else RES
	var bw := clampi(x1 - x0, 2, RES)
	var bh := clampi(y1 - y0, 2, RES)
	var main := Color.html(str(meta[2])) if meta.size() > 2 else Color(0.6, 0.7, 0.8)
	var shade := Color.html(str(meta[3])) if meta.size() > 3 else main.darkened(0.35)
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	for layer in 2:
		var mask: Image = m[layer]
		if bw != RES or bh != RES:
			mask = mask.duplicate()
			mask.resize(bw, bh, Image.INTERPOLATE_NEAREST)
		var col: Color = shade if layer == 0 else main.lightened(0.12)
		col.a = 0.95
		var solid := Image.create(bw, bh, false, Image.FORMAT_RGBA8)
		solid.fill(col)
		img.blit_rect_mask(solid, mask, Rect2i(0, 0, bw, bh), Vector2i(x0, y0))
	return img


## A kind's two masks (its whole shape; its lit top), drawn once.
static func _mask(kind: String) -> Array:
	if _masks.has(kind):
		return _masks[kind]
	var out := []
	for layer in 2:
		var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
		for y in RES:
			for x in RES:
				if _inside(kind, layer, (x + 0.5) / RES, (y + 0.5) / RES):
					img.set_pixel(x, y, Color(1, 1, 1, 1))
		out.append(img)
	_masks[kind] = out
	return out


## Is (u, v) (0..1 across the sprite) in the shape - its whole (layer 0) or its lit top (1)?
static func _inside(kind: String, layer: int, u: float, v: float) -> bool:
	var p := Vector2(u, v)
	match kind:
		"hull":   # (a pointed hull with swept wings, nose up)
			var body := absf(u - 0.5) < 0.24 * (1.0 - absf(v - 0.55) / 0.55) + 0.05 and v > 0.03 and v < 0.97
			var wings := v > 0.35 and v < 0.85 and absf(u - 0.5) < (v - 0.35) * 0.95
			return (body or wings) if layer == 0 else (absf(u - 0.5) < 0.07 and v > 0.12 and v < 0.75)
		"station":   # (a ring on spokes round a core)
			var d := p.distance_to(Vector2(0.5, 0.5))
			if layer == 1:
				return d < 0.15
			return (d > 0.3 and d < 0.47) or d < 0.17 or (d < 0.47 and (absf(u - 0.5) < 0.04 or absf(v - 0.5) < 0.04))
		"beast":   # (a body, a head, legs)
			var body := pow((u - 0.47) / 0.36, 2) + pow((v - 0.55) / 0.24, 2) < 1.0
			var head := p.distance_to(Vector2(0.8, 0.35)) < 0.15
			var legs := v > 0.6 and v < 0.97 and (absf(u - 0.27) < 0.05 or absf(u - 0.42) < 0.05 or absf(u - 0.58) < 0.05 or absf(u - 0.7) < 0.05)
			if layer == 1:
				return pow((u - 0.45) / 0.28, 2) + pow((v - 0.45) / 0.12, 2) < 1.0 or p.distance_to(Vector2(0.8, 0.33)) < 0.09
			return body or head or legs
		"figure":   # (a head on a robed body)
			var head := p.distance_to(Vector2(0.5, 0.15)) < 0.12
			var robe := v > 0.28 and v < 0.98 and absf(u - 0.5) < 0.16 + (v - 0.28) * 0.18
			return (head or robe) if layer == 0 else head
		"block":   # (an isometric block: a lit top, two walls)
			var top := absf(u - 0.5) / 0.5 + absf(v - 0.27) / 0.25 < 1.0
			var walls := v > 0.27 and v < 0.75 + 0.25 * (1.0 - absf(u - 0.5) / 0.5) and u > 0.0 and u < 1.0
			return (top or walls) if layer == 0 else top
		"ring":
			var d := p.distance_to(Vector2(0.5, 0.5))
			return (d > 0.32 and d < 0.48) if layer == 0 else (d > 0.39 and d < 0.43)
		"diamond":
			var k := absf(u - 0.5) + absf(v - 0.5)
			return k < 0.48 if layer == 0 else k < 0.2
		"glow":
			var d := p.distance_to(Vector2(0.5, 0.5))
			return d < 0.45 if layer == 0 else d < 0.2
		"band":
			return true if layer == 0 else v < 0.35
	# (anything else: a slab with a lit top edge)
	return (u > 0.06 and u < 0.94 and v > 0.06 and v < 0.94) if layer == 0 else (u > 0.06 and u < 0.94 and v > 0.06 and v < 0.3)
