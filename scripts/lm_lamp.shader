shader_type canvas_item;
render_mode blend_add, unshaded;
// Light bake, direct pass: one additive quad per ceiling lamp, centred on it.
// Floor irradiance of a down-facing 60 cm panel, shadowed by marching toward four points
// across the lens through the wall map (soft penumbra, exact wall shadows).

uniform sampler2D walls;
uniform float res = 512.0;        // map size in px
uniform float ppm = 10.0;         // map px per metre
uniform float radius_px = 90.0;   // quad half-size
uniform float gain = 0.5;
uniform float lamp_h = 2.75;

varying vec2 cpos;
varying vec2 lpos;

void vertex() {
	cpos = (WORLD_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	lpos = (WORLD_MATRIX * vec4(vec2(radius_px), 0.0, 1.0)).xy;
}

float vis(vec2 a, vec2 b) {
	vec2 d = b - a;
	for (int i = 1; i < 30; i++) {
		if (texture(walls, (a + d * (float(i) / 30.0)) / res).r > 0.35) {
			return 0.0;
		}
	}
	return 1.0;
}

void fragment() {
	vec2 dpx = cpos - lpos;
	float dm = length(dpx) / ppm;
	float h2 = lamp_h * lamp_h;
	float rm = radius_px / ppm;
	float f = pow(h2 / (dm * dm + h2), 1.5) * (1.0 - smoothstep(rm * 0.7, rm, dm));
	float v = 0.0;
	if (f > 0.002) {
		vec2 side = normalize(vec2(-dpx.y, dpx.x) + vec2(0.0001, 0.0)) * 0.25 * ppm;
		v = 0.25 * (vis(cpos, lpos + side) + vis(cpos, lpos - side) + vis(cpos, lpos + side * 0.33) + vis(cpos, lpos - side * 0.33));
	}
	float dither = (fract(sin(dot(cpos, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	COLOR = vec4(vec3(max(0.0, f * v * gain + dither)), 1.0);
}
