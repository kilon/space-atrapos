extends SceneTree
## Runs every test suite in res://tests/ (files named test_*.gd).
##
##   godot --headless --path . -s tests/run_tests.gd            all suites
##   godot --headless --path . -s tests/run_tests.gd -- galaxy  suites whose name contains "galaxy"
##
## A test fails on a failed check or on any engine / script error logged
## while it runs. Exit code 0 = all passed, 1 = failures.
## Use tests/run.sh: it also protects your settings and save game.

class ErrorCatcher extends Logger:
	var errors: Array = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d %s) %s" % [code, file.get_file(), line, function, rationale])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		mutex.unlock()
		return out


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	# (a second filter: test names containing it - or a comma-separated list of names: tools/test.py)
	var only: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray()
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	# Wait for the autoloads to settle: the sprites load on background threads
	# (tests running meanwhile would race the loader, and anything it logs
	# would be blamed on whichever test was running).
	for i in 3:
		await process_frame
	var art: Node = root.get_node_or_null("ProcArt")
	var t_wait := Time.get_ticks_msec()
	while art and not art.ready_done and Time.get_ticks_msec() - t_wait < 120000:
		await process_frame
	var load_errors := catcher.take()
	if not load_errors.is_empty():
		print("Errors while loading the game's assets:")
		for e in load_errors.slice(0, 12):
			print("  - " + str(e))
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd" and (filter == "" or f.contains(filter)):
			files.append(f)
	files.sort()
	var passed := 0
	var failed: Array = []
	var t_all := Time.get_ticks_msec()
	for f in files:
		var script: Variant = load("res://tests/" + f)
		if not (script is GDScript) or not script.can_instantiate():
			print("\n== %s: does not load" % f.get_basename())
			failed.append(f.get_basename() + " (load)")
			catcher.take()
			continue
		var suite: TestCase = script.new()
		suite.tree = self
		var names: Array = []
		for m in suite.get_method_list():
			if str(m["name"]).begins_with("test_") and (only.is_empty() or Array(only).any(func(o): return str(m["name"]) == o or (only.size() == 1 and str(m["name"]).contains(o)))):
				names.append(m["name"])
		print("\n== %s (%d tests)" % [f.get_basename(), names.size()])
		for n in names:
			suite.failures = []
			suite.expect_errors = []
			catcher.take()
			var t0 := Time.get_ticks_msec()
			await suite.setup()
			await suite.call(n)
			await suite.teardown()
			await process_frame
			var errs := catcher.take()
			for e in errs:
				if not suite.expect_errors.any(func(x): return e.contains(x)):
					suite.failures.append("engine error: " + e)
			var ms := Time.get_ticks_msec() - t0
			if suite.failures.is_empty():
				passed += 1
				print("  ok    %s  (%d ms)" % [n, ms])
			else:
				failed.append("%s.%s" % [f.get_basename(), n])
				print("  FAIL  %s  (%d ms)" % [n, ms])
				for msg in suite.failures.slice(0, 12):
					print("          - " + str(msg))
				if suite.failures.size() > 12:
					print("          ... %d more" % (suite.failures.size() - 12))
	print("\n%d passed, %d failed  (%.1f s)" % [passed, failed.size(), (Time.get_ticks_msec() - t_all) / 1000.0])
	for f in failed:
		print("  failed: " + f)
	OS.remove_logger(catcher)
	quit(0 if failed.is_empty() else 1)
