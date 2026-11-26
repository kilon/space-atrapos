class_name BgWork
## How much of the machine the game's background work (building the path
## grid, planting a planet's scenery as you walk) may use: a quarter of its
## processor threads, at least one - on a quad core, one, leaving the rest to
## the game's own frame (on four cores, every thread on the path grid starved
## the game: 30-100 ms frames). The user arg --cores=N stands in for the
## machine's count (tools/fps_test.py --cores 4: a quad core on a bigger one).

static var _n := -1


static func threads() -> int:
	if _n < 0:
		var cores := OS.get_processor_count()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--cores="):
				cores = maxi(1, int(a.trim_prefix("--cores=")))
		_n = maxi(1, cores / 4)
	return _n


## The main thread's time for background work (a planet's surface built ahead
## while you fly): paced by time, not by frames - RATE of every second (at 600
## FPS ~0.1 ms a frame, at 60 FPS ~1 ms), never more than CAP_US in one frame.
## A fixed slice a frame (1 ms) took a 600 FPS frame from 1.1 to 2.3 ms; now it
## takes about a sixteenth of the main thread whatever the frame rate.
const RATE := 0.06
const CAP_US := 2000.0
static var _bank := 0.0
static var _at := -1


## This frame's share, taken (0 if the bank's empty): spend it, then yield.
static func take() -> int:
	var now := Time.get_ticks_usec()
	if _at >= 0:
		_bank = minf(CAP_US, _bank + (now - _at) * RATE)
	_at = now
	var us := int(_bank)
	_bank -= us
	return us
