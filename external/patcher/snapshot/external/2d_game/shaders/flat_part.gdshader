shader_type spatial;
// A flat colour for the 3D characters (Stage3D): their glowing lights, and the
// ink outline (the model's inverted hull: only its far side shows).
render_mode unshaded, cull_back;

uniform vec3 color = vec3(0.01, 0.008, 0.02);      // (linear)

void fragment() {
	ALBEDO = color;
}
