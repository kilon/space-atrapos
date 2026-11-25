class_name TeleportGate
extends SurfaceProps.Thing
## A teleport gate on a planet surface: the Minoan portal arch (tile_xt_portal,
## the extra tile sheet) with its swirl glowing. Gates stand across the planet
## (PlanetSurface._plan_gates: by the landing pad, by every village, out in the
## wilds); click one and the portal network's map opens (SurfaceMap, gates
## mode) - pick any other gate to step through to it.

const PIECE := "xt_portal"
const HEIGHT := 150.0              # px on screen
const GLOW := Color(0.35, 0.65, 1.0)

var gate_name := ""
var index := -1                    # in the surface's gate list
var _t := 0.0
var _sprite: Sprite2D


func setup(name_: String, i: int) -> TeleportGate:
	gate_name = name_
	index = i
	title = "%s  -  click to travel the portal network" % gate_name
	height = HEIGHT * 0.8
	click_radius = 60.0
	return self


func _ready() -> void:
	_t = randf() * 10.0
	var tex := MinoanTiles.texture(PIECE)
	if tex:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		var k := HEIGHT / tex.get_height()
		_sprite.scale = Vector2(k, k)
		_sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() + 6.0 / k)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		MinoanTiles.tag(_sprite, ["piece_name", PIECE, HEIGHT])
		add_child(_sprite)


func _process(delta: float) -> void:
	_t += delta
	if UI.near_view(self) and UI.redraw_due(self):   # (off screen: its glow can wait)
		queue_redraw()


## A soft pulsing glow in the arch and light on the ground before it.
func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 70.0, Color(GLOW, 0.10 + 0.08 * pulse))
	draw_circle(Vector2.ZERO, 42.0, Color(GLOW.lightened(0.3), 0.10 + 0.10 * pulse))
	draw_set_transform(Vector2.ZERO)
	var c := Vector2(0, -HEIGHT * 0.42)
	for k in 3:
		var r := 30.0 + k * 10.0 + 4.0 * sin(_t * 3.0 + k)
		draw_arc(c, r, _t * (1.5 + k * 0.4), _t * (1.5 + k * 0.4) + PI * 1.3, 24, Color(GLOW.lightened(0.4), 0.18 - k * 0.04), 3.0, true)


## Where you stand to use it: just in front of the arch.
func approach() -> Vector2:
	return position + Vector2(0, 46)


func interact(surface: Node) -> void:
	if surface.has_method("open_gate_map"):
		surface.open_gate_map(self)
