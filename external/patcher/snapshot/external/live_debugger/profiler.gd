extends SceneTree
## The script profiler server for tools/fps_test.py --profile: the game
## connects to it (godot ... --remote-debug tcp://127.0.0.1:PORT); it turns on
## Godot's own scripts profiler ("profiler:servers") and adds up each
## function's time per scenario - the tour (tests/fps_tour.gd) prints
## "@@profile <scenario>" when one starts being measured and "@@profile -"
## when it ends. Writes the totals as JSON when the game disconnects.
##   godot --headless --path external/live_debugger -s profiler.gd -- PORT OUT.json

var _srv := TCPServer.new()
var _game: StreamPeerTCP
var _buf := PackedByteArray()
var _out := ""
var _names := {}          # signature id -> "file:line:function"
var _bucket := ""         # the scenario being measured ("" between)
var _data := {}           # scenario -> {frames, funcs: {name: [calls, self_ms, total_ms]}}
var _raw_dumped := 0
var _spike_s := float(OS.get_environment("PROFILE_SPIKE_MS")) / 1000.0 if OS.get_environment("PROFILE_SPIKE_MS") != "" else 0.024


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 6017
	_out = args[1] if args.size() > 1 else "profile.json"
	if _srv.listen(port, "127.0.0.1") != OK:
		printerr("profiler: port %d busy" % port)
		quit(1)
		return
	print("profiler: waiting on %d" % port)
	process_frame.connect(_poll)


func _send(name: String, data: Array) -> void:
	var b := var_to_bytes([name, 1, data])
	_game.put_u32(b.size())
	_game.put_data(b)


func _poll() -> void:
	OS.delay_msec(2)
	if _game == null and _srv.is_connection_available():
		_game = _srv.take_connection()
		_game.set_no_delay(true)
		_send("profiler:servers", [true, [512, false]])
		print("profiler: game connected")
	if _game == null:
		return
	_game.poll()
	if _game.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_save()
		quit(0)
		return
	var n := _game.get_available_bytes()
	if n > 0:
		_buf.append_array(_game.get_data(n)[1])
	while _buf.size() >= 4:
		var size := _buf.decode_u32(0)
		if _buf.size() < 4 + size:
			break
		var msg: Variant = bytes_to_var(_buf.slice(4, 4 + size))
		_buf = _buf.slice(4 + size)
		if msg is Array and msg.size() == 3:
			_on(str(msg[0]), msg[2] if msg[2] is Array else [])


func _on(name: String, data: Array) -> void:
	match name:
		"output":
			for s in Array(data[0]) if data.size() > 0 else []:
				for line in str(s).split("\n"):
					if line.begins_with("@@profile "):
						_bucket = line.substr(10).strip_edges()
						if _bucket == "-":
							_bucket = ""
						elif not _data.has(_bucket):
							_data[_bucket] = {"frames": 0, "funcs": {}}
		"servers:function_signature":
			# [name, id, name, id, ...] (or nested)
			var flat: Array = data[0] if data.size() == 1 and data[0] is Array else data
			var i := 0
			while i + 1 < flat.size():
				_names[int(flat[i + 1])] = str(flat[i])
				i += 2
		"servers:profile_frame":
			if _raw_dumped < 2 and OS.get_environment("PROFILER_RAW") != "":
				_raw_dumped += 1
				print("RAW ", var_to_str(data).left(3000))
			if _bucket == "":
				return
			_frame(data)


## ServersProfilerFrame: frame_number, frame_time, process_time, physics_time,
## physics_frame_time, script_time, servers (count, then per server: name,
## count, [name, time]...), script functions (count, then per function: sig
## id, call count, self time, total time, internal time).
func _frame(d: Array) -> void:
	var b: Dictionary = _data[_bucket]
	b["frames"] += 1
	# Slow frames (over 1/120 s) also add into "slow": what makes them slow.
	var slow := float(d[1]) > 1.0 / 120.0
	if slow:
		b["slow_frames"] = int(b.get("slow_frames", 0)) + 1
		if not b.has("slow"):
			b["slow"] = {}
	var i := 6
	if d.size() <= i:
		return
	var servers := int(d[i])
	i += 1
	for s in servers:
		i += 1                       # name
		var n := int(d[i])
		i += 1 + n                   # (its [name, time] pairs, flattened: n values)
	if i >= d.size():
		return
	var nf := int(d[i])
	i += 1
	var f: Dictionary = b["funcs"]
	var spike: bool = float(d[1]) > _spike_s and (b.get("spikes", []) as Array).size() < 300   # (a long frame: its own list; 300 at most)
	var mine := {}
	for k in nf / 5:
		var sig := int(d[i])
		var calls := int(d[i + 1])
		var self_t := float(d[i + 2])
		var total := float(d[i + 3])
		i += 5
		var key: String = _names.get(sig, str(sig))
		if not f.has(key):
			f[key] = [0, 0.0, 0.0]
		f[key][0] += calls
		f[key][1] += self_t * 1000.0
		f[key][2] += total * 1000.0
		if spike:
			mine[key] = [calls, snappedf(self_t * 1000.0, 0.01), snappedf(total * 1000.0, 0.01)]
		if slow:
			var sf: Dictionary = b["slow"]
			if not sf.has(key):
				sf[key] = [0, 0.0, 0.0]
			sf[key][0] += calls
			sf[key][1] += self_t * 1000.0
			sf[key][2] += total * 1000.0

	if spike:
		var keys := mine.keys()
		keys.sort_custom(func(a, b): return mine[a][2] > mine[b][2])
		if not b.has("spikes"):
			b["spikes"] = []
		b["spikes"].append({"ms": snappedf(float(d[1]) * 1000.0, 0.1), "process_ms": snappedf(float(d[2]) * 1000.0, 0.1), "script_ms": snappedf(float(d[5]) * 1000.0, 0.1), "funcs": keys.slice(0, 14).map(func(k): return [k] + mine[k])})


func _save() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_data))
	f.close()
	print("profiler: saved %s (%d scenarios)" % [_out, _data.size()])
