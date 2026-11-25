class_name Jobs
extends RefCounted
## Heavy background jobs (a town's buildings, a ship's design or hull or rooms, a
## station's bake, a dungeon, a monster, a trader's rooms): WorkerThreadPool tasks,
## asked for the same way (add / done / wait in place of add_task /
## is_task_completed / wait_for_task_completion).
##
## On the desktop they're the pool's own tasks. In a browser the low-priority ones
## run ONE AT A TIME, in the order asked: there several at once - each making
## hundreds of thousands of vertices - held the main thread back (the page's one
## memory allocator, its lock), the game at ~40 frames a second for ten seconds as
## it came in; one at a time it stays at 60. A job waited for (wait) starts at once.

static var _n := 0
static var _jobs := {}         # id -> {task: pool task (-1: not started), f, name}
static var _queue: Array = []  # (a browser) ids not started yet, in order
static var _running := -1      # (a browser) the one started from the queue
static var _hooked := false


## A job (as WorkerThreadPool.add_task): its id.
static func add(f: Callable, high_priority := false, description := "") -> int:
	_n += 1
	if high_priority or not OS.has_feature("web"):
		_jobs[_n] = {"task": WorkerThreadPool.add_task(f, high_priority, description)}
		return _n
	_jobs[_n] = {"task": -1, "f": f, "name": description}
	_queue.append(_n)
	if not _hooked:
		_hooked = true
		(Engine.get_main_loop() as SceneTree).process_frame.connect(_pump)
	_pump()
	return _n


## Done (as WorkerThreadPool.is_task_completed) - collect it with wait().
static func done(id: int) -> bool:
	var j = _jobs.get(id)
	if j == null:
		return true
	return int(j["task"]) >= 0 and WorkerThreadPool.is_task_completed(int(j["task"]))


## Waited for (as WorkerThreadPool.wait_for_task_completion): one not started yet starts now.
static func wait(id: int) -> void:
	var j = _jobs.get(id)
	if j == null:
		return
	if int(j["task"]) < 0:
		_queue.erase(id)
		j["task"] = WorkerThreadPool.add_task(j["f"], true, str(j["name"]))
	WorkerThreadPool.wait_for_task_completion(int(j["task"]))
	_jobs.erase(id)
	if _running == id:
		_running = -1
		_pump()


## (A browser, each frame) The next job started once the last is done.
static func _pump() -> void:
	if _running >= 0:
		var r = _jobs.get(_running)
		if r != null and not WorkerThreadPool.is_task_completed(int(r["task"])):
			return
		_running = -1
	while not _queue.is_empty():
		var id: int = _queue.pop_front()
		var j = _jobs.get(id)
		if j == null or int(j["task"]) >= 0:
			continue
		j["task"] = WorkerThreadPool.add_task(j["f"], false, str(j["name"]))
		_running = id
		return
