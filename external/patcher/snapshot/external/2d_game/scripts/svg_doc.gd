class_name SvgDoc
extends RefCounted
## The SVG Editor's document: a page (width x height) and a list of shapes,
## bottom to top. Shapes are dictionaries:
##   common: type, name, fill (Color or null = none), stroke (Color or null),
##           stroke_width, opacity, xf (Transform2D: shape -> page), hidden, locked
##   rect:    x, y, w, h, r (corner radius)
##   ellipse: cx, cy, rx, ry
##   star:    cx, cy, r1, r2 (inner), n (corners), star (bool), angle
##   text:    x, y (baseline start), text, size, bold
##   path:    subs: [{nodes: [{p, i, o, s}], closed}] - p the node, i / o its
##            in / out handles (equal to p = a sharp, straight join), s smooth
## Writes and reads SVG (rect, circle, ellipse, line, polyline, polygon, path,
## text, g with transforms, fill / stroke / opacity attributes and styles).
## Rendering uses Godot's SVG rasteriser (Image.load_svg_from_string); text
## is drawn as glyph outlines since the rasteriser has no text.

var width := 800.0
var height := 600.0
var background: Variant = null     # page colour in exports (null: transparent)
var shapes: Array = []

const FONT_SIZE := 48.0


static func new_shape(type: String) -> Dictionary:
	var sh := {"type": type, "name": "", "fill": Color(0.35, 0.6, 0.95), "stroke": Color(0.08, 0.1, 0.16),
		"stroke_width": 2.0, "opacity": 1.0, "xf": Transform2D.IDENTITY, "hidden": false, "locked": false}
	match type:
		"rect": sh.merge({"x": 0.0, "y": 0.0, "w": 10.0, "h": 10.0, "r": 0.0}, true)
		"ellipse": sh.merge({"cx": 0.0, "cy": 0.0, "rx": 5.0, "ry": 5.0}, true)
		"star": sh.merge({"cx": 0.0, "cy": 0.0, "r1": 10.0, "r2": 5.0, "n": 5, "star": true, "angle": -PI / 2.0}, true)
		"text": sh.merge({"x": 0.0, "y": 0.0, "text": "Text", "size": FONT_SIZE, "bold": false, "stroke": null}, true)
		"path": sh.merge({"subs": []}, true)
	return sh


static func node(p: Vector2, i = null, o = null, smooth := false) -> Dictionary:
	return {"p": p, "i": p if i == null else i, "o": p if o == null else o, "s": smooth}


# --- Geometry --------------------------------------------------------------------------

## The shape as path subpaths in its own coordinates (rects, ellipses, stars
## and text converted).
static func to_subs(sh: Dictionary) -> Array:
	match sh["type"]:
		"path":
			return sh["subs"]
		"rect":
			var x: float = sh["x"]
			var y: float = sh["y"]
			var w: float = sh["w"]
			var h: float = sh["h"]
			var r: float = clampf(sh.get("r", 0.0), 0.0, minf(absf(w), absf(h)) / 2.0)
			if r <= 0.01:
				return [{"closed": true, "nodes": [node(Vector2(x, y)), node(Vector2(x + w, y)), node(Vector2(x + w, y + h)), node(Vector2(x, y + h))]}]
			var k := r * 0.5523
			var ns := []
			for c in [[Vector2(x + r, y), Vector2(x + w - r, y), Vector2(1, 0)], [Vector2(x + w, y + r), Vector2(x + w, y + h - r), Vector2(0, 1)],
					[Vector2(x + w - r, y + h), Vector2(x + r, y + h), Vector2(-1, 0)], [Vector2(x, y + h - r), Vector2(x, y + r), Vector2(0, -1)]]:
				var d: Vector2 = c[2]
				ns.append(node(c[0], c[0] - d * k, c[0]))
				ns.append(node(c[1], c[1], c[1] + d * k))
			return [{"closed": true, "nodes": ns}]
		"ellipse":
			var c := Vector2(sh["cx"], sh["cy"])
			var rx: float = sh["rx"]
			var ry: float = sh["ry"]
			var kx := rx * 0.5523
			var ky := ry * 0.5523
			return [{"closed": true, "nodes": [
				node(c + Vector2(rx, 0), c + Vector2(rx, -ky), c + Vector2(rx, ky), true),
				node(c + Vector2(0, ry), c + Vector2(kx, ry), c + Vector2(-kx, ry), true),
				node(c + Vector2(-rx, 0), c + Vector2(-rx, ky), c + Vector2(-rx, -ky), true),
				node(c + Vector2(0, -ry), c + Vector2(-kx, -ry), c + Vector2(kx, -ry), true)]}]
		"star":
			var c := Vector2(sh["cx"], sh["cy"])
			var n: int = maxi(3, int(sh["n"]))
			var ns := []
			var steps := n * 2 if sh["star"] else n
			for i in steps:
				var a: float = float(sh["angle"]) + TAU * i / steps
				var r: float = sh["r1"] if (i % 2 == 0 or not sh["star"]) else sh["r2"]
				ns.append(node(c + Vector2.from_angle(a) * r))
			return [{"closed": true, "nodes": ns}]
		"text":
			return text_subs(sh)
	return []


## Text as glyph outlines (the default font), baseline at (x, y).
static func text_subs(sh: Dictionary) -> Array:
	var ts := TextServerManager.get_primary_interface()
	var font: Font = ThemeDB.fallback_font
	var size := int(maxf(1.0, float(sh["size"])))
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, str(sh["text"]), font.get_rids(), size)
	var out := []
	var pen := Vector2(sh["x"], sh["y"])
	for g in ts.shaped_text_get_glyphs(rid):
		var c: Dictionary = ts.font_get_glyph_contours(g["font_rid"], size, g["index"])
		if not c.is_empty():
			var at: Vector2 = pen + g["offset"]
			var start := 0
			for end in c["contours"]:
				var sub := _contour(c["points"], start, end, at)
				if sub.size() > 1:
					out.append({"closed": true, "nodes": sub})
				start = end + 1
		pen.x += float(g["advance"]) * int(g["repeat"])
	ts.free_rid(rid)
	if sh.get("bold", false):
		pass   # (bold is drawn with a stroke in the fill colour, see style)
	return out


## One TrueType / CFF contour (on, conic and cubic points) as path nodes.
static func _contour(pts: PackedVector3Array, a: int, b: int, at: Vector2) -> Array:
	var raw := []
	for k in range(a, b + 1):
		raw.append([Vector2(pts[k].x, pts[k].y) + at, int(pts[k].z)])
	if raw.is_empty():
		return []
	# Start at an on-curve point (or the midpoint of two conic ones).
	var first := -1
	for k in raw.size():
		if raw[k][1] == 1:
			first = k
			break
	if first == -1:
		raw.insert(0, [(raw[0][0] + raw[-1][0]) / 2.0, 1])
		first = 0
	raw = raw.slice(first) + raw.slice(0, first)
	var nodes := [node(raw[0][0])]
	var k := 1
	var n := raw.size()
	while k <= n:
		var cur: Array = raw[k % n]
		if cur[1] == 1:
			nodes.append(node(cur[0]))
			k += 1
		elif cur[1] == 0:   # conic: implied on-points between consecutive conics
			var nxt: Array = raw[(k + 1) % n]
			var end: Vector2 = nxt[0] if nxt[1] == 1 else (cur[0] + nxt[0]) / 2.0
			var p0: Vector2 = nodes[-1]["p"]
			nodes[-1]["o"] = p0 + (cur[0] - p0) * 2.0 / 3.0
			nodes.append(node(end, end + (cur[0] - end) * 2.0 / 3.0))
			k += 2 if nxt[1] == 1 else 1
		else:               # cubic: two control points then an on-point
			var c2: Array = raw[(k + 1) % n]
			var e: Array = raw[(k + 2) % n]
			nodes[-1]["o"] = cur[0]
			nodes.append(node(e[0], c2[0]))
			k += 3
	# The last node repeats the first (closed): merge it.
	if nodes.size() > 1 and (nodes[-1]["p"] as Vector2).is_equal_approx(nodes[0]["p"]):
		nodes[0]["i"] = nodes[-1]["i"]
		nodes.pop_back()
	return nodes


## Points along a cubic segment.
static func flatten_seg(p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2, out: PackedVector2Array, tol := 1.0) -> void:
	if c0.is_equal_approx(p0) and c1.is_equal_approx(p1):
		out.append(p1)
		return
	var l := p0.distance_to(c0) + c0.distance_to(c1) + c1.distance_to(p1)
	var steps := clampi(int(l / maxf(tol * 4.0, 0.5)), 4, 96)
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var u := 1.0 - t
		out.append(p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t)


## Polylines of a shape in page coordinates ([PackedVector2Array, closed]).
static func polylines(sh: Dictionary, tol := 1.0) -> Array:
	var xf: Transform2D = sh["xf"]
	var out := []
	for sub in to_subs(sh):
		var ns: Array = sub["nodes"]
		if ns.is_empty():
			continue
		var pts := PackedVector2Array([ns[0]["p"]])
		for k in range(1, ns.size()):
			flatten_seg(ns[k - 1]["p"], ns[k - 1]["o"], ns[k]["i"], ns[k]["p"], pts, tol)
		if sub["closed"] and ns.size() > 1:
			flatten_seg(ns[-1]["p"], ns[-1]["o"], ns[0]["i"], ns[0]["p"], pts, tol)
		out.append([xf * pts, bool(sub["closed"])])
	return out


## Bounding box in page coordinates (Rect2() for empty shapes).
static func bounds(sh: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for pl in polylines(sh, 2.0):
		for p in pl[0]:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


## True if the page point hits the shape (inside its fill, or on its stroke
## within `slop` page units).
static func hit(sh: Dictionary, p: Vector2, slop: float) -> bool:
	if sh.get("hidden", false):
		return false
	var b := bounds(sh).grow(slop + float(sh.get("stroke_width", 0.0)))
	if not b.has_point(p):
		return false
	var inside := 0
	var reach := slop + (float(sh["stroke_width"]) / 2.0 if sh.get("stroke") != null else 0.0)
	for pl in polylines(sh, 1.5):
		var pts: PackedVector2Array = pl[0]
		if pl[1] and pts.size() >= 3 and Geometry2D.is_point_in_polygon(p, pts):
			inside += 1
		for k in range(1, pts.size()):
			if Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k]).distance_to(p) <= reach:
				return true
	return inside % 2 == 1 and (sh.get("fill") != null or sh["type"] == "text")


# --- Writing SVG ---------------------------------------------------------------------

static func color_hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _num(v: float) -> String:
	var s := "%.3f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


static func _pt(p: Vector2) -> String:
	return _num(p.x) + "," + _num(p.y)


static func style(sh: Dictionary) -> String:
	var s := []
	var f = sh.get("fill")
	s.append("fill:" + (color_hex(f) if f != null else "none"))
	if f != null and f.a < 0.999:
		s.append("fill-opacity:" + _num(f.a))
	var st = sh.get("stroke")
	if sh["type"] == "text" and sh.get("bold", false) and st == null and f != null:
		st = f   # bold text: a thin stroke in its own colour
		s.append("stroke:%s;stroke-width:%s;stroke-linejoin:round" % [color_hex(st), _num(float(sh["size"]) * 0.035)])
	elif st != null and float(sh["stroke_width"]) > 0.0:
		s.append("stroke:" + color_hex(st))
		if st.a < 0.999:
			s.append("stroke-opacity:" + _num(st.a))
		s.append("stroke-width:" + _num(sh["stroke_width"]))
		s.append("stroke-linejoin:round;stroke-linecap:round")
	if float(sh.get("opacity", 1.0)) < 0.999:
		s.append("opacity:" + _num(sh["opacity"]))
	return ";".join(s)


static func transform_attr(xf: Transform2D) -> String:
	if xf.is_equal_approx(Transform2D.IDENTITY):
		return ""
	return ' transform="matrix(%s %s %s %s %s %s)"' % [_num(xf.x.x), _num(xf.x.y), _num(xf.y.x), _num(xf.y.y), _num(xf.origin.x), _num(xf.origin.y)]


static func path_data(subs: Array) -> String:
	var d := []
	for sub in subs:
		var ns: Array = sub["nodes"]
		if ns.is_empty():
			continue
		d.append("M" + _pt(ns[0]["p"]))
		var count := ns.size() + (1 if sub["closed"] else 0)
		for k in range(1, count):
			var a: Dictionary = ns[k - 1]
			var b: Dictionary = ns[k % ns.size()]
			if (a["o"] as Vector2).is_equal_approx(a["p"]) and (b["i"] as Vector2).is_equal_approx(b["p"]):
				if k < ns.size():   # (the closing straight segment is the Z)
					d.append("L" + _pt(b["p"]))
			else:
				d.append("C%s %s %s" % [_pt(a["o"]), _pt(b["i"]), _pt(b["p"])])
		if sub["closed"]:
			d.append("Z")
	return " ".join(d)


## One shape as an SVG element. `for_render`: text as outlines (the rasteriser
## has no text); otherwise a real <text> element (editable elsewhere).
static func shape_svg(sh: Dictionary, for_render: bool) -> String:
	if sh.get("hidden", false) and for_render:
		return ""
	var attrs := ' style="%s"%s' % [style(sh), transform_attr(sh["xf"])]
	if sh.get("name", "") != "":
		attrs += ' id="%s"' % str(sh["name"]).xml_escape(true)
	if sh.get("hidden", false):
		attrs += ' display="none"'
	match sh["type"]:
		"rect":
			var r := ' rx="%s"' % _num(sh["r"]) if float(sh["r"]) > 0.0 else ""
			return '<rect x="%s" y="%s" width="%s" height="%s"%s%s/>' % [_num(sh["x"]), _num(sh["y"]), _num(sh["w"]), _num(sh["h"]), r, attrs]
		"ellipse":
			return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s"%s/>' % [_num(sh["cx"]), _num(sh["cy"]), _num(sh["rx"]), _num(sh["ry"]), attrs]
		"star":
			return '<path d="%s" data-star="%s %s %s %s %d %d %s"%s/>' % [path_data(to_subs(sh)), _num(sh["cx"]), _num(sh["cy"]), _num(sh["r1"]),
				_num(sh["r2"]), int(sh["n"]), 1 if sh["star"] else 0, "%.6f" % float(sh["angle"]), attrs]
		"text":
			if for_render:
				return '<path d="%s"%s/>' % [path_data(text_subs(sh)), attrs]
			return '<text x="%s" y="%s" font-size="%s"%s%s>%s</text>' % [_num(sh["x"]), _num(sh["y"]), _num(sh["size"]),
				' font-weight="bold"' if sh.get("bold", false) else "", attrs, str(sh["text"]).xml_escape()]
		"path":
			return '<path d="%s"%s/>' % [path_data(sh["subs"]), attrs]
	return ""


## The whole document as SVG. `view`: the page area shown (for rendering a
## view of it); `px`: the output size in pixels (default: the page size).
func to_svg(for_render := false, view := Rect2(), px := Vector2.ZERO, with_background := true) -> String:
	if view.size == Vector2.ZERO:
		view = Rect2(0, 0, width, height)
	if px == Vector2.ZERO:
		px = view.size
	var out := ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">' % [
		maxi(1, roundi(px.x)), maxi(1, roundi(px.y)), _num(view.position.x), _num(view.position.y), _num(view.size.x), _num(view.size.y)]]
	if with_background and background != null:
		out.append('<rect id="page-background" x="0" y="0" width="%s" height="%s" style="fill:%s"/>' % [_num(width), _num(height), color_hex(background)])
	for sh in shapes:
		var s := shape_svg(sh, for_render)
		if s != "":
			out.append(s)
	out.append("</svg>")
	return "\n".join(out)


## Rasterises the page (or `area`) at `scale` into an image.
func render(scale := 1.0, area := Rect2(), with_background := true) -> Image:
	if area.size == Vector2.ZERO:
		area = Rect2(0, 0, width, height)
	var img := Image.new()
	var err := img.load_svg_from_string(to_svg(true, area, area.size * scale, with_background), 1.0)
	return img if err == OK else null


# --- Reading SVG ---------------------------------------------------------------------

static func parse_color(v: String) -> Variant:
	v = v.strip_edges()
	if v == "" or v == "none" or v == "transparent":
		return null
	if v.begins_with("url("):
		return Color(0.6, 0.6, 0.6)   # gradients / patterns: not supported, grey
	if v == "currentColor":
		return Color.BLACK
	if v.begins_with("rgb"):
		var inner := v.substr(v.find("(") + 1).trim_suffix(")").split(",")
		var c := []
		for part in inner:
			var t := part.strip_edges()
			c.append(float(t.trim_suffix("%")) / (100.0 if t.ends_with("%") else 255.0))
		return Color(c[0], c[1], c[2], c[3] * 255.0 if c.size() > 3 else 1.0)
	if v.begins_with("#") and v.length() == 4:
		v = "#" + v[1] + v[1] + v[2] + v[2] + v[3] + v[3]
	return Color.from_string(v, Color.BLACK)


static func parse_transform(s: String) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var re := RegEx.create_from_string("(matrix|translate|scale|rotate|skewX|skewY)\\s*\\(([^)]*)\\)")
	for m in re.search_all(s):
		var a := _numbers(m.get_string(2))
		var t := Transform2D.IDENTITY
		match m.get_string(1):
			"matrix":
				if a.size() >= 6:
					t = Transform2D(Vector2(a[0], a[1]), Vector2(a[2], a[3]), Vector2(a[4], a[5]))
			"translate":
				t = Transform2D(0.0, Vector2(a[0] if a.size() > 0 else 0.0, a[1] if a.size() > 1 else 0.0))
			"scale":
				var sx: float = a[0] if a.size() > 0 else 1.0
				t = Transform2D(Vector2(sx, 0), Vector2(0, a[1] if a.size() > 1 else sx), Vector2.ZERO)
			"rotate":
				var r := deg_to_rad(a[0] if a.size() > 0 else 0.0)
				t = Transform2D(r, Vector2.ZERO)
				if a.size() >= 3:
					var c := Vector2(a[1], a[2])
					t = Transform2D(0.0, c) * t * Transform2D(0.0, -c)
			"skewX":
				t = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(a[0])), 1), Vector2.ZERO)
			"skewY":
				t = Transform2D(Vector2(1, tan(deg_to_rad(a[0]))), Vector2(0, 1), Vector2.ZERO)
		xf = xf * t
	return xf


static func _numbers(s: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?")
	for m in re.search_all(s):
		out.append(float(m.get_string()))
	return out


## SVG path data -> subpaths (every command, relative ones and arcs too).
static func parse_path(d: String) -> Array:
	var toks := []   # commands (String) and numbers (float); arc flags split
	var i := 0
	var num_re := RegEx.create_from_string("^[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?")
	var last_cmd := ""
	var arg_i := 0
	while i < d.length():
		var ch := d[i]
		if "MmLlHhVvCcSsQqTtAaZz".contains(ch):
			toks.append(ch)
			last_cmd = ch.to_upper()
			arg_i = 0
			i += 1
		elif ch in " ,\t\n\r":
			i += 1
		else:
			if last_cmd == "A" and (arg_i % 7 == 3 or arg_i % 7 == 4) and ch in "01":
				toks.append(float(ch))
				i += 1
			else:
				var m := num_re.search(d.substr(i, 40))
				if m == null:
					i += 1
					continue
				toks.append(float(m.get_string()))
				i += m.get_string().length()
			arg_i += 1
	var subs := []
	var cur: Dictionary = {}
	var pos := Vector2.ZERO
	var start := Vector2.ZERO
	var last_c := Vector2.ZERO    # last cubic control (for S)
	var last_q := Vector2.ZERO    # last quadratic control (for T)
	var prev := ""
	var k := 0
	var cmd := ""
	while k < toks.size():
		if toks[k] is String:
			cmd = toks[k]
			k += 1
			if cmd in "Zz":
				if not cur.is_empty():
					cur["closed"] = true
					var ns: Array = cur["nodes"]
					if ns.size() > 1 and (ns[-1]["p"] as Vector2).is_equal_approx(ns[0]["p"]):
						ns[0]["i"] = ns[-1]["i"]
						ns.pop_back()
					cur = {}
				pos = start
				prev = "Z"
				continue
		if cmd == "":
			k += 1
			continue
		var rel := cmd == cmd.to_lower()
		var base := pos if rel else Vector2.ZERO
		var C := cmd.to_upper()
		var need: int = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7}.get(C, 0)
		if k + need > toks.size() or need == 0:
			break
		var a := []
		for j in need:
			if not toks[k + j] is float:
				return subs
			a.append(toks[k + j])
		k += need
		if C != "M" and cur.is_empty():
			cur = {"closed": false, "nodes": [node(pos)]}
			subs.append(cur)
		match C:
			"M":
				pos = base + Vector2(a[0], a[1])
				start = pos
				cur = {"closed": false, "nodes": [node(pos)]}
				subs.append(cur)
				cmd = "l" if rel else "L"   # further pairs are line-tos
			"L":
				pos = base + Vector2(a[0], a[1])
				cur["nodes"].append(node(pos))
			"H":
				pos = Vector2((pos.x if rel else 0.0) + a[0], pos.y)
				cur["nodes"].append(node(pos))
			"V":
				pos = Vector2(pos.x, (pos.y if rel else 0.0) + a[0])
				cur["nodes"].append(node(pos))
			"C", "S":
				var c0: Vector2
				var c1: Vector2
				var p: Vector2
				if C == "C":
					c0 = base + Vector2(a[0], a[1])
					c1 = base + Vector2(a[2], a[3])
					p = base + Vector2(a[4], a[5])
				else:
					c0 = pos * 2.0 - last_c if prev in ["C", "S"] else pos
					c1 = base + Vector2(a[0], a[1])
					p = base + Vector2(a[2], a[3])
				cur["nodes"][-1]["o"] = c0
				cur["nodes"].append(node(p, c1))
				last_c = c1
				pos = p
			"Q", "T":
				var q: Vector2
				var p: Vector2
				if C == "Q":
					q = base + Vector2(a[0], a[1])
					p = base + Vector2(a[2], a[3])
				else:
					q = pos * 2.0 - last_q if prev in ["Q", "T"] else pos
					p = base + Vector2(a[0], a[1])
				cur["nodes"][-1]["o"] = pos + (q - pos) * 2.0 / 3.0
				cur["nodes"].append(node(p, p + (q - p) * 2.0 / 3.0))
				last_q = q
				pos = p
			"A":
				var p := base + Vector2(a[5], a[6])
				for seg in _arc(pos, Vector2(absf(a[0]), absf(a[1])), deg_to_rad(a[2]), a[3] != 0.0, a[4] != 0.0, p):
					cur["nodes"][-1]["o"] = seg[0]
					cur["nodes"].append(node(seg[2], seg[1]))
				pos = p
		prev = C
	return subs


## An SVG elliptical arc as cubic segments [[c0, c1, p], ...].
static func _arc(p0: Vector2, r: Vector2, phi: float, large: bool, sweep: bool, p1: Vector2) -> Array:
	if r.x < 1e-6 or r.y < 1e-6 or p0.is_equal_approx(p1):
		return [[p0, p1, p1]]
	var cp := cos(phi)
	var sp := sin(phi)
	var d := (p0 - p1) / 2.0
	var x1 := cp * d.x + sp * d.y
	var y1 := -sp * d.x + cp * d.y
	var lam := (x1 * x1) / (r.x * r.x) + (y1 * y1) / (r.y * r.y)
	if lam > 1.0:
		r *= sqrt(lam)
	var num := r.x * r.x * r.y * r.y - r.x * r.x * y1 * y1 - r.y * r.y * x1 * x1
	var den := r.x * r.x * y1 * y1 + r.y * r.y * x1 * x1
	var co := sqrt(maxf(0.0, num / den)) * (-1.0 if large == sweep else 1.0)
	var cxp := co * r.x * y1 / r.y
	var cyp := -co * r.y * x1 / r.x
	var c := Vector2(cp * cxp - sp * cyp, sp * cxp + cp * cyp) + (p0 + p1) / 2.0
	var a1 := Vector2((x1 - cxp) / r.x, (y1 - cyp) / r.y).angle()
	var da := Vector2((x1 - cxp) / r.x, (y1 - cyp) / r.y).angle_to(Vector2((-x1 - cxp) / r.x, (-y1 - cyp) / r.y))
	if not sweep and da > 0.0:
		da -= TAU
	elif sweep and da < 0.0:
		da += TAU
	var n := maxi(1, ceili(absf(da) / (PI / 2.0)))
	var step := da / n
	var k := 4.0 / 3.0 * tan(step / 4.0)
	var out := []
	var rot := Transform2D(phi, c)
	for s in n:
		var t0 := a1 + step * s
		var t1 := t0 + step
		var e0 := Vector2(cos(t0), sin(t0))
		var e1 := Vector2(cos(t1), sin(t1))
		var q0 := Vector2(e0.x * r.x, e0.y * r.y)
		var q1 := Vector2(e1.x * r.x, e1.y * r.y)
		var d0 := Vector2(-e0.y * r.x, e0.x * r.y) * k
		var d1 := Vector2(-e1.y * r.x, e1.x * r.y) * k
		out.append([rot * (q0 + d0), rot * (q1 - d1), p1 if s == n - 1 else rot * q1])
	return out


static func _style_map(el: Dictionary) -> Dictionary:
	var m := {}
	for k in ["fill", "stroke", "stroke-width", "opacity", "fill-opacity", "stroke-opacity", "display", "font-size", "font-weight"]:
		if el.has(k):
			m[k] = el[k]
	for part in str(el.get("style", "")).split(";"):
		var kv := part.split(":", true, 1)
		if kv.size() == 2:
			m[kv[0].strip_edges()] = kv[1].strip_edges()
	return m


## Reads SVG text into this document (replacing it). Returns false on a parse failure.
func load_svg(text: String) -> bool:
	var xp := XMLParser.new()
	if xp.open_buffer(text.to_utf8_buffer()) != OK:
		return false
	shapes = []
	background = null
	var stack := [{"xf": Transform2D.IDENTITY, "style": {"fill": "#000000"}}]
	var text_shape: Dictionary = {}
	var got_root := false
	while xp.read() == OK:
		match xp.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xp.get_node_name()
				var el := {}
				for a in xp.get_attribute_count():
					el[xp.get_attribute_name(a)] = xp.get_attribute_value(a)
				var parent: Dictionary = stack[-1]
				var st: Dictionary = (parent["style"] as Dictionary).duplicate()
				st.merge(_style_map(el), true)
				var xf: Transform2D = parent["xf"] * parse_transform(str(el.get("transform", "")))
				if tag == "svg" and not got_root:
					got_root = true
					var vb := _numbers(str(el.get("viewBox", "")))
					var w := _numbers(str(el.get("width", "")))
					var h := _numbers(str(el.get("height", "")))
					if vb.size() == 4:
						width = vb[2]
						height = vb[3]
						xf = Transform2D(0.0, Vector2(-vb[0], -vb[1]))
					elif w.size() > 0 and h.size() > 0 and not str(el.get("width")).ends_with("%"):
						width = w[0]
						height = h[0]
				var sh := _element(tag, el, st, xf)
				if str(el.get("id", "")) == "page-background":
					background = sh["fill"]
				elif not sh.is_empty():
					shapes.append(sh)
					if tag == "text":
						text_shape = sh
				if not xp.is_empty():
					stack.append({"xf": xf, "style": st, "tag": tag})
			XMLParser.NODE_TEXT:
				if not text_shape.is_empty() and stack.size() > 1 and str(stack[-1].get("tag", "")) in ["text", "tspan"]:
					text_shape["text"] = str(text_shape["text"]) + xp.get_node_data().strip_edges()
			XMLParser.NODE_ELEMENT_END:
				if xp.get_node_name() == "text":
					text_shape = {}
				if stack.size() > 1:
					stack.pop_back()
	return got_root


func _element(tag: String, el: Dictionary, st: Dictionary, xf: Transform2D) -> Dictionary:
	var f := func(k: String, def := 0.0) -> float:
		var n := _numbers(str(el.get(k, "")))
		return n[0] if n.size() > 0 else def
	var sh: Dictionary
	match tag:
		"rect":
			sh = new_shape("rect")
			sh.merge({"x": f.call("x"), "y": f.call("y"), "w": f.call("width"), "h": f.call("height"), "r": f.call("rx", f.call("ry"))}, true)
		"circle":
			sh = new_shape("ellipse")
			sh.merge({"cx": f.call("cx"), "cy": f.call("cy"), "rx": f.call("r"), "ry": f.call("r")}, true)
		"ellipse":
			sh = new_shape("ellipse")
			sh.merge({"cx": f.call("cx"), "cy": f.call("cy"), "rx": f.call("rx"), "ry": f.call("ry")}, true)
		"line":
			sh = new_shape("path")
			sh["subs"] = [{"closed": false, "nodes": [node(Vector2(f.call("x1"), f.call("y1"))), node(Vector2(f.call("x2"), f.call("y2")))]}]
		"polyline", "polygon":
			sh = new_shape("path")
			var n := _numbers(str(el.get("points", "")))
			var ns := []
			for k in range(0, n.size() - 1, 2):
				ns.append(node(Vector2(n[k], n[k + 1])))
			sh["subs"] = [{"closed": tag == "polygon", "nodes": ns}]
		"path":
			var star := _numbers(str(el.get("data-star", "")))
			if star.size() == 7:
				sh = new_shape("star")
				sh.merge({"cx": star[0], "cy": star[1], "r1": star[2], "r2": star[3], "n": int(star[4]), "star": star[5] != 0.0, "angle": star[6]}, true)
			else:
				sh = new_shape("path")
				sh["subs"] = parse_path(str(el.get("d", "")))
		"text":
			sh = new_shape("text")
			sh.merge({"x": f.call("x"), "y": f.call("y"), "text": "", "size": _numbers(str(st.get("font-size", "16")))[0] if not _numbers(str(st.get("font-size", "16"))).is_empty() else 16.0,
				"bold": str(st.get("font-weight", "")) in ["bold", "700", "800", "900"]}, true)
		_:
			return {}
	sh["xf"] = xf
	sh["name"] = str(el.get("id", ""))
	sh["hidden"] = str(st.get("display", "")) == "none"
	sh["fill"] = parse_color(str(st.get("fill", "#000000")))
	if sh["fill"] != null and st.has("fill-opacity"):
		sh["fill"].a = float(st["fill-opacity"])
	sh["stroke"] = parse_color(str(st.get("stroke", "none")))
	if sh["stroke"] != null and st.has("stroke-opacity"):
		sh["stroke"].a = float(st["stroke-opacity"])
	sh["stroke_width"] = _numbers(str(st.get("stroke-width", "1")))[0] if not _numbers(str(st.get("stroke-width", "1"))).is_empty() else 1.0
	sh["opacity"] = float(st.get("opacity", "1"))
	if tag in ["line", "polyline"] and not st.has("fill"):
		sh["fill"] = null
	return sh
