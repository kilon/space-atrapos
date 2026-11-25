// The flight HUD's sights (CosmosHud): not drawn where your ship covers the screen - the ship over
// them. ship_mask: the ship alone, drawn by a camera that sees only it (its alpha: where it is).
shader_type canvas_item;

uniform sampler2D ship_mask : hint_default_transparent, filter_linear;

void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.2, 0.8, texture(ship_mask, SCREEN_UV).a);
}
