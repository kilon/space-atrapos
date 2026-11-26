extends Node
## Autoload "Settings": display, text-size, sound and CRT-filter settings,
## stored in user://settings.cfg and applied at startup.

## Emitted when any text size changes, so open screens can rescale.
signal text_scale_changed

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const DEFAULT_RESOLUTION := Vector2i(1920, 1080)

## No text smaller than this (px), anywhere - menus, HUD, text drawn on
## screen - whatever the text size settings: it stays easy to read.
const MIN_FONT := 12
## Text size slider range (1.0 = 100%).
const TEXT_SCALE_MIN := 0.5
const TEXT_SCALE_MAX := 3.0
const TEXT_SCALE_STEP := 0.05
## Kinds of text, each with its own size setting (id -> label in the menu).
const TEXT_CATEGORIES := {
	"hud": "HUD",
	"dialogue": "Story dialogue",
	"menu": "Menus & panels",
	"world": "Labels in space",
}

var resolution := DEFAULT_RESOLUTION
var fullscreen := false
var text_scale := {"hud": 1.0, "dialogue": 1.0, "menu": 1.0, "world": 1.0}
## Volumes, 0 (off) .. 1 (full): everything (the Master bus), the music (the
## Music bus, see Music), the sound effects (the SFX bus, see Sfx) and the
## characters' voices (the Voice bus, see Voice).
const VOLUMES := {"master": "Master", "music": "Music", "sfx": "Sound effects", "voice": "Voices"}
const VOLUME_DEFAULTS := {"master": 1.0, "music": 0.7, "sfx": 1.0, "voice": 0.8}
var master_volume := 1.0
var music_volume := 0.7
var sfx_volume := 1.0
var voice_volume := 0.8

## The CRT filter (CrtFilter, shaders/crt.gdshader): off in normal play by
## default, on during attract mode by default. Every shader parameter can be
## tuned on its own settings page: [id, label, min, max, step, default,
## shown x (so 0.38 reads 38), unit, tooltip].
const CRT_PARAMS := [
	["curvature", "Curvature", 0.0, 0.2, 0.005, 0.07, 100.0, "", "How much the glass bulges (0 = flat)."],
	["corner", "Round corners", 0.0, 0.15, 0.005, 0.035, 100.0, "", "How rounded the tube's corners are (0 = square)."],
	["scanline_px", "Scanline size", 2.0, 8.0, 0.5, 3.0, 1.0, " px", "Screen pixels per scanline."],
	["scanline_strength", "Scanlines", 0.0, 1.0, 0.01, 0.38, 100.0, "%", "How dark the gaps between the scanlines are."],
	["mask_strength", "Phosphor mask", 0.0, 0.5, 0.01, 0.14, 100.0, "%", "The red, green and blue stripes of the screen."],
	["fringe_px", "Colour fringe", 0.0, 4.0, 0.1, 1.2, 1.0, " px", "Red and blue drift apart toward the edges."],
	["vignette", "Dark rim", 0.0, 1.0, 0.01, 0.32, 100.0, "%", "How much darker the edges of the tube are."],
	["brightness", "Brightness", 0.6, 1.8, 0.01, 1.2, 100.0, "%", "Overall brightness (makes up for the dark scanlines)."],
	["flicker", "Flicker", 0.0, 0.06, 0.002, 0.012, 100.0, "%", "A fast shimmer of the picture."],
	["roll", "Rolling band", 0.0, 0.2, 0.005, 0.04, 100.0, "%", "A faint bright band slowly rolling down the screen."],
]
## The FPS counter (FpsCounter): a small frame-rate readout in a corner, with
## its graph; the settings page has a switch for it. On by default while the
## game is run from the project (development), off in exported builds (the
## versions players get: itch.io, the downloads).
static func fps_counter_default() -> bool:
	return not OS.has_feature("template")
var fps_counter := fps_counter_default()

## Autosaves (SaveGame.autosave): every this many minutes (0: never), and
## (autosave_events) on docking, arriving in a system and landing.
const AUTOSAVE_CHOICES := [0, 2, 5, 10, 15, 30]
const AUTOSAVE_DEFAULT := 5
var autosave_minutes := AUTOSAVE_DEFAULT
var autosave_events := true

func set_fps_counter(on: bool) -> void:
	fps_counter = on
	_queue_save()


## How the characters on foot are drawn: "3d" - the automaton's actual 3D model,
## live (Stage3D; the pirates from the sprites rendered from theirs); "sprites" -
## the animations rendered from the models, for all; "classic" - the hand-drawn
## two-pose sheets (the backup). Characters made after the change follow it (the
## next landing).
const CHARACTER_GRAPHICS := [["3d", "3D model"], ["sprites", "Rendered sprites"], ["classic", "Classic sprites"]]
var character_graphics := "3d"

func set_character_graphics(mode: String) -> void:
	character_graphics = mode if CHARACTER_GRAPHICS.any(func(m): return m[0] == mode) else "3d"
	_apply_character_graphics()
	_queue_save()


func _apply_character_graphics() -> void:
	SheetPuppet.classic = character_graphics == "classic"
	SheetPuppet.model3d = character_graphics == "3d"


## Anti-aliasing (the 3D game's view: edges, the stars, thin plants): its
## modes, from none to the smoothest. MSAA smooths geometry's edges, FXAA
## blurs jagged edges cheaply after the picture's drawn, TAA (temporal) also
## steadies what shimmers from frame to frame (stars, grass) at a little blur.
const ANTIALIAS := [["off", "Off"], ["fxaa", "FXAA (fastest)"], ["msaa2", "MSAA 2x + FXAA"], ["msaa4", "MSAA 4x + FXAA"],
	["msaa8", "MSAA 8x + FXAA"], ["taa", "TAA + MSAA 2x (steadiest)"]]
var antialias := "msaa2"

func set_antialias(mode: String) -> void:
	antialias = mode if ANTIALIAS.any(func(m): return m[0] == mode) else "msaa2"
	apply_antialias()
	_queue_save()


func apply_antialias() -> void:
	var vp := get_tree().root if is_inside_tree() else null
	if vp == null:
		return
	vp.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X, "msaa8": Viewport.MSAA_8X, "taa": Viewport.MSAA_2X}.get(antialias, Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if antialias in ["fxaa", "msaa2", "msaa4", "msaa8"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = antialias == "taa"


## The planets' ground as 3D geometry (Ground3D) - off: the 2D tiles drawn as
## pictures (the fallback). From the next landing.
var terrain_3d := true

func set_terrain_3d(on: bool) -> void:
	terrain_3d = on
	Ground3D.enabled = on
	_queue_save()


const CRT_ON_DEFAULT := false
const CRT_ATTRACT_DEFAULT := true
var crt_on := CRT_ON_DEFAULT                # always on
var crt_attract := CRT_ATTRACT_DEFAULT      # on during attract mode
var crt_preview := false                    # (the CRT settings page is open)
var crt := {}                               # id -> value


static func crt_default(id: String) -> float:
	for p in CRT_PARAMS:
		if p[0] == id:
			return p[5]
	return 0.0


func set_crt(id: String, value: float) -> void:
	for p in CRT_PARAMS:
		if p[0] == id:
			crt[id] = clampf(value, p[2], p[3])
	_queue_save()


func set_crt_switch(attract: bool, on: bool) -> void:
	if attract:
		crt_attract = on
	else:
		crt_on = on
	_queue_save()


## The CRT filter's parameters (not the switches) back to their defaults.
func reset_crt() -> void:
	for p in CRT_PARAMS:
		crt[p[0]] = p[5]
	_queue_save()


func _ready() -> void:
	if bot_arg() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	reset_crt()
	load_settings()
	apply()
	apply_volumes()
	# The neon GUI look (see NeonTheme), merged into Godot's default theme:
	# every Control falls back to it - including those under CanvasLayers
	# (HUD, panels) and popup windows (menus, dropdowns, tooltips), which a
	# theme set on the root window doesn't reach.
	ThemeDB.get_default_theme().merge_with(NeonTheme.build())
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.add_child.call_deferred(CrtFilter.new())
	get_tree().root.add_child.call_deferred(FpsCounter.new())


# --- Text sizes ------------------------------------------------------------------

## Text added after its screen was built - a page rebuilt after a change, a
## row added to a list - gets that screen's text size (UI.fit_text: the
## screens UI.scale_fonts scaled are marked) and never less than MIN_FONT.
## Gathered as they come, fitted once at the end of the frame (before it's drawn).
var _text_added: Array[Control] = []

func _on_node_added(n: Node) -> void:
	if not n is Control:
		return   # (most nodes added in play - shots, sparks, creatures - aren't: one check)
	if n is Label or n is Button or n is RichTextLabel or n is LineEdit or n is TextEdit or n is ItemList or n is Tree:
		if _text_added.is_empty():
			_fit_added_text.call_deferred()
		_text_added.append(n)


func _fit_added_text() -> void:
	var list := _text_added
	_text_added = []
	for n in list:
		if is_instance_valid(n) and n.is_inside_tree():
			UI.fit_text(n)


func font_scale(category: String) -> float:
	return text_scale.get(category, 1.0)


## A font size for `category`, scaled from the size it was designed at.
func fs(category: String, base_size: int) -> int:
	return maxi(MIN_FONT, roundi(base_size * font_scale(category)))


func set_text_scale(category: String, value: float) -> void:
	value = clampf(value, TEXT_SCALE_MIN, TEXT_SCALE_MAX)
	if is_equal_approx(text_scale.get(category, 1.0), value):
		return
	text_scale[category] = value
	text_scale_changed.emit()
	_queue_save()


func volume(kind: String) -> float:
	return get(kind + "_volume")


## Sets a volume ("master", "music" or "sfx", 0..1) and applies it at once.
func set_volume(kind: String, value: float) -> void:
	set(kind + "_volume", clampf(value, 0.0, 1.0))
	apply_volumes()
	_queue_save()


func set_sfx_volume(value: float) -> void:
	set_volume("sfx", value)


func apply_volumes() -> void:
	var m := AudioServer.get_bus_index("Master")
	# (--mute among the user args: playtests run silent - the saved volumes untouched)
	AudioServer.set_bus_mute(m, master_volume <= 0.001 or muted_arg())
	AudioServer.set_bus_volume_db(m, linear_to_db(maxf(master_volume, 0.001)))
	for n in ["/root/Sfx", "/root/Music", "/root/Voice"]:
		var node := get_node_or_null(n)
		if node:
			node.apply_volume()


## Sliders change values many times a second; write the file once they settle.
var _save_queued := false

func _queue_save() -> void:
	if not is_inside_tree():  # too early for timers: just save now
		save_settings()
		return
	if _save_queued:
		return
	_save_queued = true
	await get_tree().create_timer(0.5, true).timeout
	_save_queued = false
	save_settings()


## Everything back to its default: resolution, fullscreen, text sizes,
## volumes and the CRT filter.
func reset_to_defaults() -> void:
	resolution = DEFAULT_RESOLUTION
	fullscreen = false
	for category in text_scale:
		text_scale[category] = 1.0
	for k in VOLUME_DEFAULTS:
		set(k + "_volume", VOLUME_DEFAULTS[k])
	crt_on = CRT_ON_DEFAULT
	crt_attract = CRT_ATTRACT_DEFAULT
	fps_counter = fps_counter_default()
	character_graphics = "3d"
	_apply_character_graphics()
	antialias = "msaa2"
	apply_antialias()
	terrain_3d = true
	Ground3D.enabled = true
	autosave_minutes = AUTOSAVE_DEFAULT
	autosave_events = true
	reset_crt()
	apply_volumes()
	apply()
	save_settings()
	text_scale_changed.emit()


func _exit_tree() -> void:
	if _save_queued:  # quitting right after moving a slider
		save_settings()
	Icons.wait_all()   # (painting tasks still running at exit: waited for)


# --- Display ---------------------------------------------------------------------

## Resolutions that fit on the current screen.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var result: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			result.append(r)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


## A web build (itch.io and the like): the browser owns the window - no
## sizes to pick, no window to move, fullscreen only from a click.
static func on_web() -> bool:
	return OS.has_feature("web")


## A phone or a tablet (the web build on one, or a mobile export).
static func on_phone() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")


func apply() -> void:
	if on_web():
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Resize after the mode change has taken effect.
		_resize_window.call_deferred()


func _resize_window() -> void:
	# Don't open a window bigger than the screen (e.g. 1920x1080 on a laptop).
	var fits := available_resolutions()
	var size := resolution if resolution in fits else fits[-1]
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var at := window_at_arg()
	DisplayServer.window_set_position(at if at != Vector2i(-1, -1) else origin + (screen_size - size) / 2)


## `-- --window-at=X,Y` on the command line (playtests): the window goes there
## instead of the screen's centre. (-1, -1) if not given.
## The user arg --mute: the master volume at zero for this run (playtests).
static func muted_arg() -> bool:
	return "--mute" in OS.get_cmdline_user_args()


## The user arg --bot: a window opened by Claude's tools (tests, tours, shots):
## it never takes the keyboard focus, and the 3D game doesn't capture the
## mouse in it - the user works on undisturbed.
static func bot_arg() -> bool:
	return "--bot" in OS.get_cmdline_user_args()


static func window_at_arg() -> Vector2i:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--window-at="):
			var xy := a.trim_prefix("--window-at=").split(",")
			if xy.size() == 2:
				return Vector2i(int(xy[0]), int(xy[1]))
	return Vector2i(-1, -1)


# --- Saving ----------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "fullscreen", fullscreen)
	for category in text_scale:
		cfg.set_value("text", category, text_scale[category])
	for k in VOLUMES:
		cfg.set_value("audio", k, volume(k))
	cfg.set_value("display", "fps_counter", fps_counter)
	cfg.set_value("display", "character_graphics", character_graphics)
	cfg.set_value("display", "terrain_3d", terrain_3d)
	cfg.set_value("display", "antialias", antialias)
	cfg.set_value("game", "autosave_minutes", autosave_minutes)
	cfg.set_value("game", "autosave_events", autosave_events)
	cfg.set_value("crt", "on", crt_on)
	cfg.set_value("crt", "attract", crt_attract)
	for k in crt:
		cfg.set_value("crt", k, crt[k])
	cfg.save(PATH)


## The first run on a phone: the text a size up (a 1080-line screen a few inches across).
const PHONE_TEXT := {"hud": 1.3, "dialogue": 1.3, "menu": 1.25, "world": 1.2}

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		if on_phone():
			text_scale.merge(PHONE_TEXT, true)
		return
	resolution = cfg.get_value("display", "resolution", resolution)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	for category in text_scale:
		text_scale[category] = clampf(float(cfg.get_value("text", category, 1.0)), TEXT_SCALE_MIN, TEXT_SCALE_MAX)
	for k in VOLUMES:
		set(k + "_volume", clampf(float(cfg.get_value("audio", k, VOLUME_DEFAULTS[k])), 0.0, 1.0))
	fps_counter = bool(cfg.get_value("display", "fps_counter", fps_counter_default()))
	character_graphics = str(cfg.get_value("display", "character_graphics", "3d"))
	if not CHARACTER_GRAPHICS.any(func(m): return m[0] == character_graphics):
		character_graphics = "3d"
	_apply_character_graphics()
	terrain_3d = bool(cfg.get_value("display", "terrain_3d", true))
	antialias = str(cfg.get_value("display", "antialias", "msaa2"))
	apply_antialias.call_deferred()
	Ground3D.enabled = terrain_3d and OS.get_environment("SA_GROUND2D") == ""
	autosave_minutes = int(cfg.get_value("game", "autosave_minutes", AUTOSAVE_DEFAULT))
	if not autosave_minutes in AUTOSAVE_CHOICES:
		autosave_minutes = AUTOSAVE_DEFAULT
	autosave_events = bool(cfg.get_value("game", "autosave_events", true))
	crt_on = bool(cfg.get_value("crt", "on", CRT_ON_DEFAULT))
	crt_attract = bool(cfg.get_value("crt", "attract", CRT_ATTRACT_DEFAULT))
	for p in CRT_PARAMS:
		crt[p[0]] = clampf(float(cfg.get_value("crt", p[0], p[5])), p[2], p[3])
