shader_type spatial;
// A selection's outline (the mesh editor's part, the Live Editor's pick): the shape drawn again
// on top of itself (a material overlay), its back faces pushed out a few pixels along their normals
// in screen space - a line of the same width however far it is; drawn only outside the shape as seen
// (the stencil its first pass, outline_mark.gdshader, wrote). Skinned meshes too (VERTEX is skinned).
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;
// (only where the shape itself isn't - outline_mark.gdshader marked its pixels first)
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(1.0, 0.42, 0.0, 1.0);
uniform float width = 3.5;   // px

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 n = mat3(MODELVIEW_MATRIX) * NORMAL;
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	float len = length(dir);
	if (len > 1e-5) {
		clip.xy += dir / len * width * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
