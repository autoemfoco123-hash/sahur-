shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
// Meadow grass (MultiMesh, one instance per blade; instance colour = its own green).
// Wind: a steady lean, gusts that roll across the whole field in long waves (the bent blades
// catch the light, so you see each gust travel), and a quick flutter. Near the edge of the grass
// around you the blades shrink into the ground, so the end of it never shows.

uniform vec4 root_col : hint_color = vec4(0.09, 0.21, 0.04, 1.0);
uniform vec4 tip_col : hint_color = vec4(0.46, 0.7, 0.19, 1.0);
uniform vec2 wind_dir = vec2(0.83, 0.55);
uniform float wind = 1.0;
uniform vec2 fade = vec2(22.0, 30.0);

varying float hgt;
varying float gust;
varying vec3 tint;

void vertex() {
	hgt = UV.y;
	tint = COLOR.rgb;
	vec3 w = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = CAMERA_MATRIX[3].xyz;
	float f = 1.0 - smoothstep(fade.x, fade.y, length(w.xz - cam.xz));
	float along = dot(w.xz, wind_dir);
	gust = 0.5 + 0.5 * sin(along * 0.085 - TIME * 1.6 + sin(w.x * 0.04 + w.z * 0.03 + TIME * 0.25) * 1.8);
	gust = gust * gust;
	float sway = sin(TIME * 1.15 + w.x * 0.21 + w.z * 0.13 + COLOR.a * 6.28) * 0.2
		+ sin(TIME * 4.6 + w.x * 1.7 - w.z * 1.3 + COLOR.a * 12.0) * 0.07 * (0.4 + gust);
	float bend = (0.16 + gust * 0.6 + sway) * wind * hgt * hgt;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * bend * 0.36;
	// into the blade's own space (its basis is a rotation and a scale per axis)
	vec3 c0 = WORLD_MATRIX[0].xyz;
	vec3 c1 = WORLD_MATRIX[1].xyz;
	vec3 c2 = WORLD_MATRIX[2].xyz;
	VERTEX += vec3(dot(off, c0) / dot(c0, c0), dot(off, c1) / dot(c1, c1), dot(off, c2) / dot(c2, c2));
	VERTEX.y -= bend * bend * 0.09;
	VERTEX *= f;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.62));
}

void fragment() {
	vec3 c = mix(root_col.rgb, tip_col.rgb, smoothstep(0.0, 1.0, hgt)) * tint;
	c *= 0.5 + 0.5 * smoothstep(0.0, 0.4, hgt);       // the roots stand in each other's shade
	c += vec3(0.07, 0.08, 0.025) * gust * hgt;          // bent over, they catch the light
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
