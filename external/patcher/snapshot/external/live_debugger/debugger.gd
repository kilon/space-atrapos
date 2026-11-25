extends SceneTree
## The live debugger daemon: a remote-debugger server the game connects to
## (godot --path . --remote-debug tcp://127.0.0.1:6007 ...), driven by
## tools/live.py over a JSON line protocol on 127.0.0.1:6071. Breakpoints,
## break / step / next / out / continue, the call stack, a frame's variables,
## evaluating expressions in a frame, the game's output and errors with their
## call stacks, and hot reload through Godot's own reload_scripts.
##   godot --headless --path external/live_debugger -s debugger.gd [-- --break-on-errors]
## Messages to and from the game: [name, thread id, data: Array], each
## var_to_bytes'd behind its length (u32), as Godot's RemoteDebuggerPeerTCP does.
## By default the game doesn't stop on script errors (a game nobody is
## watching would freeze) - the errors and their stacks are logged instead.

const GAME_PORT := 6007
const CTL_PORT := 6071
const MAX_EVENTS := 3000

var _game_srv := TCPServer.new()
var _ctl_srv := TCPServer.new()
var _game: StreamPeerTCP
var _gbuf := PackedByteArray()
var _clients: Array = []                # [{peer, buf}]
var _tid := 1                           # the game's main thread id
var _break := {}                        # {} or {reason, can_continue, thread}
var _stack: Array = []                  # the last stack dump
var _vars: Array = []                   # frame vars being gathered
var _vars_left := 0
var _waiting: Array = []                # [{kind, peer, ...}] replies due from the game
var _breakpoints := {}                  # "res://x.gd:12" -> true
var _events: Array = []
var _seq := 0
var _break_on_errors := false
var _sessions := 0


func _init() -> void:
	_break_on_errors = "--break-on-errors" in OS.get_cmdline_user_args()
	if _game_srv.listen(GAME_PORT, "127.0.0.1") != OK or _ctl_srv.listen(CTL_PORT, "127.0.0.1") != OK:
		printerr("live debugger: ports %d / %d are busy (already running?)" % [GAME_PORT, CTL_PORT])
		quit(1)
		return
	print("live debugger: waiting for the game on %d, commands on %d" % [GAME_PORT, CTL_PORT])
	process_frame.connect(_poll)


func _event(kind: String, data: Variant) -> void:
	_seq += 1
	_events.append({"seq": _seq, "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "kind": kind, "data": data})
	if _events.size() > MAX_EVENTS:
		_events = _events.slice(_events.size() - MAX_EVENTS)


# --- The game side -------------------------------------------------------------------

func _send(name: String, data: Array = []) -> bool:
	if _game == null or _game.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var b := var_to_bytes([name, _break.get("thread", _tid), data])
	_game.put_u32(b.size())
	_game.put_data(b)
	return true


func _poll() -> void:
	OS.delay_msec(4)
	if _game_srv.is_connection_available():
		if _game:
			_game.disconnect_from_host()
		_game = _game_srv.take_connection()
		_game.set_no_delay(true)
		_gbuf.clear()
		_break = {}
		_sessions += 1
		_event("connected", {"session": _sessions})
		for k in _breakpoints:
			_send_breakpoint(k, true)
		_send("set_ignore_error_breaks", [not _break_on_errors])
	if _game:
		_game.poll()
		if _game.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_event("disconnected", {"session": _sessions})
			_game = null
			_break = {}
			_answer_all({"ok": false, "error": "the game closed"})
		else:
			var n := _game.get_available_bytes()
			if n > 0:
				_gbuf.append_array(_game.get_data(n)[1])
			while _gbuf.size() >= 4:
				var size := _gbuf.decode_u32(0)
				if _gbuf.size() < 4 + size:
					break
				var msg: Variant = bytes_to_var(_gbuf.slice(4, 4 + size))
				_gbuf = _gbuf.slice(4 + size)
				if msg is Array and msg.size() == 3:
					_on_game(str(msg[0]), int(msg[1]), msg[2] if msg[2] is Array else [])
	_poll_ctl()


func _on_game(name: String, tid: int, data: Array) -> void:
	match name:
		"debug_enter":
			# [can_continue, reason, has_stack, thread id]
			_break = {"can_continue": data[0], "reason": str(data[1]), "thread": data[3] if data.size() > 3 else tid}
			_event("break", _break)
			_send("get_stack_dump")
		"debug_exit":
			_break = {}
			_event("continue", {})
		"stack_dump":
			# [n (= frames x 3), file, line, function, file, line, function, ...]
			_stack = []
			var i := 1 if data.size() > 0 and typeof(data[0]) == TYPE_INT else 0
			while i + 2 < data.size():
				_stack.append({"file": str(data[i]), "line": int(data[i + 1]), "function": str(data[i + 2])})
				i += 3
			_answer("stack", {"ok": true, "result": _stack})
			if not _break.is_empty() and not _break.has("where") and not _stack.is_empty():
				_break["where"] = _stack[0]
				_event("stack", {"stack": _stack, "reason": _break.get("reason", "")})
		"stack_frame_vars":
			_vars = []
			_vars_left = int(data[0]) if data.size() > 0 else 0
			if _vars_left == 0:
				_answer("vars", {"ok": true, "result": []})
		"stack_frame_var":
			_vars.append(_var(data))
			_vars_left -= 1
			if _vars_left <= 0:
				_answer("vars", {"ok": true, "result": _vars})
		"evaluation_return":
			var v := _var(data)
			_answer("eval", {"ok": true, "result": v})
		"output":
			# [strings, types]: 0 log, 1 error, 2 rich
			var strings: Array = Array(data[0]) if data.size() > 0 else []
			var types: Array = Array(data[1]) if data.size() > 1 else []
			for i in strings.size():
				_event("error" if i < types.size() and int(types[i]) == 1 else "print", str(strings[i]))
		"error":
			var e := _error(data)
			_event("warning" if e.get("warning", false) else "error", e)
		_:
			if name.begins_with("performance") or name.begins_with("scene:") or name.begins_with("servers:") \
					or name.begins_with("profiler") or name.begins_with("visual") or name.begins_with("multiplayer"):
				return
			_event("message", {"name": name, "data": _plain(data)})


## A ScriptStackVariable: [name, type (0 local, 1 member, 2 global, 3 eval), var type, value].
func _var(d: Array) -> Dictionary:
	var kinds := ["local", "member", "global", "eval"]
	var k: int = int(d[1]) if d.size() > 1 else 0
	return {"name": str(d[0]) if d.size() > 0 else "", "scope": kinds[k] if k < 4 else str(k),
		"value": _plain(d[3] if d.size() > 3 else d.back())}


## An error report (OutputError.serialize): find its message, place and stack.
func _error(d: Array) -> Dictionary:
	var out := {"raw": _plain(d)}
	# [hr, min, sec, msec, source_file, source_func, source_line, error, error_descr, warning, callstack...]
	if d.size() >= 10:
		out = {"file": str(d[4]), "function": str(d[5]), "line": d[6], "error": str(d[7]),
			"description": str(d[8]), "warning": bool(d[9])}
		var frames := []
		var i := 10
		if d.size() > i:
			var n := int(d[i])
			i += 1
			for f in n:
				if i + 3 <= d.size():
					frames.append({"file": str(d[i]), "function": str(d[i + 1]), "line": d[i + 2]})
				i += 3
		out["stack"] = frames
	return out


func _plain(v: Variant) -> Variant:
	if v is Array or (typeof(v) >= TYPE_PACKED_BYTE_ARRAY):
		var a := []
		for x in v:
			if a.size() > 200:
				a.append("...")
				break
			a.append(_plain(x))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _plain(v[k])
		return d
	if v is Object:
		if v is EncodedObjectAsID:
			return "<object #%d>" % v.object_id
		return "<%s>" % v.get_class()
	if typeof(v) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]:
		return v
	if typeof(v) == TYPE_FLOAT:
		return snappedf(v, 0.001) if is_finite(v) else str(v)
	return var_to_str(v)


# --- The control side (tools/live.py) ----------------------------------------------

func _poll_ctl() -> void:
	while _ctl_srv.is_connection_available():
		var p := _ctl_srv.take_connection()
		_clients.append({"peer": p, "buf": PackedByteArray()})
	for c in _clients.duplicate():
		var p: StreamPeerTCP = c["peer"]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var n := p.get_available_bytes()
		if n > 0:
			c["buf"].append_array(p.get_data(n)[1])
		var nl: int = c["buf"].find(10)
		while nl >= 0:
			var line: String = c["buf"].slice(0, nl).get_string_from_utf8()
			c["buf"] = c["buf"].slice(nl + 1)
			nl = c["buf"].find(10)
			var req: Variant = JSON.parse_string(line)
			if req is Dictionary:
				_command(p, req)
	# Replies the game never gave (it ran on, or hung): give up after a while.
	for w in _waiting.duplicate():
		if Time.get_ticks_msec() > w["until"]:
			_waiting.erase(w)
			_reply(w["peer"], {"ok": false, "error": "no answer from the game (is it stopped at a break?)"})


func _reply(p: StreamPeerTCP, r: Dictionary) -> void:
	if p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		p.put_data((JSON.stringify(r) + "\n").to_utf8_buffer())


func _wait(kind: String, p: StreamPeerTCP) -> void:
	_waiting.append({"kind": kind, "peer": p, "until": Time.get_ticks_msec() + 3000})


func _answer(kind: String, r: Dictionary) -> void:
	for w in _waiting.duplicate():
		if w["kind"] == kind:
			_waiting.erase(w)
			_reply(w["peer"], r)
			return


func _answer_all(r: Dictionary) -> void:
	for w in _waiting:
		_reply(w["peer"], r)
	_waiting.clear()


func _send_breakpoint(key: String, on: bool) -> void:
	var file := key.rsplit(":", true, 1)[0]
	var line := int(key.rsplit(":", true, 1)[1])
	_send("breakpoint", [file, line, on])


func _res(f: String) -> String:
	if f.begins_with("res://"):
		return f
	return "res://" + f.trim_prefix("./")


func _command(p: StreamPeerTCP, req: Dictionary) -> void:
	var cmd := str(req.get("cmd", ""))
	var connected := _game != null and _game.get_status() == StreamPeerTCP.STATUS_CONNECTED
	match cmd:
		"status":
			_reply(p, {"ok": true, "result": {"connected": connected, "break": _break,
				"breakpoints": _breakpoints.keys(), "break_on_errors": _break_on_errors, "last": _seq}})
			return
		"events":
			var since := int(req.get("since", 0))
			_reply(p, {"ok": true, "result": {"events": _events.filter(func(e): return e["seq"] > since), "last": _seq}})
			return
		"break":   # {file, line, on}: a breakpoint
			var key := "%s:%d" % [_res(str(req.get("file", ""))), int(req.get("line", 0))]
			var on := bool(req.get("on", true))
			if on:
				_breakpoints[key] = true
			else:
				_breakpoints.erase(key)
			_send_breakpoint(key, on)
			_reply(p, {"ok": true, "result": _breakpoints.keys()})
			return
		"clear":
			for k in _breakpoints:
				_send_breakpoint(k, false)
			_breakpoints.clear()
			_reply(p, {"ok": true, "result": []})
			return
		"errors":   # {on}: stop the game at script errors
			_break_on_errors = bool(req.get("on", true))
			_send("set_ignore_error_breaks", [not _break_on_errors])
			_reply(p, {"ok": true, "result": {"break_on_errors": _break_on_errors}})
			return
	if not connected:
		_reply(p, {"ok": false, "error": "the game isn't connected (start it with --remote-debug tcp://127.0.0.1:%d)" % GAME_PORT})
		return
	match cmd:
		"pause":   # stop the game where it is
			_send("break")
			_reply(p, {"ok": true, "result": "break requested"})
		"step", "next", "out", "continue":
			if _break.is_empty():
				_reply(p, {"ok": false, "error": "the game isn't stopped"})
				return
			_send(cmd)
			_reply(p, {"ok": true, "result": cmd})
		"stack":
			if _break.is_empty():
				_reply(p, {"ok": false, "error": "the game isn't stopped (the stack is only there at a break)"})
				return
			_wait("stack", p)
			_send("get_stack_dump")
		"vars":
			if _break.is_empty():
				_reply(p, {"ok": false, "error": "the game isn't stopped"})
				return
			_wait("vars", p)
			_send("get_stack_frame_vars", [int(req.get("frame", 0))])
		"eval":
			_wait("eval", p)
			_send("evaluate", [str(req.get("expr", "")), int(req.get("frame", 0 if not _break.is_empty() else -1))])
		"reload":
			var paths: Array = req.get("paths", [])
			if paths.is_empty():
				_send("reload_all_scripts")
			else:
				_send("reload_scripts", paths.map(func(x): return _res(str(x))))
			_reply(p, {"ok": true, "result": "reload sent"})
		_:
			_reply(p, {"ok": false, "error": "unknown command " + cmd})
