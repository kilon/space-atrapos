class_name Surgery
extends Control
## The automaton on the operating table (the Repair Bay's table when the body
## is the automaton): its anatomy in four layers - muscles, veins, nerves,
## skeleton (Parts.LAYERS; the bay's layer buttons choose which is shown) -
## the body lying with its head to the left (AnatomyArt), seen close on the
## part being worked on (part_view). Each of the part's components is a
## structure of one layer at its place on the body (its "site"); its faults
## show there once the scanner has found them (the lens finds the faults of
## the layer shown, where your scanner reads that layer).
##
## Surgery: the muscles are the surface - worked on directly. A fault deeper
## (a vessel, a nerve, a bone) is reached through an INCISION: trace the dashed
## line over its site with the scalpel; the wound is held open (retractors)
## and shows the layers beneath. Then the fault's tool (Parts.fault_info):
##   suture   - a tear in soft tissue: a stitch at each mark; also closes an incision
##   fuser    - a fracture: traced slowly along the break (it heats: the vitals)
##   clamp    - on a bleeding vessel, upstream: the pressure stays down while it holds (not for long)
##   sealant  - the vessel's hole, held while the pressure is low
##   splicer  - a burnt nerve: each fibre to its own colour (the region numbed first - the nerve block - or it shocks)
##   tuner    - a spasm: rate and phase onto the reference wave, and held
##   forceps  - a destroyed structure: its two ties undone, lifted out, a spare grafted in - turned the way the tissue runs - and tied
## Mistakes cost work, never a new fault (RepairBay.mishap). Leaving the part closes its incisions.

var bay: RepairBay
var _mouse := Vector2(-999, -999)
var _down := false
var _still := 0.0
var _speed := 0.0
var _since_move := 0.0
var _drag := {}
var _held_spare := -1      # forceps: a graft in hand, turned (0..3)
var _flash_text := ""
var _flash_col := Color.WHITE
var _flash_t := 0.0
var _flash_at := Vector2.ZERO
var _t := 0.0
var _schem_k := 0
var _view := Rect2()       # the part of the picture shown (its pixels), easing toward _view_to
var _view_to := Rect2()
var _view_pid := ""

## Room round a part's components in its view (along the body, across it), and the least length shown (metres).
const VIEW_MARGIN := Vector2(0.12, 0.09)
const VIEW_MIN := 0.42
## A site's size on screen: this much of the body (metres), within limits (px).
const SITE_M := 0.05
const SITE_MIN := 38.0
const SITE_MAX := 60.0
const CUT_BITS := 10
const STITCHES := 5
## A vessel clamp holds this long, then the tissue needs its blood: this long before the next.
const CLAMP_TIME := 14.0
const CLAMP_REST := 4.0
## Where on a site each kind of fault sits, along the structure (x its size).
const ALONG := {"crack": 0.0, "drift": 0.0, "wreck": 0.0, "leak": 0.5, "burn": 0.0}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(func(): _mouse = Vector2(-999, -999); _down = false; repaint())
	AnatomyArt.warm()
	_make_canvas()


func flash(text: String, col: Color) -> void:
	_flash_text = text
	_flash_col = col
	_flash_t = 2.4
	_flash_at = _mouse if _mouse.x > -900 else size * 0.5


# --- geometry ------------------------------------------------------------------------------------

func area() -> Rect2:
	return Rect2(Vector2(8, 8), size - Vector2(16, 16))


## The part of the picture a body part is seen in: its components' box with
## room round it, in the table's shape.
func part_view(pid: String) -> Rect2:
	var r := Rect2()
	var first := true
	for c in Parts.comps("automaton", pid):
		var p := AnatomyArt.px(float(c[3]), float(c[4]))
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	r = r.grow_individual(VIEW_MARGIN.x * AnatomyArt.PPM, VIEW_MARGIN.y * AnatomyArt.PPM, VIEW_MARGIN.x * AnatomyArt.PPM, VIEW_MARGIN.y * AnatomyArt.PPM)
	var a := area().size
	var asp := a.x / maxf(1.0, a.y)
	var w := maxf(maxf(r.size.x, r.size.y * asp), VIEW_MIN * AnatomyArt.PPM)
	var h := w / asp
	var v := Rect2(r.get_center() - Vector2(w, h) * 0.5, Vector2(w, h))
	var s := AnatomyArt.SIZE
	v.position.x = (s.x - w) * 0.5 if w >= s.x else clampf(v.position.x, 0.0, s.x - w)
	v.position.y = (s.y - h) * 0.5 if h >= s.y else clampf(v.position.y, 0.0, s.y - h)
	return v


## Screen pixels a picture pixel.
func k() -> float:
	return area().size.x / maxf(1.0, _view.size.x)


func to_screen(p: Vector2) -> Vector2:
	return area().position + (p - _view.position) * k()


func to_pic(p: Vector2) -> Vector2:
	return _view.position + (p - area().position) / k()


func comps() -> Array:
	return Parts.comps(bay.which, bay.pid)


## Component i's place on the table.
func site(i: int) -> Vector2:
	var c: Array = comps()[i]
	return to_screen(AnatomyArt.px(float(c[3]), float(c[4])))


func site_r() -> float:
	return clampf(SITE_M * AnatomyArt.PPM * k(), SITE_MIN, SITE_MAX)


## The way component i runs, on the table.
func dir(i: int) -> Vector2:
	return AnatomyArt.axis(float(comps()[i][5]))


## Half the structure's width on the table.
func half_w(i: int) -> float:
	return float(comps()[i][6]) * AnatomyArt.PPM * k()


func layer_i(i: int) -> String:
	return str(comps()[i][2])


func layer_of(f: Dictionary) -> String:
	return layer_i(int(f["comp"]))


func deep(i: int) -> bool:
	return layer_i(i) != "muscles"


func _rng(f: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(f.get("seed", 1)) * 7919 + int(f["id"])
	return r


## Where a fault is (the scanner finds it there).
func anchor(f: Dictionary) -> Vector2:
	var i := int(f["comp"])
	return site(i) + dir(i) * site_r() * float(ALONG.get(str(f["kind"]), 0.0))


## A tear or a fracture: a jagged line across the structure.
func crack_pts(f: Dictionary) -> PackedVector2Array:
	var i := int(f["comp"])
	var r := _rng(f)
	var c := anchor(f)
	var d := dir(i)
	var n := d.orthogonal()
	var ln := clampf(half_w(i) * 1.2, 18.0, site_r() * 0.8)
	var pts := PackedVector2Array()
	for j in 6:
		var u := j / 5.0 * 2.0 - 1.0
		pts.append(c + n * u * ln + d * (r.randf_range(-0.24, 0.24) * ln if j > 0 and j < 5 else 0.0))
	return pts


## ... cut into short pieces (a fracture: each fused on its own).
func crack_bits(f: Dictionary) -> Array:
	var pts := crack_pts(f)
	var out := []
	for i in pts.size() - 1:
		for j in 3:
			out.append([pts[i].lerp(pts[i + 1], j / 3.0), pts[i].lerp(pts[i + 1], (j + 1) / 3.0)])
	return out


## Where a tear's stitches go.
func stitch_pts(f: Dictionary) -> PackedVector2Array:
	var pts := crack_pts(f)
	var out := PackedVector2Array()
	for j in STITCHES:
		var u := (j + 0.5) / STITCHES * (pts.size() - 1)
		out.append(pts[int(u)].lerp(pts[mini(int(u) + 1, pts.size() - 1)], u - int(u)))
	return out


## The incision over component i: its two ends (along the structure).
func cut_line(i: int) -> Array:
	var c := site(i)
	var d := dir(i)
	return [c - d * site_r() * 1.25, c + d * site_r() * 1.25]


func cut_bits(i: int) -> Array:
	var l := cut_line(i)
	var out := []
	for j in CUT_BITS:
		out.append([(l[0] as Vector2).lerp(l[1], j / float(CUT_BITS)), (l[0] as Vector2).lerp(l[1], (j + 1) / float(CUT_BITS))])
	return out


## ... and the stitches that close it.
func close_pts(i: int) -> PackedVector2Array:
	var l := cut_line(i)
	var out := PackedVector2Array()
	for j in STITCHES:
		out.append((l[0] as Vector2).lerp(l[1], (j + 0.5) / STITCHES))
	return out


## The incision's state ({done, open, st}), made on asking.
func cut_of(i: int) -> Dictionary:
	var cuts: Dictionary = bay.op()["cuts"]
	if not cuts.has(i):
		var done := []
		done.resize(CUT_BITS)
		done.fill(false)
		var st := []
		st.resize(STITCHES)
		st.fill(false)
		cuts[i] = {"done": done, "open": false, "st": st, "gape": 0.0}
	return cuts[i]


func is_open(i: int) -> bool:
	var cuts: Dictionary = bay.op()["cuts"]
	return cuts.has(i) and bool(cuts[i]["open"])


## Can a fault be worked on: found, and at the surface or under an open incision?
func reachable(f: Dictionary) -> bool:
	return f.get("found", false) and (not deep(int(f["comp"])) or is_open(int(f["comp"])))


## A burnt nerve: the gap's two ends and the fibres' colours ({l, r, cols, order, mid}).
func burn_geo(f: Dictionary) -> Dictionary:
	var i := int(f["comp"])
	var mid := anchor(f)
	var d := dir(i)
	var n := d.orthogonal()
	var r := _rng(f)
	var palette := [Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.45), Color(0.95, 0.95, 0.95)]
	var cols := []
	while cols.size() < 3:
		var c: Color = palette[r.randi() % palette.size()]
		if not c in cols:
			cols.append(c)
	var order := [0, 1, 2]
	for a in range(2, 0, -1):
		var b := r.randi() % (a + 1)
		var tmp: int = order[a]
		order[a] = order[b]
		order[b] = tmp
	if order == [0, 1, 2]:
		order = [2, 0, 1]
	var l := []
	var rr := []
	for j in 3:
		l.append(mid - d * 30.0 + n * (j - 1) * 16.0)
		rr.append(mid + d * 30.0 + n * (j - 1) * 16.0)
	return {"l": l, "r": rr, "cols": cols, "order": order, "mid": mid}


func leak_pos(f: Dictionary) -> Vector2:
	return anchor(f)


## Where a bleeding vessel is clamped: upstream of the hole.
func clamp_at(f: Dictionary) -> Vector2:
	var i := int(f["comp"])
	return site(i) - dir(i) * site_r() * 0.55


## A destroyed structure: the piece's half sizes (along it, across it), and where its two ties are.
func piece(i: int) -> Vector2:
	return Vector2(site_r() * 0.95, clampf(half_w(i) * 1.35, site_r() * 0.42, site_r() * 0.72))


func tie_pos(f: Dictionary, j: int) -> Vector2:
	var i := int(f["comp"])
	return site(i) + dir(i) * (j * 2 - 1) * (piece(i).x + 12.0)


func notch(f: Dictionary) -> int:
	return _rng(f).randi() % 4


## The tuner's panel of a spasm: [scope rect, rate dial, phase dial].
func cal_panel(f: Dictionary) -> Array:
	var c := anchor(f)
	var w := Vector2(230, 104)
	var r := Rect2(c + Vector2(-w.x * 0.5, -w.y - site_r() - 44.0), w)
	if r.position.y < 6.0:
		r.position.y = c.y + site_r() + 14.0
	r.position.x = clampf(r.position.x, 6.0, size.x - w.x - 6.0)
	r.position.y = clampf(r.position.y, 6.0, size.y - w.y - 70.0)
	return [r, r.position + Vector2(55, w.y + 30), r.position + Vector2(w.x - 55, w.y + 30)]


## A fault's work in progress (made anew if the fault changed kind under the hands).
func fstate(f: Dictionary) -> Dictionary:
	var fs: Dictionary = bay.op()["f"]
	var id := int(f["id"])
	var soft := layer_of(f) != "skeleton"
	var tag := str(f["kind"]) + ("s" if soft else "")
	if not fs.has(id) or str(fs[id].get("kind", "")) != tag:
		var r := _rng(f)
		match str(f["kind"]):
			"crack":
				var done := []
				done.resize(STITCHES if soft else crack_bits(f).size())
				done.fill(false)
				fs[id] = {"done": done}
			"burn":
				fs[id] = {"joined": [false, false, false]}
			"leak":
				fs[id] = {"prog": float(f.get("prog", 0.0)), "w": r.randf_range(1.3, 2.1), "ph": r.randf() * TAU, "clamp": 0.0, "rest": 0.0}
			"drift":
				var f0 := r.randf_range(1.2, 3.2)
				var p0 := r.randf() * TAU
				fs[id] = {"f0": f0, "p0": p0, "f": clampf(f0 + (r.randf_range(0.6, 1.2) * (1 if r.randf() < 0.5 else -1)), 0.6, 4.0),
					"p": wrapf(p0 + r.randf_range(1.2, 2.6), 0.0, TAU), "hold": 0.0}
			"wreck":
				fs[id] = {"stage": "ties", "ties": [true, true], "out": Vector2.ZERO}
		fs[id]["kind"] = tag
	return fs[id]


func pressure(f: Dictionary) -> float:
	var st := fstate(f)
	if float(st["clamp"]) > 0.0:
		return 0.12 + 0.04 * sin(_t * 5.0)   # (clamped: a trickle)
	return 0.5 + 0.5 * sin(_t * float(st["w"]) + float(st["ph"])) * (0.85 + 0.15 * sin(_t * 3.7))


## The part's shown: its view, and what is plain to see at once (a destroyed muscle).
func opened() -> void:
	if bay == null or bay.pid == "" or bay.which != "automaton":
		return
	_view_to = part_view(bay.pid)
	if _view_pid == "" or _view.size.x <= 1.0:
		_view = _view_to
	_view_pid = bay.pid
	_held_spare = -1
	_drag = {}
	for f in bay.faults():
		if f["kind"] == "wreck" and not f.get("found", false) and not deep(int(f["comp"])):
			f["found"] = true


# --- the frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	AnatomyArt.pump()   # (the pictures come in one at a time, whether the table shows or not)
	if not is_visible_in_tree() or bay == null or bay.pid == "" or bay.which != "automaton":
		return
	_t += delta
	if _view_pid != bay.pid:
		opened()
	_view_to = part_view(bay.pid)
	var e := 1.0 - exp(-delta * 7.0)
	_view = Rect2(_view.position.lerp(_view_to.position, e), _view.size.lerp(_view_to.size, e))
	var o := bay.op()
	o["shock"] = maxf(0.0, float(o["shock"]) - delta * 1.6)
	_flash_t = maxf(0.0, _flash_t - delta)
	for i in o["cuts"]:
		var c: Dictionary = o["cuts"][i]
		c["gape"] = move_toward(float(c["gape"]), 1.0 if c["open"] else 0.0, delta * 3.0)
	# Heat: the bone fuser's, a shock's; an open bleed warms it a little; it cools by itself.
	var heat := float(o["heat"])
	for f in bay.faults():
		if f["kind"] == "leak" and reachable(f):
			heat += 1.2 * delta
			var st := fstate(f)
			if float(st["clamp"]) > 0.0:
				st["clamp"] = float(st["clamp"]) - delta
				if float(st["clamp"]) <= 0.0:
					st["clamp"] = 0.0
					st["rest"] = CLAMP_REST
					Sfx.play("space/select", -8.0)
					flash("The clamp's off - the tissue needs its blood", Color(1.0, 0.8, 0.5))
			st["rest"] = maxf(0.0, float(st["rest"]) - delta)
	heat = maxf(0.0, heat - 7.0 * delta)
	if _down and bay.tool == "fuser":
		heat += 13.0 * delta
		if _speed < 6.0:
			_still += delta
			if _still > 0.7:
				heat += 40.0 * delta   # (resting in one place: burning the bone)
		else:
			_still = 0.0
		_fuse()
	o["heat"] = heat
	if heat >= 100.0:
		o["heat"] = 55.0
		_down = false
		for f in bay.faults():   # (the hot bone cracks back: half of each fusing in progress to do again)
			if f["kind"] == "crack" and layer_of(f) == "skeleton" and o["f"].has(int(f["id"])):
				var done: Array = fstate(f)["done"]
				for j in done.size():
					if done[j] and j % 2 == 1:
						done[j] = false
		bay.mishap("Overheated", "The fuser cut out and the hot bone cracked back - let it cool.")
	if _down and bay.tool == "scalpel":
		_cut()
	if _down and bay.tool == "sealant":
		_seal(delta)
	_tune(delta)
	if bay.tool == "scanner":
		_scan(delta)
	_since_move += delta
	if _since_move > 0.08:
		_speed = 0.0
	# (60 a second while it's being worked on; its idle animation - pulses, a bleed - at half that)
	if UI.redraw_due(self, 60.0 if _since_move < 1.5 or _down or not _drag.is_empty() else 30.0):
		repaint()
		bay._vitals.queue_redraw()
		_schem_k = (_schem_k + 1) % 4
		if _schem_k == 0:
			bay._schem.queue_redraw()


# --- tools -----------------------------------------------------------------------------------------

func lens_r() -> float:
	return 105.0 if Parts.deep_scan(bay.items_all()) else 82.0


## Does the scanner see this fault now (the layer shown, a layer it reads - a Deep Scanner: every layer at once)?
func scan_sees(f: Dictionary) -> bool:
	var items := bay.items_all()
	var l := layer_of(f)
	if f["kind"] != "wreck" and not l in Parts.scan_layers(items):
		return false   # (what's destroyed shows to any scanner)
	return l == bay.layer or Parts.deep_scan(items)


func _scan(delta: float) -> void:
	if not Rect2(Vector2.ZERO, size).has_point(_mouse):
		return
	var o := bay.op()
	var r := lens_r()
	for f in bay.faults():
		if f.get("found", false) or not scan_sees(f):
			continue
		if anchor(f).distance_to(_mouse) <= r:
			var id := int(f["id"])
			o["scan"][id] = float(o["scan"].get(id, 0.0)) + delta
			if float(o["scan"][id]) >= 0.45:
				f["found"] = true
				Sfx.play("space/scan_done", -6.0)
				bay.log_line("Found: %s - %s." % [Parts.fault_info(bay.which, bay.pid, f)["name"].to_lower(), str(comps()[int(f["comp"])][1]).to_lower()], "info")
				bay._fill()


## The scalpel drawn along an incision's line (over a found fault's site, deeper than the muscle).
func _cut() -> void:
	for i in _cut_sites():
		var c := cut_of(i)
		if c["open"]:
			continue
		var bits := cut_bits(i)
		var done: Array = c["done"]
		for j in bits.size():
			if done[j]:
				continue
			var m: Vector2 = ((bits[j][0] as Vector2) + (bits[j][1] as Vector2)) * 0.5
			if m.distance_to(_mouse) < 12.0:
				if _speed > 560.0:
					if _flash_t <= 0.0:
						flash("Too fast - the blade skips", Color(1.0, 0.7, 0.3))
					continue
				done[j] = true
				if randf() < 0.3:
					Sfx.play("space/select", -18.0)
		if not done.has(false):
			c["open"] = true
			c["st"].fill(false)
			Sfx.play("surface/locker_open", -10.0)
			bay.log_line("Incision open over the %s." % str(comps()[i][1]).to_lower(), "info")
			bay._fill()
			return


## The components that want an incision: a found fault deeper than the muscle, not yet opened.
func _cut_sites() -> Array:
	var out := []
	for f in bay.faults():
		var i := int(f["comp"])
		if f.get("found", false) and deep(i) and not i in out:
			out.append(i)
	return out


func _fuse() -> void:
	for f in bay.faults():
		if f["kind"] != "crack" or layer_of(f) != "skeleton" or not reachable(f):
			continue
		var st := fstate(f)
		var bits := crack_bits(f)
		var done: Array = st["done"]
		for j in bits.size():
			if done[j]:
				continue
			var m: Vector2 = ((bits[j][0] as Vector2) + (bits[j][1] as Vector2)) * 0.5
			if m.distance_to(_mouse) < 11.0:
				if _speed > 520.0:
					if _flash_t <= 0.0:
						flash("Too fast - the bone doesn't knit", Color(1.0, 0.7, 0.3))
					continue
				done[j] = true
				if randf() < 0.25:
					Sfx.play("space/spark", -16.0)
		if not done.has(false):
			bay.fixed(f)
			return


func _seal(delta: float) -> void:
	for f in bay.faults():
		if f["kind"] != "leak" or not reachable(f):
			continue
		if leak_pos(f).distance_to(_mouse) > 30.0:
			continue
		var st := fstate(f)
		var p := pressure(f)
		if p < 0.42:
			st["prog"] = float(st["prog"]) + delta * 0.5
		elif p > 0.68:
			st["prog"] = maxf(0.0, float(st["prog"]) - delta * 0.7)
			if _flash_t <= 0.0:
				flash("Washed away - clamp the vessel, or wait for the pressure to drop", Color(1.0, 0.6, 0.3))
		f["prog"] = st["prog"]
		if float(st["prog"]) >= 1.0:
			bay.fixed(f)
			return


func _tune(delta: float) -> void:
	if bay.tool != "tuner":
		return
	for f in bay.faults():
		if f["kind"] != "drift" or not reachable(f):
			continue
		var st := fstate(f)
		var ok: bool = absf(float(st["f"]) - float(st["f0"])) < 0.07 and absf(angle_difference(float(st["p"]), float(st["p0"]))) < 0.22
		st["hold"] = float(st["hold"]) + delta if ok else 0.0
		if float(st["hold"]) >= 1.0:
			bay.fixed(f)
			return


# --- input -----------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if bay == null or bay.pid == "":
		return
	var mm := event as InputEventMouseMotion
	if mm:
		var d := mm.position - _mouse
		if _mouse.x > -900:
			_speed = minf(maxf(_speed * 0.6, d.length() / maxf(get_process_delta_time(), 0.004)), 4000.0)
		_since_move = 0.0
		_mouse = mm.position
		if not _drag.is_empty():
			_drag_move(mm)
		if d.length() > 2.0:
			_still = 0.0
		repaint()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	_mouse = mb.position
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _held_spare >= 0 and mb.pressed:
			_held_spare = wrapi(_held_spare + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, 4)
			accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _held_spare >= 0:
			_held_spare = wrapi(_held_spare + 1, 0, 4)
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed:
		_down = true
		_still = 0.0
		_press(mb.position)
	else:
		_down = false
		_release(mb.position)
		_drag = {}


## A fault of `kinds` the tool is for, found but still under closed muscle near `p`: say so.
func _needs_cut(p: Vector2, kinds: Array) -> bool:
	for f in bay.faults():
		if f["kind"] in kinds and f.get("found", false) and not reachable(f) and anchor(f).distance_to(p) < site_r() * 1.3:
			flash("Under the muscle: open it with the scalpel first", Color(1.0, 0.8, 0.5))
			return true
	return false


func _press(p: Vector2) -> void:
	match bay.tool:
		"suture":
			_suture_press(p)
		"clamp":
			for f in bay.faults():
				if f["kind"] != "leak" or not reachable(f) or clamp_at(f).distance_to(p) > 20.0:
					continue
				var st := fstate(f)
				if float(st["clamp"]) > 0.0:
					st["clamp"] = 0.0
					st["rest"] = CLAMP_REST * 0.5
					Sfx.play("space/select", -8.0)
				elif float(st["rest"]) > 0.0:
					flash("Not yet - let the blood back in first", Color(1.0, 0.8, 0.5))
				else:
					st["clamp"] = CLAMP_TIME
					Sfx.play("space/dock", -12.0)
					flash("Clamped - seal it now", Color(0.6, 1.0, 0.7))
				return
			_needs_cut(p, ["leak"])
		"splicer":
			for f in bay.faults():
				if f["kind"] != "burn" or not reachable(f):
					continue
				var g := burn_geo(f)
				var st2 := fstate(f)
				for j in 3:
					if not st2["joined"][j] and (g["l"][j] as Vector2).distance_to(p) < 13.0:
						_drag = {"kind": "strand", "f": int(f["id"]), "k": j}
						if bay.powered():
							_drag = {}
							bay.shock("Shock! The nerve is live - numb the region first (the nerve block).")
						return
			_needs_cut(p, ["burn"])
		"tuner":
			for f in bay.faults():
				if f["kind"] != "drift" or not reachable(f):
					continue
				var panel := cal_panel(f)
				for j in 2:
					if (panel[j + 1] as Vector2).distance_to(p) < 26.0:
						_drag = {"kind": "dial", "f": int(f["id"]), "k": j}
						return
			_needs_cut(p, ["drift"])
		"forceps":
			_forceps_press(p)
		"fuser", "sealant":
			_needs_cut(p, ["crack"] if bay.tool == "fuser" else ["leak"])


## The needle: a stitch at a tear's mark - or at an open incision's (closing it).
func _suture_press(p: Vector2) -> void:
	for f in bay.faults():
		if f["kind"] != "crack" or layer_of(f) == "skeleton" or not reachable(f):
			continue
		var pts := stitch_pts(f)
		var done: Array = fstate(f)["done"]
		for j in pts.size():
			if not done[j] and pts[j].distance_to(p) < 13.0:
				done[j] = true
				Sfx.play("space/select", -10.0)
				if not done.has(false):
					bay.fixed(f)
				return
	var cuts: Dictionary = bay.op()["cuts"]
	for i in cuts.keys():
		var c: Dictionary = cuts[i]
		if not c["open"]:
			continue
		var pts2 := close_pts(i)
		for j in pts2.size():
			if not c["st"][j] and pts2[j].distance_to(p) < 13.0:
				c["st"][j] = true
				Sfx.play("space/select", -10.0)
				if not c["st"].has(false):
					cuts.erase(i)
					bay.log_line("Closed up over the %s." % str(comps()[i][1]).to_lower(), "info")
					bay._fill()
				return
	_needs_cut(p, ["crack"])


func _forceps_press(p: Vector2) -> void:
	for f in bay.faults():
		if f["kind"] != "wreck" or not reachable(f):
			continue
		var st := fstate(f)
		var i := int(f["comp"])
		var c := site(i)
		var reach := piece(i).x
		match str(st["stage"]):
			"ties":
				for j in 2:
					if tie_pos(f, j).distance_to(p) < 16.0 and st["ties"][j]:
						st["ties"][j] = false
						Sfx.play("space/select", -8.0)
						if not st["ties"].has(true):
							st["stage"] = "lift"
						return
				if c.distance_to(p) < reach:
					flash("Undo both ties first", Color(1.0, 0.8, 0.5))
					return
			"lift":
				if c.distance_to(p) < reach:
					_drag = {"kind": "wreck", "f": int(f["id"])}
					return
			"empty":
				if c.distance_to(p) < reach:
					var sid: String = Parts.SPARE_OF[str(comps()[i][0])]
					if _held_spare < 0:
						if bay.count(sid) <= 0:
							flash("No %s - stations sell them" % Items.display_name(sid).to_lower(), Color(1.0, 0.5, 0.4))
							return
						_held_spare = (notch(f) + 1 + randi() % 3) % 4
						Sfx.play("space/pickup", -8.0)
						return
					if _held_spare != notch(f):
						flash("It won't take - turn it the way the tissue runs (wheel / right-click)", Color(1.0, 0.75, 0.4))
						Sfx.play("space/select", -4.0)
						return
					if not bay.use_item(sid):
						_held_spare = -1
						return
					_held_spare = -1
					st["stage"] = "seat"
					st["ties"] = [false, false]
					Sfx.play("space/dock", -10.0)
					flash("Grafted - tie it in", Color(0.6, 1.0, 0.7))
					return
			"seat":
				for j in 2:
					if tie_pos(f, j).distance_to(p) < 16.0 and not st["ties"][j]:
						st["ties"][j] = true
						Sfx.play("space/select", -8.0)
						if not st["ties"].has(false):
							bay.fixed(f)
						return
	_needs_cut(p, ["wreck"])


func _drag_move(mm: InputEventMouseMotion) -> void:
	var f := bay.fault(int(_drag.get("f", -1)))
	if f.is_empty():
		_drag = {}
		return
	match str(_drag["kind"]):
		"dial":
			var st := fstate(f)
			var dy := -mm.relative.y
			if int(_drag["k"]) == 0:
				st["f"] = clampf(float(st["f"]) + dy * 0.008, 0.5, 4.0)
			else:
				st["p"] = wrapf(float(st["p"]) + dy * 0.02, 0.0, TAU)
		"wreck":
			var st2 := fstate(f)
			var i := int(f["comp"])
			st2["out"] = _mouse - site(i)
			if (st2["out"] as Vector2).length() > piece(i).x * 2.4:
				st2["stage"] = "empty"
				st2["out"] = Vector2.ZERO
				_drag = {}
				Sfx.play("space/rock_break", -10.0)
				flash("Out. Click the wound to take a spare", Color(0.8, 0.9, 1.0))


func _release(p: Vector2) -> void:
	if _drag.is_empty():
		return
	var f := bay.fault(int(_drag.get("f", -1)))
	if f.is_empty():
		return
	if str(_drag["kind"]) == "strand":
		var g := burn_geo(f)
		var st := fstate(f)
		var j0 := int(_drag["k"])
		var best := -1   # (the nearest end: they lie close together)
		for j in 3:
			if (g["r"][j] as Vector2).distance_to(p) < 15.0 and (best < 0 or (g["r"][j] as Vector2).distance_to(p) < (g["r"][best] as Vector2).distance_to(p)):
				best = j
		if best < 0:
			return
		if int(g["order"][best]) == j0:
			st["joined"][j0] = true
			Sfx.play("space/spark", -10.0)
			if not st["joined"].has(false):
				bay.fixed(f)
		else:
			flash("Wrong fibre - match the colours", Color(1.0, 0.6, 0.3))
			Sfx.play("space/hazard_zap", -10.0)
			bay.op()["shock"] = 0.5


# --- drawing ---------------------------------------------------------------------------------------

## The table as a picture: painted off screen (a SubViewport) when something
## on it changes - 60 times a second at most - and shown as one rectangle.
## (Drawn straight onto the menu its few hundred commands were sent to the card
## every frame: 590 FPS; this way the frames between repaints cost one quad.)
class Canvas extends Control:
	var painter: Surgery

	func _draw() -> void:
		if painter:
			painter._paint()


var _vp: SubViewport
var _ci: Canvas


func _make_canvas() -> void:
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.size = Vector2i(maxi(8, int(size.x)), maxi(8, int(size.y)))
	add_child(_vp)
	_ci = Canvas.new()
	_ci.painter = self
	_ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ci.mouse_filter = MOUSE_FILTER_IGNORE
	_ci.size = size
	_vp.add_child(_ci)
	resized.connect(func():
		_vp.size = Vector2i(maxi(8, int(size.x)), maxi(8, int(size.y)))
		_ci.size = size
		repaint())


## Something on the table changed: paint it again (this frame).
func repaint() -> void:
	if _ci == null:
		return
	_ci.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _draw() -> void:
	if _vp:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)


func _paint() -> void:
	if bay == null or bay.pid == "" or bay.which != "automaton":
		return
	var a := area()
	RepairArt.table(_ci, Rect2(Vector2.ZERO, size))
	_ci.draw_texture_rect(RepairBay.Table._lamp(), Rect2(size * 0.5 - Vector2(size.x * 0.6, size.y * 0.75), Vector2(size.x * 1.2, size.y * 1.5)), false, Color(0.75, 0.9, 1.0, 0.10))
	var font := ThemeDB.fallback_font
	if not AnatomyArt.ready() or _view.size.x <= 1.0:
		_ci.draw_string(font, size * 0.5 + Vector2(-120, 0), "Preparing the operating table...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.85, 1.0, 0.8))
		return
	var layer := bay.layer
	# The body: its shadow on the table, the skeleton faint under the vessels / nerves, the layer itself.
	var view := AnatomyArt.region(_view)   # (the web build's pictures are half the size)
	var sh := Rect2(a.position + Vector2(5, 7), a.size)
	_ci.draw_texture_rect_region(AnatomyArt.tex("muscles"), sh, view, Color(0, 0, 0, 0.5))
	if layer in ["veins", "nerves"]:
		_ci.draw_texture_rect_region(AnatomyArt.tex("muscles"), a, view, Color(0.10, 0.16, 0.24, 0.5))
		_ci.draw_texture_rect_region(AnatomyArt.tex("skeleton"), a, view, Color(0.75, 0.85, 1.0, 0.26))
	elif layer == "skeleton":
		_ci.draw_texture_rect_region(AnatomyArt.tex("muscles"), a, view, Color(0.10, 0.16, 0.24, 0.42))
	_ci.draw_texture_rect_region(AnatomyArt.tex(layer), a, view)
	var o := bay.op()
	var s := site_r()
	# The sites of this layer: a name by each.
	for i in comps().size():
		if layer_i(i) == layer or is_open(i):
			_draw_label(i, font)
	# Incisions: the line to cut, the cut, the wound held open (and the layers under it).
	var want := _cut_sites()
	for i in comps().size():
		if o["cuts"].has(i) or i in want:
			_draw_cut(i, i in want)
	# The faults found.
	for f in bay.faults():
		if not f.get("found", false):
			continue
		var i2 := int(f["comp"])
		if layer_of(f) != layer and not is_open(i2):
			continue   # (another layer's, and no wound open over it)
		match str(f["kind"]):
			"crack":
				_draw_crack(f)
			"burn":
				_draw_burn(f)
			"leak":
				_draw_leak(f)
			"drift":
				_draw_drift(f)
			"wreck":
				_draw_wreck(f)
	if bay.tool == "scanner":
		_draw_scan()
	_draw_tool()
	if _flash_t > 0.0:
		var al := clampf(_flash_t, 0.0, 1.0)
		var w := font.get_string_size(_flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var at := Vector2(clampf(_flash_at.x - w * 0.5, 8.0, maxf(8.0, size.x - w - 8.0)), clampf(_flash_at.y - 46.0, 22.0, size.y - 10.0))
		_ci.draw_rect(Rect2(at + Vector2(-6, -18), Vector2(w + 12, 24)), Color(0, 0, 0, 0.6 * al))
		_ci.draw_string(font, at, _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(_flash_col, al))
	# The layer shown, in the corner.
	var info: Dictionary = Parts.LAYER_INFO[layer]
	_ci.draw_string(font, Vector2(16, size.y - 14), "%d  %s" % [Parts.LAYERS.find(layer) + 1, str(info["name"]).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(info["color"], 0.9))


func _draw_label(i: int, font: Font) -> void:
	var c := site(i)
	var s := site_r()
	var name := str(comps()[i][1])
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var gap := s * 1.05 + (58.0 if is_open(i) else 20.0)   # (clear of a wound's retractors)
	var at := c + Vector2(-w * 0.5, gap)
	if at.y > size.y - 26.0:
		at.y = c.y - gap + 8.0
	at.x = clampf(at.x, 6.0, maxf(6.0, size.x - w - 6.0))
	_ci.draw_line(c + Vector2(0, s * 0.5 * signf(at.y - c.y)), Vector2(c.x, at.y - (12.0 if at.y > c.y else -4.0)), Color(0.7, 0.85, 1.0, 0.35), 1.0)
	_ci.draw_circle(c, 2.5, Color(0.8, 0.9, 1.0, 0.7))
	_ci.draw_rect(Rect2(at + Vector2(-5, -13), Vector2(w + 10, 18)), Color(0.02, 0.04, 0.06, 0.78))
	_ci.draw_rect(Rect2(at + Vector2(-5, -13), Vector2(w + 10, 18)), Color(0.5, 0.7, 0.9, 0.5), false, 1.0)
	_ci.draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.92, 1.0))


## A circle of unit points (ellipses and patches are this, transformed: one call, not a loop).
static var _unit := PackedVector2Array()
static var _unit_closed := PackedVector2Array()

static func _circle() -> void:
	if _unit.is_empty():
		for j in 28:
			_unit.append(Vector2.from_angle(TAU * j / 28.0))
		_unit_closed = _unit.duplicate()
		_unit_closed.append(_unit[0])


## A patch of a layer's picture as it lies under an ellipse at `c` (half sizes
## `r` along `d` and across), drawn at `at`, turned `turn`.
func _patch(c: Vector2, r: Vector2, d: Vector2, layer: String, col: Color, at := Vector2.INF, turn := 0.0) -> void:
	var tex := AnatomyArt.tex(layer)
	if tex == null:
		return
	_circle()
	if at == Vector2.INF:
		at = c
	var n := d.orthogonal()
	var shape := Transform2D(d * r.x, n * r.y, Vector2.ZERO)
	var pts: PackedVector2Array = (Transform2D(turn, at) * shape) * _unit
	# (the same ellipse where it lies in the picture, as UVs)
	var inv := 1.0 / k()
	var uv := Transform2D(d * r.x * inv / AnatomyArt.SIZE, n * r.y * inv / AnatomyArt.SIZE, (_view.position + (c - area().position) * inv) / AnatomyArt.SIZE)
	_ci.draw_colored_polygon(pts, col, uv * _unit, tex)


func _ellipse(c: Vector2, r: Vector2, d: Vector2, col: Color, width := -1.0) -> void:
	_circle()
	var xf := Transform2D(d * r.x, d.orthogonal() * r.y, c)
	if width < 0.0:
		_ci.draw_colored_polygon(xf * _unit, col)
	else:
		_ci.draw_polyline(xf * _unit_closed, col, width, true)


func _draw_cut(i: int, wanted: bool) -> void:
	var o := bay.op()
	var l := cut_line(i)
	var d := dir(i)
	var n := d.orthogonal()
	var s := site_r()
	var c := site(i)
	if not o["cuts"].has(i):
		# The line to cut: dashed, brighter with the scalpel in hand.
		var al := 0.9 if bay.tool == "scalpel" else 0.4
		for j in 12:
			if j % 2 == 0:
				_ci.draw_line((l[0] as Vector2).lerp(l[1], j / 12.0), (l[0] as Vector2).lerp(l[1], (j + 1) / 12.0), Color(1.0, 0.95, 0.75, al), 2.0, true)
		if bay.tool == "scalpel":
			_ci.draw_circle(l[0], 5.0, Color(1.0, 0.9, 0.6, 0.5 + 0.3 * sin(_t * 5.0)))
		return
	var cut: Dictionary = o["cuts"][i]
	var gape := float(cut["gape"])
	if gape < 0.02:
		# Being cut: the line so far, bleeding a little; the rest still dashed.
		var bits := cut_bits(i)
		for j in bits.size():
			if cut["done"][j]:
				_ci.draw_line(bits[j][0], bits[j][1], Color(0.35, 0.02, 0.02), 4.0, true)
				_ci.draw_line(bits[j][0], bits[j][1], Color(0.95, 0.25, 0.2), 1.5, true)
			elif j % 2 == 0:
				_ci.draw_line(bits[j][0], bits[j][1], Color(1.0, 0.95, 0.75, 0.8), 2.0, true)
		return
	# Held open: the wound's lips, the layers beneath showing through, the retractors.
	var r := Vector2(s * 1.32, s * 0.86 * gape)
	_ellipse(c, r + Vector2(5, 5), d, Color(0.30, 0.03, 0.03, 0.95))
	_ellipse(c, r, d, Color(0.06, 0.01, 0.015))
	var vi := Parts.LAYERS.find(bay.layer)
	for lname in ["skeleton", "nerves", "veins"]:
		if Parts.LAYERS.find(lname) > vi or lname == layer_i(i):
			if Parts.LAYERS.find(lname) <= Parts.LAYERS.find(layer_i(i)) or lname == "skeleton":
				_patch(c, r - Vector2(2, 2), d, lname, Color(1, 1, 1, 0.96 if lname == layer_i(i) else 0.6))
	_ellipse(c, r, d, Color(0.85, 0.32, 0.26, 0.9), 2.0)
	_ellipse(c, r + Vector2(4, 4), d, Color(0.55, 0.08, 0.07, 0.8), 3.0)
	for sg in [-1.0, 1.0]:
		var rp: Vector2 = c + n * sg * (r.y + 14.0)
		_ci.draw_set_transform(rp, n.angle() + PI * 0.5 + (0.0 if sg > 0 else PI), Vector2.ONE)
		var reg := RepairArt.region("retractor")
		if reg.size.x > 0.0:
			_ci.draw_texture_rect_region(RepairArt.texture(RepairArt.ATLAS), Rect2(-21, -24, 42, 49), reg)
		_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Closing it: the stitches' marks with the needle in hand; those placed.
	var pts := close_pts(i)
	for j in pts.size():
		if cut["st"][j]:
			_stitch(pts[j], n, r.y + 6.0)
		elif bay.tool == "suture":
			_ci.draw_circle(pts[j] + n * (r.y + 4.0), 4.0, Color(0.5, 0.8, 1.0, 0.55 + 0.3 * sin(_t * 5.0 + j)))
			_ci.draw_circle(pts[j] - n * (r.y + 4.0), 4.0, Color(0.5, 0.8, 1.0, 0.55 + 0.3 * sin(_t * 5.0 + j)))
			_ci.draw_arc(pts[j], 9.0, 0, TAU, 16, Color(0.5, 0.8, 1.0, 0.5), 1.5, true)


## A stitch across a wound at `p`: the thread from one lip to the other (`n`: across it), knotted.
func _stitch(p: Vector2, n: Vector2, half: float) -> void:
	var a := p - n * half
	var b := p + n * half
	_ci.draw_line(a + Vector2(1, 2), b + Vector2(1, 2), Color(0, 0, 0, 0.4), 3.0, true)
	_ci.draw_line(a, b, Color(0.16, 0.3, 0.62), 3.0, true)
	_ci.draw_line(a, b, Color(0.55, 0.78, 1.0), 1.2, true)
	_ci.draw_circle(a, 2.6, Color(0.1, 0.16, 0.3))
	_ci.draw_circle(b, 2.6, Color(0.1, 0.16, 0.3))
	_ci.draw_circle(b + n.orthogonal() * 3.0, 1.8, Color(0.55, 0.78, 1.0))


func _draw_crack(f: Dictionary) -> void:
	var i := int(f["comp"])
	var d := dir(i)
	var st := fstate(f)
	var done: Array = st["done"]
	var pts := crack_pts(f)
	if layer_of(f) == "skeleton":
		# A fracture: the break dark, its edges chipped pale, blood in the bone round it; fused pieces knit pale.
		RepairArt.glow(_ci, anchor(f), site_r() * 0.8, Color(0.45, 0.02, 0.02, 0.28))
		var bits := crack_bits(f)
		for j in bits.size():
			var a: Vector2 = bits[j][0]
			var b: Vector2 = bits[j][1]
			if done[j]:
				_ci.draw_line(a, b, Color(0.55, 0.5, 0.42), 5.0, true)
				_ci.draw_line(a, b, Color(0.98, 0.95, 0.86), 2.5, true)
				var heat := clampf(1.0 - ((a + b) * 0.5).distance_to(_mouse) / 60.0, 0.0, 1.0) if _down and bay.tool == "fuser" else 0.0
				if heat > 0.0:
					RepairArt.glow(_ci, (a + b) * 0.5, 9.0, Color(0.5, 0.85, 1.0, 0.6 * heat))
			else:
				_ci.draw_line(a + d * 1.5, b + d * 1.5, Color(1.0, 0.96, 0.86, 0.55), 1.5, true)
				_ci.draw_line(a, b, Color(0.05, 0.01, 0.01), 4.0, true)
				_ci.draw_line(a - d * 1.0, b - d * 1.0, Color(0.38, 0.05, 0.04), 1.5, true)
		var r := _rng(f)
		for j in 3:   # splinters
			var at := pts[1 + j] + d * r.randf_range(-7.0, 7.0)
			var sp := Vector2.from_angle(r.randf() * TAU)
			if not done[mini(j * 5, done.size() - 1)]:
				_ci.draw_colored_polygon(PackedVector2Array([at + sp * 5.0, at - sp * 4.0 + sp.orthogonal() * 2.5, at - sp * 4.0 - sp.orthogonal() * 2.5]), Color(0.9, 0.86, 0.74))
		return
	# A tear: the tissue gaping, dark inside, its lips wet; each stitch draws it shut there.
	var n := d.orthogonal()
	var sp2 := stitch_pts(f)
	var shut := float(done.count(true)) / done.size()
	var gap := 9.0 * (1.0 - shut * 0.75)
	RepairArt.glow(_ci, anchor(f), site_r() * 0.7, Color(0.4, 0.0, 0.0, 0.25))
	var up := PackedVector2Array()
	var dn := PackedVector2Array()
	for j in pts.size():
		var u := j / float(pts.size() - 1)
		var w := sin(u * PI) * gap
		# (narrower where a stitch holds it)
		for q in sp2.size():
			if done[q]:
				w *= clampf(pts[j].distance_to(sp2[q]) / 16.0, 0.12, 1.0)
		up.append(pts[j] + d * w)
		dn.append(pts[j] - d * w)
	var poly := up.duplicate()
	for j in range(dn.size() - 1, -1, -1):
		poly.append(dn[j])
	if Geometry2D.triangulate_polygon(poly).size() > 0:
		_ci.draw_colored_polygon(poly, Color(0.16, 0.0, 0.01))
	_ci.draw_polyline(up, Color(0.95, 0.35, 0.28), 2.0, true)
	_ci.draw_polyline(dn, Color(0.55, 0.06, 0.05), 2.0, true)
	_ci.draw_polyline(pts, Color(0.02, 0.0, 0.0, 0.8), 1.5, true)
	for q in sp2.size():
		if done[q]:
			_stitch(sp2[q], d, 10.0)
		elif bay.tool == "suture" and reachable(f):
			_ci.draw_circle(sp2[q] + d * 9.0, 3.5, Color(0.5, 0.8, 1.0, 0.6 + 0.3 * sin(_t * 5.0 + q)))
			_ci.draw_circle(sp2[q] - d * 9.0, 3.5, Color(0.5, 0.8, 1.0, 0.6 + 0.3 * sin(_t * 5.0 + q)))
			_ci.draw_arc(sp2[q], 9.0, 0, TAU, 16, Color(0.5, 0.8, 1.0, 0.5), 1.5, true)
	var _unused := n


func _draw_burn(f: Dictionary) -> void:
	var g := burn_geo(f)
	var st := fstate(f)
	var mid: Vector2 = g["mid"]
	var d := dir(int(f["comp"]))
	# The nerve charred through: soot round the gap, the fibres frayed out of each stump.
	RepairArt.glow(_ci, mid, 44.0, Color(0.02, 0.01, 0.0, 0.85))
	RepairArt.glow(_ci, mid, 22.0, Color(0.0, 0.0, 0.0, 0.9))
	for sg in [-1.0, 1.0]:
		var stump: Vector2 = mid + d * sg * 40.0
		_ci.draw_line(stump + d * sg * 14.0, stump, Color(0.25, 0.2, 0.08), 9.0, true)
		_ci.draw_line(stump + d * sg * 14.0, stump, Color(0.95, 0.8, 0.3), 5.0, true)
		_ci.draw_circle(stump, 5.5, Color(0.12, 0.08, 0.04))
	var live: bool = bay.powered()
	for j in 3:
		var col: Color = g["cols"][j]
		var lp: Vector2 = g["l"][j]
		var rp: Vector2 = g["r"][j]
		var rc: Color = g["cols"][int(g["order"][j])]
		_ci.draw_line(mid - d * 40.0, lp, col.darkened(0.3), 2.5, true)
		_ci.draw_line(mid + d * 40.0, rp, rc.darkened(0.3), 2.5, true)
		if st["joined"][j]:
			var to: Vector2 = g["r"][(g["order"] as Array).find(j)]
			_ci.draw_line(lp + Vector2(2, 3), to + Vector2(2, 3), Color(0, 0, 0, 0.35), 5.0, true)
			_ci.draw_line(lp, to, col.darkened(0.4), 5.0, true)
			_ci.draw_line(lp, to, col, 3.0, true)
			_ci.draw_line(lp, to, col.lightened(0.45), 1.0, true)
		_ci.draw_circle(lp, 6.5, Color(0.08, 0.07, 0.05))
		_ci.draw_circle(lp, 5.0, col)
		_ci.draw_circle(rp, 6.5, Color(0.08, 0.07, 0.05))
		_ci.draw_circle(rp, 5.0, rc)
		_ci.draw_circle(rp, 2.0, Color(0.05, 0.04, 0.03))
	if live and reachable(f):
		for j in 2:
			var a := mid + Vector2(randf_range(-22, 22), randf_range(-16, 16))
			_ci.draw_line(a, a + Vector2(randf_range(-9, 9), randf_range(-9, 9)), Color(0.7, 0.9, 1.0, 0.9), 1.5, true)
	if not _drag.is_empty() and str(_drag.get("kind", "")) == "strand" and int(_drag["f"]) == int(f["id"]):
		var j2 := int(_drag["k"])
		var c2: Color = g["cols"][j2]
		_ci.draw_line(g["l"][j2], _mouse, c2.darkened(0.4), 5.0, true)
		_ci.draw_line(g["l"][j2], _mouse, c2, 3.0, true)


func _draw_leak(f: Dictionary) -> void:
	var at := leak_pos(f)
	var i := int(f["comp"])
	var d := dir(i)
	var n := d.orthogonal()
	var st := fstate(f)
	var p := pressure(f)
	var prog := float(st["prog"])
	# The blood: a pool spreading, a jet with each beat (less the more is sealed).
	RepairArt.glow(_ci, at, 34.0, Color(0.5, 0.0, 0.0, 0.45 * (1.0 - prog * 0.7)))
	RepairArt.glow(_ci, at + n * 10.0, 20.0, Color(0.6, 0.02, 0.02, 0.35 * (1.0 - prog)))
	_ci.draw_circle(at, 4.5, Color(0.1, 0.0, 0.0))
	var jets := int(round(5.0 * p * (1.0 - prog)))
	for j in jets:
		var u := fmod(_t * 1.6 + j * 0.21, 1.0)
		var jp := at + (n * (0.4 + 0.5 * sin(j * 2.1)) - d * 0.3 * cos(j * 1.7)).normalized() * u * 34.0 * p
		_ci.draw_circle(jp, 3.2 * (1.0 - u) + 0.8, Color(0.85, 0.05, 0.04, 0.9 * (1.0 - u)))
	if prog > 0.0:
		_ci.draw_circle(at, 4.0 + prog * 7.0, Color(0.85, 0.95, 1.0, 0.35 + 0.4 * prog))
		_ci.draw_arc(at, 15.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 24, Color(0.6, 1.0, 0.75), 3.0, true)
	if not reachable(f):
		return
	# The pressure at the hole: a small gauge beside it.
	var gc := at + n * 46.0 + d * 10.0
	RepairArt.gauge(_ci, gc, 15.0)
	var ga := PI * 0.75 + PI * 1.5 * p
	_ci.draw_arc(gc, 11.0, PI * 0.75, PI * 0.75 + PI * 1.5 * 0.42, 10, Color(0.4, 1.0, 0.55, 0.8), 2.5, true)
	_ci.draw_arc(gc, 11.0, PI * 0.75 + PI * 1.5 * 0.68, PI * 2.25, 10, Color(1.0, 0.35, 0.25, 0.8), 2.5, true)
	_ci.draw_line(gc, gc + Vector2.from_angle(ga) * 12.0, Color(1.0, 0.92, 0.8), 2.0, true)
	# The clamp's place on the vessel - and the clamp, while it holds.
	var cp := clamp_at(f)
	if float(st["clamp"]) > 0.0:
		var reg := RepairArt.region("vclamp")
		_ci.draw_set_transform(cp, n.angle(), Vector2.ONE)
		if reg.size.x > 0.0:
			_ci.draw_texture_rect_region(RepairArt.texture(RepairArt.ATLAS), Rect2(-28, -18, 56, 36), reg)
		_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_ci.draw_arc(cp, 24.0, -PI * 0.5, -PI * 0.5 + TAU * float(st["clamp"]) / CLAMP_TIME, 24, Color(1.0, 0.85, 0.4, 0.9), 2.5, true)
	elif bay.tool == "clamp":
		var rest := float(st["rest"]) > 0.0
		_ci.draw_arc(cp, 15.0, 0, TAU, 24, Color(1.0, 0.5, 0.4, 0.7) if rest else Color(1.0, 0.85, 0.4, 0.6 + 0.3 * sin(_t * 5.0)), 2.5, true)
		_ci.draw_line(cp - n * 12.0, cp + n * 12.0, Color(1.0, 0.85, 0.4, 0.6), 1.5, true)


func _draw_drift(f: Dictionary) -> void:
	var c := anchor(f)
	var s := site_r()
	var st := fstate(f)
	for j in 3:   # it twitches: rings running out of it, off the beat
		var r := s * (0.55 + 0.2 * j) + 4.0 * sin(_t * float(st["f"]) * 4.0 + j)
		_ci.draw_arc(c, r, 0, TAU, 32, Color(1.0, 0.75, 0.35, 0.5 - j * 0.13), 1.5, true)
	if bay.tool != "tuner" or not reachable(f):
		return
	var panel := cal_panel(f)
	var r2: Rect2 = panel[0]
	_ci.draw_line(c, Vector2(r2.get_center().x, r2.end.y if r2.end.y < c.y else r2.position.y), Color(0.45, 1.0, 0.6, 0.4), 1.0)
	_ci.draw_rect(r2.grow(4), Color(0.16, 0.17, 0.2, 0.97))
	_ci.draw_rect(r2.grow(4), Color(0.4, 0.42, 0.46), false, 1.5)
	_ci.draw_rect(r2, Color(0.01, 0.05, 0.03, 0.97))
	for gx in 7:
		var xx2 := r2.position.x + r2.size.x * (gx + 1) / 8.0
		_ci.draw_line(Vector2(xx2, r2.position.y), Vector2(xx2, r2.end.y), Color(0.45, 1.0, 0.6, 0.08), 1.0)
	_ci.draw_line(Vector2(r2.position.x, r2.get_center().y), Vector2(r2.end.x, r2.get_center().y), Color(0.45, 1.0, 0.6, 0.12), 1.0)
	_ci.draw_rect(r2, Color(0.45, 1.0, 0.6, 0.6), false, 1.0)
	var ref := PackedVector2Array()
	var cur := PackedVector2Array()
	for j in 61:
		var u := j / 60.0
		var xx := r2.position.x + 6 + u * (r2.size.x - 12)
		ref.append(Vector2(xx, r2.get_center().y + sin(u * TAU * float(st["f0"]) + float(st["p0"])) * r2.size.y * 0.32))
		cur.append(Vector2(xx, r2.get_center().y + sin(u * TAU * float(st["f"]) + float(st["p"])) * r2.size.y * 0.32))
	_ci.draw_polyline(ref, Color(1, 1, 1, 0.35), 2.0, true)
	var good := float(st["hold"]) > 0.0
	_ci.draw_polyline(cur, Color(0.4, 1.0, 0.55) if good else Color(1.0, 0.75, 0.3), 2.0, true)
	if good:
		_ci.draw_rect(Rect2(r2.position + Vector2(0, r2.size.y - 4), Vector2(r2.size.x * float(st["hold"]), 4)), Color(0.4, 1.0, 0.55))
	var font := ThemeDB.fallback_font
	for j in 2:
		var dc: Vector2 = panel[j + 1]
		var v: float = (float(st["f"]) - 0.5) / 3.5 * TAU * 0.8 if j == 0 else float(st["p"])
		_ci.draw_arc(dc, 27.0, 0, TAU, 32, Color(0.45, 1.0, 0.6, 0.55), 2.0, true)
		RepairArt.knob(_ci, dc, 24.0)
		var tipv := dc + Vector2.from_angle(v - PI * 0.5) * 21.0
		_ci.draw_line(dc + Vector2.from_angle(v - PI * 0.5) * 8.0, tipv, Color(0.45, 1.0, 0.6), 3.0, true)
		_ci.draw_circle(tipv, 2.5, Color(0.8, 1.0, 0.85))
		_ci.draw_string(font, dc + Vector2(-18, 40), "RATE" if j == 0 else "PHASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 0.75))


func _draw_wreck(f: Dictionary) -> void:
	var i := int(f["comp"])
	var c := site(i)
	var d := dir(i)
	var r := piece(i)
	var layer := layer_i(i)
	var st := fstate(f)
	var stage := str(st["stage"])
	var out: Vector2 = st["out"]
	if stage in ["ties", "lift"]:
		if out.length() > 2.0:
			_cavity(c, r, d, f)
		# The dead piece: charred, cracked, a dull ember in it, a wisp of smoke.
		_ellipse(c + out, r + Vector2(3, 3), d, Color(0.0, 0.0, 0.0, 0.55))
		_patch(c, r, d, layer, Color(0.50, 0.40, 0.36), c + out)
		_ellipse(c + out, r, d, Color(0.05, 0.03, 0.02, 0.30))
		_ellipse(c + out, r, d, Color(0.0, 0.0, 0.0, 0.85), 2.5)
		_ellipse(c + out, r * 0.97, d, Color(0.55, 0.2, 0.1, 0.5), 1.0)
		var rg := _rng(f)
		for j in 4:
			var a := Vector2(rg.randf_range(-0.7, 0.7) * r.x, rg.randf_range(-0.6, 0.6) * r.y)
			var b := a + Vector2(rg.randf_range(-0.5, 0.5) * r.x, rg.randf_range(-0.5, 0.5) * r.y)
			var a2 := c + out + d * a.x + d.orthogonal() * a.y
			var b2 := c + out + d * b.x + d.orthogonal() * b.y
			_ci.draw_line(a2, b2, Color(0, 0, 0, 0.85), 2.0, true)
			_ci.draw_line(a2, b2, Color(1.0, 0.4, 0.1, 0.35 + 0.25 * sin(_t * 2.0 + j)), 1.0, true)
		RepairArt.glow(_ci, c + out, r.x * 0.9, Color(1.0, 0.35, 0.08, 0.08 + 0.05 * sin(_t * 2.3)))
		for j in 3:
			var u := fmod(_t * 0.35 + j * 0.33, 1.0)
			RepairArt.glow(_ci, c + out + Vector2(sin(_t * 1.3 + j * 2.0) * 8.0 * u, -u * r.x * 1.1), r.x * (0.16 + 0.3 * u), Color(0.2, 0.19, 0.18, 0.45 * sin(u * PI)))
	elif stage == "empty":
		_cavity(c, r, d, f)
	if stage in ["ties", "seat"]:
		for j in 2:
			var tp := tie_pos(f, j)
			var tied: bool = st["ties"][j]
			if reachable(f) and bay.tool == "forceps" and (tied if stage == "ties" else not tied):
				_ci.draw_circle(tp, 20.0, Color(1.0, 0.6, 0.25, 0.18 + 0.1 * sin(_t * 5.0)))
			_tie(tp, d, tied)


## The wound a destroyed piece came out of - and the notch: the way the graft must lie.
func _cavity(c: Vector2, r: Vector2, d: Vector2, f: Dictionary) -> void:
	_ellipse(c, r + Vector2(3, 3), d, Color(0.35, 0.04, 0.04, 0.95))
	_ellipse(c, r, d, Color(0.05, 0.005, 0.01, 0.96))
	_ellipse(c, r * 0.7, d, Color(0.0, 0.0, 0.0, 0.5))
	_ellipse(c, r, d, Color(0.8, 0.3, 0.25, 0.7), 1.5)
	var nd := d.rotated(notch(f) * PI * 0.5)
	_notch_mark(c + nd * (r.x if notch(f) % 2 == 0 else r.y) * 1.08, nd, Color(1.0, 0.6, 0.25))


## A tie: a loop of thread round the piece's end, knotted (or hanging open).
func _tie(p: Vector2, d: Vector2, tied: bool) -> void:
	var n := d.orthogonal()
	if tied:
		_ci.draw_line(p - n * 11.0, p + n * 11.0, Color(0, 0, 0, 0.5), 5.0, true)
		_ci.draw_line(p - n * 11.0, p + n * 11.0, Color(0.16, 0.3, 0.62), 4.0, true)
		_ci.draw_line(p - n * 11.0, p + n * 11.0, Color(0.6, 0.82, 1.0), 1.5, true)
		_ci.draw_circle(p, 4.5, Color(0.1, 0.16, 0.3))
		_ci.draw_circle(p, 3.0, Color(0.6, 0.82, 1.0))
	else:
		_ci.draw_line(p - n * 11.0, p - n * 4.0 + d * 7.0, Color(0.4, 0.6, 0.85, 0.8), 2.0, true)
		_ci.draw_line(p + n * 11.0, p + n * 4.0 - d * 7.0, Color(0.4, 0.6, 0.85, 0.8), 2.0, true)
		_ci.draw_arc(p, 5.0, 0, TAU, 12, Color(0.4, 0.6, 0.85, 0.7), 1.5, true)


func _notch_mark(at: Vector2, out: Vector2, col: Color) -> void:
	var side := out.orthogonal()
	_ci.draw_colored_polygon(PackedVector2Array([at + out * 10.0, at - out * 4.0 + side * 8.0, at - out * 4.0 - side * 8.0]), Color(0, 0, 0, 0.6))
	_ci.draw_colored_polygon(PackedVector2Array([at + out * 7.0, at - out * 2.0 + side * 5.5, at - out * 2.0 - side * 5.5]), col)


func _draw_scan() -> void:
	if _mouse.x < -900:
		return
	var o := bay.op()
	var col: Color = Parts.LAYER_INFO[bay.layer]["color"]
	var r := lens_r()
	_ci.draw_circle(_mouse, r, Color(col, 0.06))
	RepairArt.glow(_ci, _mouse, r * 1.05, Color(col, 0.09))
	_ci.draw_arc(_mouse, r + 3.0, 0, TAU, 56, Color(0.05, 0.06, 0.08, 0.9), 7.0, true)
	_ci.draw_arc(_mouse, r + 3.0, 0, TAU, 56, Color(0.55, 0.58, 0.64), 3.0, true)
	_ci.draw_arc(_mouse, r, 0, TAU, 56, Color(col, 0.85), 1.5, true)
	for j in 24:
		var ta := TAU * j / 24.0
		var t1 := 7.0 if j % 6 == 0 else 3.5
		_ci.draw_line(_mouse + Vector2.from_angle(ta) * (r - t1), _mouse + Vector2.from_angle(ta) * (r - 0.5), Color(col, 0.7), 1.0, true)
	_ci.draw_arc(_mouse, r + 8.0, _t * 2.0, _t * 2.0 + 0.8, 10, Color(col, 0.9), 2.5, true)
	_ci.draw_arc(_mouse, r + 8.0, _t * 2.0 + PI, _t * 2.0 + PI + 0.8, 10, Color(col, 0.45), 2.5, true)
	var sy := (fmod(_t * 0.6, 1.0) * 2.0 - 1.0) * r * 0.96
	var half := sqrt(maxf(0.0, r * r - sy * sy))
	_ci.draw_line(_mouse + Vector2(-half, sy), _mouse + Vector2(half, sy), Color(col, 0.35), 1.5)
	_ci.draw_arc(_mouse, r * 0.7, -2.5, -1.9, 8, Color(1, 1, 1, 0.12), 3.0, true)
	if not bay.layer in Parts.scan_layers(bay.items_all()):
		_ci.draw_string(ThemeDB.fallback_font, _mouse + Vector2(-r * 0.86, 4), "this layer needs a Mk II scanner", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col, 0.9))
	for f in bay.faults():
		if not scan_sees(f):
			continue
		var at := anchor(f)
		var dd := at.distance_to(_mouse)
		if dd > r:
			continue
		var kk := 1.0 - dd / r
		var prog := clampf(float(o["scan"].get(int(f["id"]), 0.0)) / 0.45, 0.0, 1.0)
		for j in 3:
			_ci.draw_arc(at, 10.0 + fmod(_t * 36.0 + j * 13.0, 39.0), 0, TAU, 24, Color(col, 0.55 * kk), 1.5, true)
		_ci.draw_circle(at, 5.0, Color(1.0, 0.3, 0.2, 0.5 + 0.4 * kk))
		if not f.get("found", false):
			_ci.draw_arc(at, 30.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 24, Color(1, 1, 1, 0.9), 3.0, true)


func _draw_tool() -> void:
	if _mouse.x < -900:
		return
	var m := _mouse
	match bay.tool:
		"scalpel":
			RepairArt.tool(_ci, "scalpel", m)
			if _down:
				_ci.draw_circle(m, 3.0, Color(0.95, 0.2, 0.15, 0.8))
		"suture":
			RepairArt.tool(_ci, "needle", m + Vector2(-4, -4))
		"fuser":
			RepairArt.tool(_ci, "fuser", m)
			if _down:
				RepairArt.glow(_ci, m, 24.0, Color(0.45, 0.8, 1.0, 0.35))
				_ci.draw_circle(m, 6.0 + randf() * 2.0, Color(0.8, 0.95, 1.0, 0.6))
				_ci.draw_circle(m, 3.0, Color(1, 1, 1))
			else:
				_ci.draw_circle(m, 2.5, Color(0.5, 0.85, 1.0, 0.8))
		"clamp":
			RepairArt.tool(_ci, "hemostat", m)
		"sealant":
			RepairArt.tool(_ci, "sealant", m)
			if _down:
				_ci.draw_circle(m, 10.0, Color(0.85, 0.95, 1.0, 0.35))
				_ci.draw_circle(m, 5.0, Color(0.95, 1.0, 1.0, 0.6))
		"splicer":
			RepairArt.tool(_ci, "splicer", m)
			_ci.draw_circle(m, 2.0, Color(1.0, 0.9, 0.5))
		"tuner":
			RepairArt.tool(_ci, "tuner", m)
		"forceps":
			if _held_spare < 0:
				RepairArt.tool(_ci, "forceps", m)
			else:
				var f := _wound_waiting()
				if not f.is_empty():
					var i := int(f["comp"])
					var d := dir(i)
					var r := piece(i)
					var turn := (_held_spare - notch(f)) * PI * 0.5
					_patch(site(i), r, d, layer_i(i), Color(1.12, 1.08, 1.05, 0.95), m, turn)
					var pts := PackedVector2Array()
					for j in 29:
						var a := TAU * j / 28.0
						pts.append(m + (d * cos(a) * r.x + d.orthogonal() * sin(a) * r.y).rotated(turn))
					_ci.draw_polyline(pts, Color(1.0, 0.95, 0.85, 0.8), 1.5, true)
					var nd := d.rotated(_held_spare * PI * 0.5)
					_notch_mark(m + nd * (r.x if (_held_spare - notch(f)) % 2 == 0 else r.y) * 1.08, nd, Color(1.0, 0.6, 0.25, 0.9))
					RepairArt.tool(_ci, "forceps", m + Vector2(-6, -6))


## The wound waiting for its graft.
func _wound_waiting() -> Dictionary:
	for f in bay.faults():
		if f["kind"] == "wreck" and f.get("found", false) and str(fstate(f)["stage"]) == "empty":
			return f
	return {}
