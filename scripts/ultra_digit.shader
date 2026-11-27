shader_type spatial;
// The 6 and the 7 on 6-7 ULTRA's scale: stone glowing red-hot right through, pulsing with its
// heartbeat, cracked black where the surface has cooled. heat: the number it is calling burns
// white-hot. Godot 3 / GLES2.

uniform float heat = 0.0;
uniform float pulse_rate = 1.1;
uniform float glow = 1.0;
uniform float hurt = 0.0;
uniform float dying = 0.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	ALBEDO = vec3(0.09, 0.02, 0.015);
	ROUGHNESS = 0.16;
	SPECULAR = 0.85;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float beat = pow(0.5 + 0.5 * sin(TIME * pulse_rate * 6.2831), 6.0);
	// a web of cracks through the stone (two warped sine fields, their zero lines)
	float c1 = abs(sin(lp.x * 2.3 + sin(lp.y * 1.7 + lp.z * 3.1) * 1.9));
	float c2 = abs(sin(lp.y * 2.9 + sin(lp.x * 2.2 - lp.z * 2.5) * 1.6 + 1.3));
	float crack = smoothstep(0.07, 0.0, c1) + smoothstep(0.05, 0.0, c2) * 0.8;
	vec3 red = vec3(1.0, 0.07, 0.03);
	float live = (1.0 - dying) * glow;
	// red-hot right through, the cracks black where the surface has cooled
	// brightest on the faces turned to you, darker down the sides: you see it is solid
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 em = red * (0.14 + 0.62 * facing * facing + 0.22 * beat) * (1.0 - crack * 0.75) * live;
	em += mix(red, vec3(1.0, 0.82, 0.66), 0.55) * heat * (0.45 + crack * 1.8 + rim * 1.4);
	em += vec3(1.0, 0.65, 0.5) * hurt * (0.4 + rim);
	EMISSION = em;
}
