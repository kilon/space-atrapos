// 80s chrome lettering: a sky-blue to deep-blue upper half, a white-hot
// horizon line, hot pink to red lower half, and a shine sweeping across.
// Uses the local vertex position, so it works on draw_string text.
shader_type canvas_item;

uniform float top = 0.0;
uniform float bottom = 100.0;
uniform float width = 800.0;
uniform float shine_speed = 0.12;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float t = clamp((local.y - top) / (bottom - top), 0.0, 1.0);
	vec3 c;
	if (t < 0.5) {
		c = mix(vec3(0.8, 0.97, 1.0), vec3(0.18, 0.5, 1.0), smoothstep(0.0, 0.28, t));
		c = mix(c, vec3(0.06, 0.12, 0.6), smoothstep(0.28, 0.5, t));
	} else {
		c = mix(vec3(1.0, 0.4, 0.82), vec3(1.0, 0.16, 0.36), smoothstep(0.5, 0.78, t));
		c = mix(c, vec3(0.85, 0.06, 0.08), smoothstep(0.78, 1.0, t));
	}
	// Bright horizon line through the middle of the letters.
	c = mix(c, vec3(1.0, 0.95, 0.98), smoothstep(0.045, 0.0, abs(t - 0.5)));
	// Diagonal shine sweeping across every few seconds.
	float x = local.x / width + t * 0.25;
	float s = fract(TIME * shine_speed) * 2.4 - 0.7;
	c += vec3(0.7) * smoothstep(0.05, 0.0, abs(x - s));
	COLOR = vec4(c, COLOR.a);
}
