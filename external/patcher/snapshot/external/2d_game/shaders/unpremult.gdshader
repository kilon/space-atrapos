// Draws textures rendered into a transparent viewport (premultiplied colour)
// with normal blending: divides the colour by alpha, then applies modulate.
// Used by the planet-surface prop atlas (SurfaceProps).
shader_type canvas_item;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(t.rgb / max(t.a, 0.0001), t.a) * vcol;
}
