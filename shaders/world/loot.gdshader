shader_type spatial;
// The loot left by the dead (CosmosLoot): a leather pouch tied with cord, its
// bronze clasp. Colours in the vertices (rgb), their look in alpha: 1 leather,
// 0.5 cord, 0 the bronze clasp - which catches the light now and then (a glint:
// something there to pick up, seen from a way off).

uniform float glint = 1.0;

varying float v_kind;
varying vec3 v_obj;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	v_kind = COLOR.a;
	v_obj = VERTEX;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float creases = hash3(floor(v_obj * 38.0)) * 0.12;
	if (v_kind > 0.75) {          // leather: worn, creased
		ALBEDO = c * (0.88 + creases);
		ROUGHNESS = 0.72;
		SPECULAR = 0.35;
	} else if (v_kind > 0.25) {   // cord
		ALBEDO = c * (0.8 + creases * 2.0);
		ROUGHNESS = 0.9;
	} else {                      // bronze
		ALBEDO = c;
		METALLIC = 0.9;
		ROUGHNESS = 0.32;
		float pulse = pow(max(sin(TIME * 1.7 + v_obj.x * 3.0) , 0.0), 24.0);
		EMISSION = vec3(1.0, 0.72, 0.35) * pulse * 2.5 * glint;
	}
}
