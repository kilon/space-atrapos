shader_type spatial;
// The 3D maps' glows and rings (a MultiMesh of quads, one an instance): turned
// to the camera, the instance's size in the world but never smaller on the
// screen than INSTANCE_CUSTOM.x pixels, in the instance's colour, added on.
// INSTANCE_CUSTOM.z the kind: 0 a soft halo round a bright core (its share
// INSTANCE_CUSTOM.y); 1 a ring (a marker's: INSTANCE_CUSTOM.w px thick);
// 2 a ring that pulses (where you are); 3 an arc turning round (a system in
// a crisis) - drawn by the GPU, not redrawn by the map's scripts.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

varying vec4 v_custom;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	float px = 2.0 * max(-c.z, 0.001) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = max(s, INSTANCE_CUSTOM.x * px);
	VERTEX = c.xyz + vec3(VERTEX.xy * size, 0.0);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float kind = v_custom.z;
	if (kind < 0.5) {
		float halo = exp(-r * r * 5.0) * (1.0 - smoothstep(0.8, 1.0, r));
		float core = (1.0 - smoothstep(0.0, 0.16, r)) * v_custom.y;
		ALBEDO = COLOR.rgb * (halo * COLOR.a) + vec3(core);
	} else {
		float px = max(fwidth(r), 1e-4);
		float rr = 0.82;
		if (kind > 1.5 && kind < 2.5) {
			rr = 0.7 + 0.1 * sin(TIME * 4.0);
		}
		float half_w = max(v_custom.w, 1.0) * 0.5 * px;
		float a = 1.0 - smoothstep(half_w, half_w + px * 1.2, abs(r - rr));
		if (kind > 2.5) {
			float ang = mod(atan(q.y, q.x) - TIME * 1.2, 6.2831853);
			a *= step(ang, 4.5);
		} else if (kind > 1.5) {
			// (and a faint wider ring outside it)
			a += 0.3 * (1.0 - smoothstep(half_w * 2.5, half_w * 2.5 + px * 1.5, abs(r - rr - 0.14)));
		}
		ALBEDO = COLOR.rgb * COLOR.a * clamp(a, 0.0, 1.0);
	}
}
