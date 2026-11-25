extends Node
## LiveLink: the running game's door for live coding (development only).
## Live updates are always on when the game runs from its project (a debug
## run, not an export, not headless): every changed script, shader, picture
## and data file applies as it's saved - hot reloaded, the open screens
## rebuilt; a change hot reload can't take (a new class_name, a variable
## removed or renamed) restarts the game where you were (live_restart). A
## note in the corner says what happened.
## The connection for tools/live.py: with the user arg --live
## (godot --path . -- --live[=PORT]) it listens on 127.0.0.1:6070 (or PORT) -
## only this machine can connect.
##
## Protocol: one JSON object per line in, one JSON reply per line out:
##   {"cmd": "...", ...}  ->  {"ok": true, "result": ...} | {"ok": false, "error": "..."}
## Commands:
##   ping                          - "pong", the game's pid and fps
##   state                         - a snapshot: ship, the signal, enemies, fps
##   eval   {expr}                 - a GDScript expression (Expression); names:
##                                   main, ship, site, root, tree, live
##   set    {target, prop, value}  - target/value are expressions; prop may be
##                                   an indexed path ("position:x")
##   run    {code}                 - GDScript statements, compiled into a
##                                   throwaway script's run() (may await; the
##                                   same names as eval); or a whole script
##                                   source that has its own func run()
##   reload {paths}                - hot reload scripts (keeping every live
##                                   object's state) / shaders / other resources
##   watch  {on}                   - hot reload changed files automatically
##   events {since}                - the log since seq `since` (errors, prints,
##                                   reloads, deaths)
##   tree   {path, depth}          - the node tree under a node
##   shot   {path}                 - a screenshot (PNG) of the game's view
##   pause  {on} / speed {scale}   - pause the game / Engine.time_scale
##   inspect {expr}                - open the Inspector window on an object
##
## In any debug run (with or without --live), Alt + right-click opens the
## developer menu: inspect the thing under the cursor, the Inspector window
## (DevInspector - live values, right of the game's window), pause, game
## speed, hot reload on / off.

const PORT := 6070
var watch_dirs := _tree_of(["res://scripts", "res://shaders"]) + ["res://data", "res://data/sprites", "res://data/docs/shots"]
## Reference sheets the pieces are cut from (external/images is outside the game):
## a changed one is cut again (tools/extract_sprites.py, on a thread) - its new
## pieces then come in through data/sprites like any changed picture.
const SHEETS_DIR := "res://external/images"
const SHEET_MATCH := "tile_sheet"
var _cutting := {}                 # sheet -> Thread
const WATCH_EXT := ["gd", "gdshader", "png", "jpg", "json"]
const PICTURE_EXT := ["png", "jpg"]
var _new_files := {}               # (files the watcher saw appear)
var _importer: Thread              # (pictures being imported again)
var _to_import := {}
const MAX_EVENTS := 2000

var enabled := false
var port := PORT
var auto_reload := true
var _server: TCPServer
var _clients: Array = []           # [{peer, buf}]
var _events: Array = []            # [{seq, t, kind, text}]
var _seq := 0
var _mutex := Mutex.new()
var _watch_t := 0.0
var dev := false                   # the developer menu (any debug run)
var inspector: Window   # (DevInspector)
var _menu: PopupMenu
var _speeds: PopupMenu
var _picked: Array = []            # menu id -> object to inspect


## --live / --live=PORT among the user args (after --), in a debug run.
static func live_arg() -> int:
	if not OS.is_debug_build():
		return 0
	for a in OS.get_cmdline_user_args():
		if a == "--live":
			return PORT
		if a.begins_with("--live="):
			return int(a.trim_prefix("--live="))
	return 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dev = OS.is_debug_build()
	set_process_input(dev)
	port = live_arg()
	for c in ProjectSettings.get_global_class_list():
		_known_classes[str(c["class"])] = true
	# (always, run from the project: not an export, not headless - the tests)
	var project_run := dev and not OS.has_feature("template") and DisplayServer.get_name() != "headless" \
		and not "--no-live" in OS.get_cmdline_user_args()   # (--no-live: live updates off for this run)
	auto_reload = project_run
	if port > 0:
		start(port)
	elif project_run:
		OS.add_logger(_Log.new(self))
		set_process(true)
	if project_run:
		_start_watch()
	else:
		set_process(false)
	if project_run:
		_resume = _read_resume()


func start(p: int) -> Error:
	_server = TCPServer.new()
	var err := _server.listen(p, "127.0.0.1")
	if err != OK:
		push_warning("LiveLink: can't listen on port %d (%s)" % [p, error_string(err)])
		_server = null
		return err
	port = p
	enabled = true
	set_process(true)
	OS.add_logger(_Log.new(self))
	print("LiveLink: listening on 127.0.0.1:%d" % p)
	return OK


func stop() -> void:
	for c in _clients:
		c["peer"].disconnect_from_host()
	_clients.clear()
	if _server:
		_server.stop()
	_server = null
	enabled = false
	set_process(false)


# --- The log ---------------------------------------------------------------------

## A line in the event log (thread safe - the logger calls it from any thread).
func event(kind: String, text: String) -> void:
	_mutex.lock()
	_seq += 1
	_events.append({"seq": _seq, "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "kind": kind, "text": text})
	if _events.size() > MAX_EVENTS:
		_events = _events.slice(_events.size() - MAX_EVENTS)
	_mutex.unlock()


func events_since(since: int) -> Array:
	_mutex.lock()
	var out := _events.filter(func(e): return e["seq"] > since)
	_mutex.unlock()
	return out.slice(maxi(0, out.size() - 400))   # (the latest - a reply carries 500 at most)


## Godot's log (prints, warnings, errors with their script place) into events.
class _Log extends Logger:
	var link: WeakRef

	func _init(l: Node) -> void:
		link = weakref(l)

	func _log_message(message: String, error: bool) -> void:
		var l = link.get_ref()
		if l and not message.begins_with("LiveLink"):
			l.event("error" if error else "print", message.strip_edges(false, true))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var l = link.get_ref()
		if l == null:
			return
		var where := "%s:%d (%s)" % [file, line, function]
		# (a parse error names the script and line itself; else: where the script was)
		for bt in script_backtraces if not file.begins_with("res://") else []:
			if bt.get_frame_count() > 0:
				where = "%s:%d (%s)" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
				break
		var kind := "warning" if error_type == ERROR_TYPE_WARNING else "error"
		l.event(kind, "%s - %s" % [rationale if rationale != "" else code, where.replace("::trial", "")])


# --- The connection --------------------------------------------------------------

func _process(delta: float) -> void:
	if auto_reload:
		_watch_step(delta)
	if not _resume.is_empty():
		_resume_step()
	if not _reopen_talos.is_empty():
		_reopen_talos_step()
	if _restart_why != "" and Time.get_ticks_msec() >= _restart_at:
		_try_restart()
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray()})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			c["buf"].append_array(peer.get_data(n)[1])
		var nl: int = c["buf"].find(10)
		while nl >= 0:
			var line: String = c["buf"].slice(0, nl).get_string_from_utf8()
			c["buf"] = c["buf"].slice(nl + 1)
			nl = c["buf"].find(10)
			if line.strip_edges() != "":
				_serve(peer, line)


func _serve(peer: StreamPeerTCP, line: String) -> void:
	var req: Variant = JSON.parse_string(line)
	var reply: Dictionary
	if not (req is Dictionary) or not req.has("cmd"):
		reply = {"ok": false, "error": "not a JSON command: " + line.left(80)}
	else:
		reply = await handle(req)
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())


## One command (see the header); a coroutine (run may await).
func handle(req: Dictionary) -> Dictionary:
	var cmd: String = req["cmd"]
	match cmd:
		"ping":
			return _ok({"pong": true, "pid": OS.get_process_id(), "fps": Engine.get_frames_per_second(), "port": port})
		"state":
			return _ok(snapshot())
		"eval":
			return _eval(str(req.get("expr", "")))
		"set":
			return _set_cmd(req)
		"run":
			return await _run(str(req.get("code", "")))
		"reload":
			return _ok(reload(req.get("paths", [])))
		"watch":
			set_auto_reload(bool(req.get("on", true)))
			return _ok({"auto_reload": auto_reload})
		"inspect":
			var r := _expr(str(req.get("expr", "ship")))
			if not r[0] or not (r[1] is Object):
				return _err("not an object: " + str(r[1]))
			open_inspector(r[1])
			return _ok(inspector.target)
		"events":
			return _ok({"events": events_since(int(req.get("since", 0))), "last": _seq})
		"tree":
			var n := _node(str(req.get("path", "")))
			if n == null:
				return _err("no node " + str(req.get("path", "")))
			return _ok(_tree(n, int(req.get("depth", 2))))
		"shot":
			return _shot(str(req.get("path", "user://live_shot.png")))
		"pause":
			get_tree().paused = bool(req.get("on", not get_tree().paused))
			return _ok({"paused": get_tree().paused})
		"speed":
			Engine.time_scale = clampf(float(req.get("scale", 1.0)), 0.0, 20.0)
			return _ok({"time_scale": Engine.time_scale})
	return _err("unknown command " + cmd)


func _ok(result: Variant) -> Dictionary:
	return {"ok": true, "result": jsonable(result)}


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


# --- Names for eval / run ---------------------------------------------------------

## The game scene (Main) - the current scene, or wherever a script put it.
func main() -> Node:
	var cs := get_tree().current_scene
	if cs and cs.has_method("enter_site"):
		return cs
	for c in get_tree().root.get_children():
		if c.has_method("enter_site"):
			return c
	return null


func _names() -> Dictionary:
	var m := main()
	var d := {}
	for c in get_tree().root.get_children():   # the autoloads (Galaxy, Settings, ...)
		if c != m and ProjectSettings.has_setting("autoload/" + str(c.name)):
			d[str(c.name)] = c
	for s in ["Engine", "Input", "OS", "Time", "DisplayServer", "ResourceLoader", "ProjectSettings"]:
		d[s] = Engine.get_singleton(s)
	for c in ProjectSettings.get_global_class_list():   # (the game's classes: MinoanTiles, Galaxy's types...)
		if not d.has(c["class"]) and ResourceLoader.has_cached(c["path"]):
			d[c["class"]] = load(c["path"])
	d.merge({
		"main": m,
		"ship": m.get("ship") if m else null,
		"site": m.get("site") if m else null,
		"root": get_tree().root,
		"tree": get_tree(),
		"live": self,
	}, true)
	return d


## A node by alias (main, ship, site) or path (from root or from Main).
func _node(path: String) -> Node:
	var names := _names()
	if path == "" or path == "root":
		return get_tree().root
	var head := path.get_slice("/", 0)
	if names.get(head) is Node:
		var base: Node = names[head]
		var rest := path.substr(head.length()).trim_prefix("/")
		return base if rest == "" else base.get_node_or_null(rest)
	var n := get_tree().root.get_node_or_null(path)
	if n == null and names["main"]:
		n = names["main"].get_node_or_null(path)
	return n


func _expr(code: String) -> Array:   # [ok, value or error]
	var names := _names()
	var e := Expression.new()
	if e.parse(code, PackedStringArray(names.keys())) != OK:
		return [false, e.get_error_text()]
	var v: Variant = e.execute(names.values(), self, false)
	if e.has_execute_failed():
		return [false, "failed: " + e.get_error_text()]
	return [true, v]


func _eval(code: String) -> Dictionary:
	var r := _expr(code)
	return _ok(r[1]) if r[0] else _err(r[1])


func _set_cmd(req: Dictionary) -> Dictionary:
	var t := _expr(str(req.get("target", "")))
	if not t[0]:
		return _err("target: " + str(t[1]))
	if not (t[1] is Object):
		return _err("target is not an object: " + str(t[1]))
	var v := _expr(str(req.get("value", "null")))
	if not v[0]:
		return _err("value: " + str(v[1]))
	var obj: Object = t[1]
	var prop := str(req.get("prop", ""))
	obj.set_indexed(NodePath(prop), v[1])
	return _ok(obj.get_indexed(NodePath(prop)))


var _run_n := 0
## The snippets' scripts and objects, kept for the whole run: freeing a script
## whose code made lambdas crashes Godot 4.7 (double free) a run or two later.
var _runs: Array = []

## Statements -> a throwaway script: func run() with main/ship/site/... set.
func _run(code: String) -> Dictionary:
	var src := code
	if not code.contains("func run("):
		var body := ""
		for l in code.split("\n"):
			body += "\t" + l + "\n"
		src = "func run():\n" + body + "\treturn null\n"
	if not src.begins_with("extends"):
		src = "extends RefCounted\nvar main\nvar ship\nvar site\nvar root\nvar tree\nvar live\n\n" + src
	var s := GDScript.new()
	s.source_code = src
	_run_n += 1
	var err := s.reload()
	if err != OK:
		return _err("doesn't compile (%s) - see the events for the line" % error_string(err))
	var obj: Object = s.new()
	_runs.append([s, obj])
	for k in _names():
		if k in obj:
			obj.set(k, _names()[k])
	var v: Variant = await obj.run()
	return _ok(v)


# --- Hot reload --------------------------------------------------------------------

## Reload scripts (live objects keep their state and get the new code -
## subclasses that are loaded are reloaded after their bases), shaders (their
## code, so every material using them updates) and other resources (in place).
func reload(paths: Array) -> Dictionary:
	# A change hot reload can't take - a new class (Godot names classes as the
	# game starts) or a variable removed or renamed (live objects would keep
	# the old layout: it has crashed the game) - restarts the game instead.
	var why := _needs_restart(paths)
	if why != "":
		_restart_why = why
		_prepared_ok = false   # (a newer change: ready it again)
		_restart_at = Time.get_ticks_msec() + RESTART_QUIET_MS   # (more saves soon: wait for them)
		_notice("Live: restarting to apply %s" % why, NOTE)
		event("reload", "restart needed: " + why)
		return {"reloaded": [], "failed": [], "restart": why}
	var done := []
	var failed := []
	var scripts := []
	var pictures := []
	for p in paths:
		p = _res_path(str(p))
		if p.ends_with(".gd"):
			scripts.append(p)
		elif DATA_RELOAD.has(p):
			if _talos_open():
				continue   # (Talos edits this data itself: a reload would drop its unsaved edits)
			DATA_RELOAD[p].call()
			done.append(p)
		elif PICTURE_EXT.has(p.get_extension()):
			pictures.append(p)   # (imported again first - else the old import loads)
		elif not ResourceLoader.has_cached(p):
			continue   # (not loaded - the game reads it fresh when it needs it)
		elif p.ends_with(".gdshader"):
			var sh: Shader = load(p)
			sh.code = FileAccess.get_file_as_string(p)
			done.append(p)
		else:
			ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
			done.append(p)
	# Loaded scripts that extend a changed one reload with it (base first).
	var all := scripts.duplicate()
	for p in _loaded_scripts():
		if p in all:
			continue
		var s: Script = load(p)
		var b := s.get_base_script()
		while b:
			if b.resource_path in scripts:
				all.append(p)
				break
			b = b.get_base_script()
	all.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for p in all:
		if not ResourceLoader.has_cached(p):
			continue
		if p == get_script().resource_path:
			continue   # (not itself - it's running the reload; restart for that)
		var s: GDScript = load(p)
		if _base_failed(s, failed):
			continue
		var src := FileAccess.get_file_as_string(p)
		# Compile it on the side first: broken code mustn't break the live script.
		if not compiles(src, p):
			failed.append(p)
			continue
		var before := _member_names(s)
		s.source_code = src
		if s.reload(true) == OK:
			done.append(p)
			var added := _member_names(s).filter(func(n): return not before.has(n))
			if not added.is_empty():
				_init_members(s, added)
		else:
			failed.append(p)
	if not pictures.is_empty():
		_import_pictures(pictures)
	if not done.is_empty():
		event("reload", "reloaded " + ", ".join(done.map(func(x): return x.get_file())))
		_refresh_screens()
		_rebuild_talos_tools(done)
		_notice("Live update: " + ", ".join(done.map(func(x): return x.get_file())), NOTE)
	if not failed.is_empty():
		event("error", "reload failed (kept the old code): " + ", ".join(failed))
		_notice("Live: not applied - doesn't compile yet: %s (the old code runs on)" % ", ".join(failed.map(func(x): return x.get_file())), WARN)
	return {"reloaded": done, "failed": failed}


# --- Changes hot reload can't take: a restart, where you were ----------------------

## Class names Godot knew as the game started (a new one needs a restart).
var _known_classes := {}
var _restart_why := ""
var _restart_at := 0
const RESTART_QUIET_MS := 2500   # (no more changes for this long: then restart)
const RESUME_FILE := "user://live_resume.json"
var _resume := {}                # (after a live restart: where to go back to)
## Data files the game reads itself, and how to read them again.
var DATA_RELOAD := {
	"res://data/main_quest.json": func(): QuestData.reload(),
	"res://data/themes.json": func(): Themes.reload(),
	"res://data/effects.json": func(): Fx.reload_all(),   # (every effect playing rebuilt)
}


## Why these changed files need a restart ("" - hot reload will do): a new
## class_name; a loaded script that lost variables, or gained some while
## objects of it live in the game (they were set up without them - their
## _ready never sees the new ones: a sprite never loaded); a new picture
## (imported as the game restarts; what looked for it found nothing).
func _needs_restart(paths: Array) -> String:
	for p in paths:
		p = _res_path(str(p))
		if PICTURE_EXT.has(p.get_extension()) and _new_files.has(p):
			return "a new picture, %s" % p.get_file()
		if not p.ends_with(".gd") or not FileAccess.file_exists(p):
			continue
		if p == get_script().resource_path:
			return "live_link.gd itself changed"   # (it can't reload itself)
		var src := FileAccess.get_file_as_string(p)
		for c in new_classes(src, _known_classes):
			return "a new class, %s (%s)" % [c, p.get_file()]
		if ResourceLoader.has_cached(p) and p != get_script().resource_path:
			var gone := removed_members(load(p), src, p)
			if not gone.is_empty():
				return "%s lost %s" % [p.get_file(), ", ".join(gone)]
			var gained := added_members(load(p), src, p)
			if not gained.is_empty() and _lasting_nodes_of(load(p)) > 0:
				return "%s gained %s (its objects in the game were made without it)" % [p.get_file(), ", ".join(gained)]
	return ""


## The variables the new source `src` has that script `s` doesn't (added)
## - only if it compiles.
static func added_members(s: Script, src: String, path: String) -> Array:
	var t := GDScript.new()
	t.source_code = trial_source(src)
	t.take_over_path(path + "::members")
	if t.reload() != OK:
		return []
	var vars := func(sc: Script) -> Array:
		return sc.get_script_property_list().filter(func(p): return p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE).map(func(p): return p["name"])
	var before: Array = vars.call(s)
	return vars.call(t).filter(func(n): return not before.has(n))


## Nodes running script `s` that would keep living after the reload - those inside a Talos tool
## that's rebuilt with the new code anyway (_rebuild_talos_tools: no unsaved work) don't count:
## a tool gaining a variable is built again, not a reason to restart the game.
func _lasting_nodes_of(s: Script) -> int:
	var rebuilt: Array = []
	for host in get_tree().get_nodes_in_group("talos_host"):
		var tools = host.get("tools")
		if tools is Dictionary:
			for t in tools.values():
				if is_instance_valid(t) and t.get("dirty") != true:
					rebuilt.append(t)
	var n_live := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n in rebuilt:
			continue   # (it and all inside it are made anew)
		stack.append_array(n.get_children(true))
		var ns: Script = n.get_script()
		while ns and ns != s:
			ns = ns.get_base_script()
		if ns == s:
			n_live += 1
	return n_live


## Nodes in the tree running script `s` (or one extending it).
static func live_nodes_of(tree: SceneTree, s: Script) -> int:
	var n_live := 0
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children(true))
		var ns: Script = n.get_script()
		while ns and ns != s:
			ns = ns.get_base_script()
		if ns != null:
			n_live += 1
	return n_live


## The class_names in `src` that `known` doesn't have.
static func new_classes(src: String, known: Dictionary) -> Array:
	var out := []
	for line in src.split("\n"):
		if line.begins_with("class_name "):
			var c := line.trim_prefix("class_name ").strip_edges().split(" ")[0].strip_edges()
			if c != "" and not known.has(c):
				out.append(c)
	return out


## The variables script `s` has that its new source `src` doesn't (renamed or
## removed) - only if the new source compiles (broken code isn't a reason).
static func removed_members(s: Script, src: String, path: String) -> Array:
	var t := GDScript.new()
	t.source_code = trial_source(src)
	t.take_over_path(path + "::members")
	if t.reload() != OK:
		return []
	var now := t.get_script_property_list().map(func(p): return p["name"])
	return s.get_script_property_list().map(func(p): return p["name"]).filter(func(n): return not now.has(n) and not str(n).ends_with(".gd"))


## Restarts the game to apply a change, back where you were - once the files
## have been quiet a moment, the game can be saved and Talos has nothing
## unsaved (else it waits, and says why).
func _try_restart() -> void:
	if _prep != null:
		return   # (being prepared)
	var tree := get_tree()
	var scene := tree.current_scene
	if scene == null or tree.root.has_node("LoadVeil"):
		_restart_at = Time.get_ticks_msec() + 500
		return
	if not _prepared_ok:
		# First (on a thread - the game runs on): an import, so the new game
		# knows new class_names, then a check that every script compiles in a
		# fresh process - never restart into code that doesn't.
		_notice("Live: getting the update ready (%s)..." % _restart_why, NOTE)
		_prep = Thread.new()
		_prep.start(_prepare)
		return
	var resume := {"why": _restart_why}
	if scene.scene_file_path == "res://scenes/editor/editor.tscn":
		if _talos_unsaved():
			_notice("Live: a change needs a restart - save your edits in Talos (Ctrl+S) and it restarts", WARN)
			_restart_at = Time.get_ticks_msec() + 3000
			return
		resume["kind"] = "talos"
		resume["tool"] = str(scene.get("current"))
		resume["page"] = TalosNav.page
		resume["talos_return"] = SaveGame.talos_return
	elif scene.has_method("get_save_data"):
		if SaveGame._game(true) == null:
			_restart_at = Time.get_ticks_msec() + 1000   # (landing, jumping: in a moment)
			return
		if SaveGame.talos_overlay() != null and _talos_unsaved():
			_notice("Live: a change needs a restart - save your edits in Talos (Ctrl+S) and it restarts", WARN)
			_restart_at = Time.get_ticks_msec() + 3000
			return
		if not SaveGame.save_game(scene.get_save_data(), SaveGame.LIVE):
			return
		resume["kind"] = "game"
		if SaveGame.talos_overlay() != null:   # (Talos open over it: open again over the game, on that tool)
			var h := TalosNav.host(tree)
			resume["talos_overlay"] = true
			resume["tool"] = str(h.get("current")) if h else ""
			resume["page"] = TalosNav.page
	else:
		resume["kind"] = "menu"
	live_restart(resume)


var _prep: Thread
var _prepared_ok := false

func _prepare() -> void:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var out := []
	OS.execute(exe, ["--headless", "--path", proj, "--import"], out, true)
	out = []
	var code := OS.execute(exe, ["--headless", "--path", proj, "-s", "res://tools/live_check.gd"], out, true)
	_prepared.call_deferred(code, "\n".join(out))


func _prepared(code: int, out: String) -> void:
	_prep.wait_to_finish()
	_prep = null
	if code != 0:
		var broken := []
		for line in out.split("\n"):
			if line.begins_with("BROKEN "):
				broken.append(line.trim_prefix("BROKEN ").get_file())
		_notice("Live: not restarting yet - doesn't compile: %s (save again when fixed)" % ", ".join(broken if not broken.is_empty() else ["?"]), WARN)
		event("error", "live restart held back - doesn't compile: " + ", ".join(broken))
		_restart_why = ""
		return
	_prepared_ok = true
	_restart_at = 0
	_try_restart()


## Writes where to come back to, then restarts the game (the same command
## line, the window where it is now).
func live_restart(resume: Dictionary) -> void:
	event("reload", "restarting: " + str(resume.get("why", "")))
	var f := FileAccess.open(RESUME_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(resume))
		f.close()
	OS.set_restart_on_exit(true, PackedStringArray(restart_args()))
	_restart_why = ""
	get_tree().quit()


## The arguments to start the game again with: the very ones it was started
## with (Linux: /proc/self/cmdline - the engine's own, --path, --position...,
## aren't in get_cmdline_args), else rebuilt: the project, the window's size
## and its frame's corner, and the user args as they were.
static func restart_args() -> Array:
	var f := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	if f:
		var raw := f.get_buffer(1 << 16)
		f.close()
		var parts := _split_nul(raw)
		if parts.size() > 1:
			return parts.slice(1)   # (without the executable itself)
	var pos := DisplayServer.window_get_position_with_decorations()
	var size := DisplayServer.window_get_size()
	var args := ["--path", ProjectSettings.globalize_path("res://"), "--resolution", "%dx%d" % [size.x, size.y],
		"--position", "%d,%d" % [pos.x, pos.y]]
	var user := Array(OS.get_cmdline_user_args())
	return args + (["--"] + user if not user.is_empty() else [])


static func _split_nul(raw: PackedByteArray) -> Array:
	var out := []
	var start := 0
	for i in raw.size():
		if raw[i] == 0:
			out.append(raw.slice(start, i).get_string_from_utf8())
			start = i + 1
	if start < raw.size():
		out.append(raw.slice(start).get_string_from_utf8())
	return out


func _read_resume() -> Dictionary:
	if not FileAccess.file_exists(RESUME_FILE):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESUME_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESUME_FILE))
	return d if d is Dictionary else {}


## After a live restart: once the title screen is up, back where you were.
func _resume_step() -> void:
	var tree := get_tree()
	var scene := tree.current_scene
	if scene == null or scene.scene_file_path != "res://scenes/ui/main_menu.tscn":
		return
	var r := _resume
	_resume = {}
	match str(r.get("kind", "")):
		"game":
			SaveGame.load_slot(SaveGame.LIVE)
			if r.get("talos_overlay", false):
				_reopen_talos = r   # (once the game is back: Talos over it again)
		"talos":
			SaveGame.talos_return = bool(r.get("talos_return", false))
			TalosNav.page = int(r.get("page", 0))
			tree.change_scene_to_file("res://scenes/editor/editor.tscn")
			var tool := str(r.get("tool", ""))
			if tool != "":
				(func():
					var h := TalosNav.host(tree)
					if h:
						h.show_tool(tool)).call_deferred()
	_notice("Live: restarted to apply %s" % r.get("why", "a change"), NOTE)


var _reopen_talos := {}

func _reopen_talos_step() -> void:
	var tree := get_tree()
	if tree.root.has_node("LoadVeil") or SaveGame._game(true) == null:
		return   # (still loading)
	var r := _reopen_talos
	_reopen_talos = {}
	TalosNav.page = int(r.get("page", 0))
	if SaveGame.open_talos():
		var tool := str(r.get("tool", ""))
		if tool != "":
			(func():
				var h := TalosNav.host(tree)
				if h:
					h.show_tool(tool)).call_deferred()


func _talos_open() -> bool:
	var s := get_tree().current_scene
	return (s != null and s.scene_file_path == "res://scenes/editor/editor.tscn") or SaveGame.talos_overlay() != null


## Whether any Talos tool has edits not saved yet.
func _talos_unsaved() -> bool:
	for s in [get_tree().current_scene, SaveGame.talos_overlay()]:
		if s == null:
			continue
		for n in s.find_children("*", "", true, false):
			if n.get("dirty") == true:
				return true
	return false


## After a hot reload: the screens on show rebuilt with the new code (a
## page built before keeps what it built until it's built again).
const SCREENS := {"dev_mode.gd": "_refresh", "station_menu.gd": "refresh", "scenario_editor.gd": "_rebuild",
	"ship_menu.gd": "show_tab", "field_menu.gd": "show_tab", "patcher.gd": "show_patch"}

func _refresh_screens() -> void:
	var stack: Array = [get_tree().current_scene, SaveGame.talos_overlay()].filter(func(x): return x != null)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var sc: Script = n.get_script()
		if sc == null or not SCREENS.has(sc.resource_path.get_file()):
			continue
		if n is CanvasItem and not n.is_visible_in_tree():
			continue
		var m: String = SCREENS[sc.resource_path.get_file()]
		if not n.has_method(m):
			continue
		if m in ["show_tab", "show_patch"]:
			var cur: Variant = n.get("current")
			if cur is int and int(cur) >= 0:
				n.call(m, cur)
		else:
			n.call(m)


## After a hot reload: Talos's tools (the mesh, animation and effects editors) built again with the
## new code when anything they're made of changed (scripts/editor/, the icons and their motions) -
## each reopening what it had open (live_state / live_restore); one with unsaved work is left as it
## is (it'd be lost) and says so.
func _rebuild_talos_tools(changed: Array) -> void:
	var editorish := changed.filter(func(p): return str(p).begins_with("res://scripts/editor/") or str(p).get_file() in ["icon_anim.gd", "editor_icons.gd", "ui.gd", "pin_tips.gd"])
	if editorish.is_empty():
		return
	for host in get_tree().get_nodes_in_group("talos_host"):
		if host.has_method("rebuild_tools"):
			var kept: Array = host.rebuild_tools()
			if not kept.is_empty():
				_notice("Live: %s has unsaved work - rebuilt once you save it (or leave and come back)" % ", ".join(kept), WARN)


## A note in the corner for a few seconds (what a live update did).
const NOTE := Color(0.55, 0.9, 1.0)
const WARN := Color(1.0, 0.6, 0.4)
var _note_layer: CanvasLayer
var _note: Label
var _note_tween: Tween

func _notice(text: String, color: Color) -> void:
	if not auto_reload or DisplayServer.get_name() == "headless":
		return
	if _note_layer == null:
		_note_layer = CanvasLayer.new()
		_note_layer.layer = 1000   # (above Talos over the game too)
		add_child(_note_layer)
		_note = Label.new()
		_note.add_theme_font_size_override("font_size", 14)
		_note.add_theme_constant_override("outline_size", 5)
		_note.add_theme_color_override("font_outline_color", Color.BLACK)
		_note.anchor_left = 1.0
		_note.anchor_right = 1.0
		_note.anchor_top = 1.0
		_note.anchor_bottom = 1.0
		_note.offset_left = -900
		_note.offset_right = -14
		_note.offset_top = -56
		_note.offset_bottom = -32
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_note.clip_text = true
		_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_note_layer.add_child(_note)
	_note.text = text
	_note.add_theme_color_override("font_color", color)
	_note.modulate.a = 1.0
	if _note_tween:
		_note_tween.kill()
	_note_tween = create_tween()
	_note_tween.tween_interval(6.0 if color == WARN else 3.0)
	_note_tween.tween_property(_note, "modulate:a", 0.0, 0.6)


## Whether GDScript source compiles (its class_name blanked out - a scratch
## copy may not take the real one's name; the errors go to the log with the
## real file's line numbers).
static func compiles(src: String, path: String) -> bool:
	var t := GDScript.new()
	t.source_code = trial_source(src)
	t.take_over_path(path + "::trial")
	return t.reload() == OK


## A script's source for a scratch compile: its class_name line blanked (a
## scratch copy can't take the real one's name) and its own name, where it
## is a type (-> X, : X, as X, is X), made Object - else a class that names
## itself ("-> RichField") never compiles on the side.
static func trial_source(src: String) -> String:
	var lines := src.split("\n")
	var own := ""
	for i in lines.size():
		if lines[i].begins_with("class_name "):
			own = lines[i].trim_prefix("class_name ").strip_edges().split(" ")[0]
			lines[i] = ""
	var out := "\n".join(lines)
	if own != "":
		var re := RegEx.new()
		re.compile("(->\\s*|:\\s*|\\bas\\s+|\\bis\\s+)" + own + "\\b")
		out = re.sub(out, "${1}Object", true)
	return out


func _base_failed(s: Script, failed: Array) -> bool:
	var b := s.get_base_script()
	while b:
		if b.resource_path in failed:
			return true
		b = b.get_base_script()
	return false


func _member_names(s: Script) -> Array:
	return s.get_script_property_list().map(func(p): return p["name"])


## Variables a reload added are null in the objects that already existed:
## give them their declared defaults (in every node of the tree with that
## script or one extending it - nodes are what lives; the rest can't be
## found).
func _init_members(s: Script, names: Array) -> void:
	var n_set := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children(true))
		var ns: Script = n.get_script()
		while ns and ns != s:
			ns = ns.get_base_script()
		if ns == null:
			continue
		var decl: Dictionary = preload("res://scripts/core/dev_inspector.gd").declared_defaults(s)
		for m in names:
			if typeof(n.get(m)) == TYPE_NIL:
				var d: Variant = decl.get(m, s.get_property_default_value(m))
				if d is Array or d is Dictionary:
					d = d.duplicate(true)
				if d != null:
					n.set(m, d)
					n_set += 1
	if n_set > 0:
		event("reload", "gave %d new variable(s) of %s their defaults in live objects" % [n_set, s.resource_path.get_file()])


func _res_path(p: String) -> String:
	if p.contains("://"):
		return p
	var root := ProjectSettings.globalize_path("res://")
	return "res://" + p.trim_prefix(root).trim_prefix("./")


func _depth(p: String) -> int:
	var n := 0
	var b: Script = (load(p) as Script).get_base_script()
	while b:
		n += 1
		b = b.get_base_script()
	return n


## The folders under these (and they), for watching.
static func _tree_of(roots: Array) -> Array:
	var out: Array = []
	var todo: Array = roots.duplicate()
	while not todo.is_empty():
		var d: String = todo.pop_back()
		out.append(d)
		for sub in DirAccess.get_directories_at(d):
			todo.append(d.path_join(sub))
	return out


func _loaded_scripts() -> Array:
	var out := []
	for d in _tree_of(["res://scripts"]):
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and ResourceLoader.has_cached(d + "/" + f):
				out.append(d + "/" + f)
	return out


## The watched files' times, checked on a thread of their own: a file check
## can block on a busy disk (100+ ms now and then - the project lives in a
## synced folder), and on the main thread that stuttered the game. A pass
## every 0.5 s; what changed is handed over (_watch_step, on the main
## thread), which reloads it - and cuts a changed tile sheet.
var _watch_thread: Thread
var _watch_stop := false
var _watch_mutex := Mutex.new()
var _changed: Array = []          # changed files the thread found (taken by _watch_step)
var _changed_sheets: Array = []   # changed tile sheets (file names)
var _fresh: Array = []            # new files the thread found (taken with _changed)

func _start_watch() -> void:
	if _watch_thread != null:
		return
	_watch_stop = false
	_watch_thread = Thread.new()
	_watch_thread.start(_watch_loop)


func _stop_watch() -> void:
	if _watch_thread == null:
		return
	_watch_stop = true
	_watch_thread.wait_to_finish()
	_watch_thread = null


func _exit_tree() -> void:
	_stop_watch()
	if _importer != null:
		_importer.wait_to_finish()


func _watch_loop() -> void:
	var times := {}
	var first := true   # (the first pass only records)
	while not _watch_stop:
		var changed := []
		var fresh := []   # (new files - not there when the game started)
		var sheets := []
		for d in watch_dirs:
			for f in DirAccess.get_files_at(d):
				if not WATCH_EXT.has(f.get_extension()):
					continue
				var p: String = d.path_join(f)
				var t := FileAccess.get_modified_time(p)
				if not first and times.get(p, -1) != t:   # (changed, or new)
					changed.append(p)
					if not times.has(p):
						fresh.append(p)
				times[p] = t
		for f in DirAccess.get_files_at(SHEETS_DIR):
			if not f.contains(SHEET_MATCH) or f.get_extension() != "png":
				continue
			var p := SHEETS_DIR.path_join(f)
			var t := FileAccess.get_modified_time(p)
			if not first and times.get(p, -1) != t:
				sheets.append(f)
			times[p] = t
		first = false
		if not changed.is_empty() or not sheets.is_empty():
			_watch_mutex.lock()
			_changed.append_array(changed)
			_fresh.append_array(fresh)
			_changed_sheets.append_array(sheets)
			_watch_mutex.unlock()
		for i in 10:   # (0.5 s, a stop request heard within 50 ms)
			if _watch_stop:
				break
			OS.delay_msec(50)


## Changed pictures: Godot imports them again (on a thread, the game runs
## on), then the loaded ones reload in place - whatever shows them updates.
func _import_pictures(pics: Array) -> void:
	for p in pics:
		_to_import[p] = true
	if _importer != null:
		return   # (one import at a time - it picks up the rest after)
	var batch: Array = _to_import.keys()
	_to_import = {}
	event("reload", "importing " + ", ".join(batch.map(func(x): return x.get_file())))
	_importer = Thread.new()
	_importer.start(func():
		var out := []
		OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], out, true)
		_imported.call_deferred(batch))


func _imported(batch: Array) -> void:
	_importer.wait_to_finish()
	_importer = null
	var done := []
	for p in batch:
		if ResourceLoader.has_cached(p):
			ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
			done.append(p.get_file())
	if not done.is_empty():
		event("reload", "reloaded " + ", ".join(done))
		_refresh_screens()
		_notice("Live update: " + ", ".join(done), NOTE)
	if not _to_import.is_empty():
		_import_pictures([])


## On the main thread, every frame: what the watcher found, reloaded.
func _watch_step(_delta: float) -> void:
	if _changed.is_empty() and _changed_sheets.is_empty():
		return   # (no lock: a read of the size is enough to skip)
	_watch_mutex.lock()
	var changed := _changed
	_changed = []
	var sheets := _changed_sheets
	_changed_sheets = []
	for p in _fresh:
		_new_files[p] = true
	_fresh = []
	_watch_mutex.unlock()
	for f in sheets:
		if not _cutting.has(f):
			_cut_sheet(f)
	if not changed.is_empty():
		reload(changed)


## Cuts a changed tile sheet into its pieces (data/sprites/tile_*.png) on a
## thread; the watcher then reloads them.
func _cut_sheet(f: String) -> void:
	event("reload", "%s changed - cutting its pieces (tools/extract_sprites.py)" % f)
	var th := Thread.new()
	_cutting[f] = th
	th.start(func():
		var out := []
		var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/extract_sprites.py"), f], out, true)
		_cut_done.call_deferred(f, code, "".join(out)))


func _cut_done(f: String, code: int, out: String) -> void:
	var th: Thread = _cutting.get(f)
	if th:
		th.wait_to_finish()
	_cutting.erase(f)
	if code == 0:
		event("reload", "%s cut: %d pieces" % [f, out.count("\n")])   # (the watcher finds them changed)
	else:
		event("error", "cutting %s failed (%d): %s" % [f, code, out.right(400)])


func set_auto_reload(on: bool) -> void:
	auto_reload = on
	if on:
		_start_watch()
		set_process(true)
	else:
		_stop_watch()
	event("reload", "hot reload " + ("on" if on else "off"))


# --- The developer menu (Alt + right-click) -----------------------------------------

func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and mb.alt_pressed:
		get_viewport().set_input_as_handled()
		open_menu(mb.position)


func open_menu(at: Vector2) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		_menu.id_pressed.connect(_on_menu)
		_speeds = PopupMenu.new()
		_speeds.name = "Speeds"
		for i in 5:
			_speeds.add_radio_check_item(["×0.25", "×0.5", "×1", "×2", "×4"][i], i)
		_speeds.id_pressed.connect(func(i): Engine.time_scale = [0.25, 0.5, 1.0, 2.0, 4.0][i])
		_menu.add_child(_speeds)
		add_child(_menu)
	_menu.clear()
	_picked.clear()
	var thing := pick_at(at)
	if thing:
		_menu.add_item("Inspect  " + _label(thing), 100)
		_picked.append(thing)
	var ui := get_viewport().gui_get_hovered_control()
	if ui and ui != thing:
		_menu.add_item("Inspect UI  " + _label(ui), 100 + _picked.size())
		_picked.append(ui)
	if _picked.size() > 0:
		_menu.add_separator()
	_menu.add_check_item("Inspector", 1)
	_menu.set_item_checked(_menu.get_item_index(1), inspector != null and inspector.visible)
	_menu.add_separator()
	_menu.add_check_item("Pause", 2)
	_menu.set_item_checked(_menu.get_item_index(2), get_tree().paused)
	_menu.add_submenu_node_item("Game speed", _speeds, 3)
	for i in 5:
		_speeds.set_item_checked(i, is_equal_approx(Engine.time_scale, [0.25, 0.5, 1.0, 2.0, 4.0][i]))
	_menu.add_check_item("Hot reload (watch files)", 4)
	_menu.set_item_checked(_menu.get_item_index(4), auto_reload)
	_menu.add_item("Screenshot", 5)
	_menu.reset_size()
	# (an embedded menu is placed in the game view's coordinates, a native one on the screen)
	var origin := Vector2i.ZERO if get_viewport().gui_embed_subwindows else get_window().position
	_menu.popup(Rect2i(Vector2i(at) + origin, Vector2i.ZERO))


func _label(o: Object) -> String:
	var s: String = inspector.node_label(o) if o is Node and inspector else (str(o.name) if o is Node else o.get_class())
	if o.get_script() and o.get_script().resource_path != "":
		s += "  (%s)" % o.get_script().resource_path.get_file().get_basename()
	return s


func _on_menu(id: int) -> void:
	match id:
		1:
			if inspector and inspector.visible:
				inspector.hide()
			else:
				open_inspector(null)
		2:
			get_tree().paused = not get_tree().paused
		4:
			set_auto_reload(not auto_reload)
		5:
			var r := _shot("user://shot_%d.png" % Time.get_unix_time_from_system())
			if r["ok"]:
				event("print", "screenshot: " + str(r["result"]["path"]))
		_:
			if id >= 100 and id - 100 < _picked.size() and is_instance_valid(_picked[id - 100]):
				open_inspector(_picked[id - 100])


func open_inspector(obj: Object) -> void:
	if inspector == null:
		inspector = preload("res://scripts/core/dev_inspector.gd").new()
		add_child(inspector)
	if not inspector.visible:
		inspector.open()
	if obj:
		inspector.inspect(obj)


## The game object under a screen point: the nearest scripted Node2D in the
## world (not the HUD) within its click radius (or 40 screen px).
func pick_at(screen: Vector2) -> Node2D:
	var m := main()
	var vp := get_viewport()
	if m == null:
		return null
	var ct := vp.get_canvas_transform()
	var world := ct.affine_inverse() * screen
	var zoom := ct.get_scale().x
	var world_canvas := vp.find_world_2d().canvas
	var best: Node2D = null
	var best_d := INF
	var stack: Array = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is CanvasLayer or c is Control or c is Window:
				continue
			stack.append(c)
			if not (c is Node2D) or c.get_script() == null or not c.is_visible_in_tree():
				continue
			if c.get_canvas() != world_canvas:
				continue
			var r: float = 40.0 / maxf(zoom, 0.0001)
			var cr = c.get("click_radius")
			if cr is float or cr is int:
				r = maxf(r, float(cr))
			var d: float = c.global_position.distance_to(world) / r
			if d < 1.0 and d < best_d:
				best_d = d
				best = c
	return best


# --- Looking at things -------------------------------------------------------------

func snapshot() -> Dictionary:
	var m := main()
	var out := {
		"fps": Engine.get_frames_per_second(),
		"paused": get_tree().paused,
		"time_scale": Engine.time_scale,
		"scene": get_tree().current_scene.name if get_tree().current_scene else "",
		"in_game": m != null,
	}
	if m == null:
		return out
	var ship: Node2D = m.get("ship")
	if ship:
		out["ship"] = {
			"pos": ship.global_position,
			"vel": ship.get("velocity"),
			"hull": ship.get("hull"), "max_hull": ship.get("max_hull"),
			"shield": ship.get("shield"), "max_shield": ship.get("max_shield"),
		}
	var site = m.get("site")
	if is_instance_valid(site):
		var sig: Dictionary = site.get("sig")
		out["site"] = {"kind": site.get("kind"), "id": sig.get("id", ""),
			"level": sig.get("level", ""), "seed": sig.get("seed", 0)}
	var foes := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		foes.append({
			"name": str(e.name),
			"type": e.get("type_id") if e.get("type_id") != null else e.get_script().resource_path.get_file() if e.get_script() else e.get_class(),
			"hull": e.get("hull"), "max_hull": e.get("max_hull"),
			"pos": e.global_position,
			"dist": e.global_position.distance_to(ship.global_position) if ship else 0.0,
		})
	foes.sort_custom(func(a, b): return a["dist"] < b["dist"])
	out["enemies"] = foes
	return out


func _tree(n: Node, depth: int) -> Dictionary:
	var d := {"name": str(n.name), "class": n.get_class()}
	if n.get_script():
		d["script"] = n.get_script().resource_path
	if n is Node2D:
		d["pos"] = n.global_position
	if depth > 0 and n.get_child_count() > 0:
		var kids := []
		for c in n.get_children():
			if kids.size() >= 60:
				kids.append({"name": "... %d more" % (n.get_child_count() - 60)})
				break
			kids.append(_tree(c, depth - 1))
		d["children"] = kids
	elif n.get_child_count() > 0:
		d["children"] = n.get_child_count()
	return d


func _shot(path: String) -> Dictionary:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return _err("no image (headless?)")
	var p := path if path.is_absolute_path() or path.begins_with("user://") else ProjectSettings.globalize_path("user://") + path
	var err := img.save_png(p)
	if err != OK:
		return _err("can't save %s (%s)" % [p, error_string(err)])
	return _ok({"path": ProjectSettings.globalize_path(p), "size": img.get_size()})


## Any value -> something JSON can carry (vectors as [x, y], objects named).
static func jsonable(v: Variant, depth := 0) -> Variant:
	if depth > 6:
		return "..."
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return snappedf(v, 0.001) if is_finite(v) else str(v)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
		TYPE_COLOR:
			return "#" + v.to_html()
		TYPE_OBJECT:
			if not is_instance_valid(v):
				return "<freed>"
			if v is Node:
				return "<%s %s>" % [v.get_class(), v.get_path() if v.is_inside_tree() else v.name]
			if v is Resource and v.resource_path != "":
				return "<%s %s>" % [v.get_class(), v.resource_path]
			return "<%s>" % v.get_class()
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = jsonable(v[k], depth + 1)
			return d
	if v is Array or typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		var a := []
		for x in v:
			if a.size() >= 500:
				a.append("... %d more" % (v.size() - 500))
				break
			a.append(jsonable(x, depth + 1))
		return a
	return str(v)
