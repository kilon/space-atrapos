class_name AssetPool
extends RefCounted
## The memory pool of the game's loaded assets (the sprites, their CPU
## copies). What's loaded stays loaded: nothing is
## unloaded unless the pool runs out of room. Its room (budget) is twice what
## the game usually keeps loaded (need: every sprite) -
## to be on the safe side.
##
## Each asset has a priority from how much it's used: every use (touch) adds
## one, and the count fades with a half-life (HALF_LIFE) - what you use now
## outranks what you used an hour ago. Over budget, the lowest-priority assets
## that nothing else holds (a sprite on screen holds its texture) are unloaded
## until it fits; pinned ones (costly to load again) never are. An unloaded
## asset comes back when it's next asked for (a placeholder until then).
##
## Every load and unload is noted (events: the loading console above the event
## log shows the latest, and the pool's total).

const HALF_LIFE := 300.0          # s
const KEEP_EVENTS := 1000

class Entry:
	var key := ""
	var label := ""
	var bytes := 0
	var uses := 0.0               # (as of `at`: fades from then)
	var at := 0.0                 # s, the last use
	var unload: Callable          # drops the asset (its owner forgets it)
	var held: Callable            # true while something else holds it (can't be freed)
	var pinned := false

static var _e := {}               # key -> Entry
static var used := 0              # bytes loaded now
static var need := 0              # bytes the game usually keeps loaded
static var budget := 0            # bytes: 2 x need (set_need), or set directly (tests)
static var peak := 0
static var loads := 0
static var unloads := 0
static var unloaded_bytes := 0
## The latest notes: [seconds, text, kind ("load", "unload", "work")]; `serial` counts them all.
static var events: Array = []
static var serial := 0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## What the game usually keeps loaded (bytes): the room is twice that.
static func set_need(bytes: int) -> void:
	set_need_part("art", bytes)


## The need in parts (the art; the surfaces a system's planets usually keep built
## ahead): the room is twice their sum.
static var _need_parts := {}
static func set_need_part(part: String, bytes: int) -> void:
	_need_parts[part] = bytes
	need = 0
	for k in _need_parts:
		need += int(_need_parts[k])
	budget = 2 * need


## An asset is in: counted, used once. Over budget, the pool makes room.
static func add(key: String, bytes: int, unload: Callable, held := Callable(), pinned := false, label := "") -> void:
	var e: Entry = _e.get(key)
	if e:
		used += bytes - e.bytes
		e.bytes = bytes
	else:
		e = Entry.new()
		e.key = key
		e.bytes = bytes
		_e[key] = e
		used += bytes
	e.label = label if label != "" else key
	e.unload = unload
	e.held = held
	e.pinned = pinned
	loads += 1
	peak = maxi(peak, used)
	touch(key)
	note("Loaded %s  (%s)" % [e.label, mb(bytes)], "load")
	if budget > 0 and used > budget:
		trim()


## An asset used (drawn, handed out): its priority goes up by one.
static func touch(key: String) -> void:
	var e: Entry = _e.get(key)
	if e:
		var t := _now()
		e.uses = e.uses * pow(0.5, (t - e.at) / HALF_LIFE) + 1.0
		e.at = t


## How much it's used (fading with time): the higher, the later it's unloaded.
static func priority(key: String) -> float:
	var e: Entry = _e.get(key)
	if e == null:
		return 0.0
	return e.uses * pow(0.5, (_now() - e.at) / HALF_LIFE)


static func has(key: String) -> bool:
	return _e.has(key)


## Its owner dropped it (no unload: the art reloaded, say).
static func forget(key: String) -> void:
	var e: Entry = _e.get(key)
	if e:
		used -= e.bytes
		_e.erase(key)


## Over budget: the least used assets nobody holds unloaded, until it fits.
static func trim() -> void:
	if used <= budget:
		return
	var free: Array = []
	for e: Entry in _e.values():
		if e.pinned or (e.held.is_valid() and e.held.call()):
			continue
		free.append([priority(e.key), e])
	free.sort_custom(func(a, b): return a[0] < b[0])
	for f in free:
		if used <= budget:
			break
		var e: Entry = f[1]
		_e.erase(e.key)
		used -= e.bytes
		unloads += 1
		unloaded_bytes += e.bytes
		if e.unload.is_valid():
			e.unload.call()
		note("Unloaded %s  (%s, priority %.1f) - the pool was full" % [e.label, mb(e.bytes), f[0]], "unload")
	if used > budget:
		note("Pool over budget: everything left is in use (%s / %s)" % [mb(used), mb(budget)], "unload")


## A line in the loading console.
static func note(text: String, kind := "work") -> void:
	events.append([_now(), text, kind])
	if events.size() > KEEP_EVENTS:
		events.pop_front()
	serial += 1


static func count() -> int:
	return _e.size()


## "212.4 MB".
static func mb(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)


## The pool's state in a line: "Memory pool 212.4 / 488.8 MB - 1093 assets - 0 unloaded".
static func summary() -> String:
	var s := "Memory pool %s / %s  -  %d assets" % [mb(used), mb(budget), _e.size()]
	s += "  -  %d unloaded (%s)" % [unloads, mb(unloaded_bytes)] if unloads > 0 else "  -  none unloaded"
	return s


## The kinds of asset, for the memory map: [key prefix, name, colour] (the first match).
const KINDS := [
	["surface:", "Planet surfaces built ahead", Color(0.95, 0.55, 0.25)],
	["placeholders", "Procedural placeholders (shown till each picture loads)", Color(0.4, 0.85, 0.55)],
	["image:", "Picture data (CPU copies for building textures)", Color(0.6, 0.6, 0.7)],
	["monster_", "Monsters", Color(0.85, 0.3, 0.75)],
	["creature_", "Creatures", Color(0.65, 0.4, 0.95)],
	["tile_", "Buildings and ground tiles", Color(0.95, 0.8, 0.35)],
	["ship_", "Ships", Color(0.3, 0.75, 1.0)],
	["station_", "Stations", Color(0.3, 0.95, 0.75)],
	["sky_", "Skies", Color(0.45, 0.6, 1.0)],
	["fx_", "Effects", Color(1.0, 0.45, 0.3)],
	["gate_", "Jump gates", Color(0.55, 0.95, 1.0)],
	["npc_", "Citizens", Color(0.8, 0.95, 0.5)],
	["", "Other", Color(0.75, 0.75, 0.75)],
]


static func kind_of(key: String) -> int:
	for i in KINDS.size():
		if key.begins_with(KINDS[i][0]):
			return i
	return KINDS.size() - 1


## What's in the pool by kind: [{kind, name, color, bytes, count, top: [[label, bytes, priority]...]}],
## biggest kind first; `top` its `top_n` biggest assets.
static func breakdown(top_n := 8) -> Array:
	var by := {}
	for e: Entry in _e.values():
		var k := kind_of(e.key)
		if not by.has(k):
			by[k] = {"kind": k, "name": KINDS[k][1], "color": KINDS[k][2], "bytes": 0, "count": 0, "items": []}
		var d: Dictionary = by[k]
		d["bytes"] += e.bytes
		d["count"] += 1
		d["items"].append([e.label, e.bytes, priority(e.key)])
	var out := by.values()
	for d in out:
		var items: Array = d["items"]
		items.sort_custom(func(a, b): return a[1] > b[1])
		d["top"] = items.slice(0, top_n)
		d.erase("items")
	out.sort_custom(func(a, b): return a["bytes"] > b["bytes"])
	return out


## Back to empty (tests).
static func reset() -> void:
	_e.clear()
	used = 0
	peak = 0
	loads = 0
	unloads = 0
	unloaded_bytes = 0
	events.clear()
	serial = 0
