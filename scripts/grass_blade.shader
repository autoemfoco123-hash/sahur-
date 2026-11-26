shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
// Meadow grass (MultiMesh): a tapered blade, darker at the root, sunlit at the tip, swaying in
// a slow wind that rolls across the field in waves.

uniform vec4 root_col : hint_color = vec4(0.12, 0.33, 0.07, 1.0);
uniform vec4 tip_col : hint_color = vec4(0.48, 0.8, 0.22, 1.0);
uniform float wind = 1.0;

varying float hgt;

void vertex() {
	hgt = UV.y;
	vec3 w = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float wave = sin(TIME * 1.3 + w.x * 0.18 + w.z * 0.11) * 0.6 + sin(TIME * 2.9 + w.x * 0.7 - w.z * 0.5) * 0.25;
	float bend = hgt * hgt * wind;
	VERTEX.x += wave * 0.12 * bend;
	VERTEX.z += wave * 0.05 * bend;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(root_col.rgb, tip_col.rgb, hgt * hgt);
	ROUGHNESS = 0.9;
}
