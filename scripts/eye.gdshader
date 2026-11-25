shader_type spatial;
// Wet cartoon-real eyeball: white sclera with faint veins, green streaked iris, black pupil.
// The eye looks down its local -Z.

uniform vec3 iris_color : source_color = vec3(0.28, 0.62, 0.16);
uniform vec3 iris_dark : source_color = vec3(0.05, 0.2, 0.04);
uniform float iris_r = 0.56;
uniform float pupil_r = 0.24;

varying vec3 lp;

float h(float n) { return fract(sin(n * 91.7) * 43758.5); }

void fragment() {
	vec3 d = normalize(lp);
	float ang = acos(clamp(dot(d, vec3(0.0, 0.0, -1.0)), -1.0, 1.0));
	float a = atan(d.y, d.x);
	// sclera
	vec3 sclera = vec3(0.96, 0.94, 0.9);
	float vein = pow(abs(sin(a * 9.0 + sin(a * 23.0) * 0.8)), 60.0) * smoothstep(0.9, 1.5, ang);
	sclera = mix(sclera, vec3(0.75, 0.25, 0.22), vein * 0.5);
	sclera *= 1.0 - smoothstep(1.2, 1.8, ang) * 0.25;
	// iris
	float streak = 0.5 + 0.5 * sin(a * 47.0 + sin(a * 11.0) * 2.5);
	float streak2 = 0.5 + 0.5 * sin(a * 89.0 + 1.7);
	vec3 iris = mix(iris_dark, iris_color, 0.35 + 0.45 * streak * streak2 + 0.3 * (ang / iris_r));
	iris = mix(iris, iris_color * 1.35, smoothstep(pupil_r, pupil_r + 0.12, ang) * (1.0 - smoothstep(pupil_r + 0.12, pupil_r + 0.25, ang)) * 0.5);
	iris = mix(iris, iris_dark * 0.35, smoothstep(iris_r * 0.82, iris_r, ang));
	vec3 col = mix(iris, sclera, smoothstep(iris_r - 0.015, iris_r + 0.015, ang));
	col = mix(vec3(0.005), col, smoothstep(pupil_r - 0.015, pupil_r + 0.015, ang));
	ALBEDO = col;
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.0;
}

void vertex() {
	lp = VERTEX;
}
