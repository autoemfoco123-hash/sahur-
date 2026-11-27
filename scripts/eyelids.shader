shader_type canvas_item;
// Waking up: eyelids over the view. open 0 = shut (black), 1 = wide open (nothing drawn).
// The lids are curved like real ones, their edges soft and lashed, and while they are only
// half open the light coming through them is a dim warm red.

uniform float open = 0.0;

float rnd(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float o = clamp(open, 0.0, 1.0);
	// distance from the eye's middle line, with the lids' curve (they meet at the corners)
	float curve = uv.x * uv.x * 1.1;
	float gap = o * 0.68 - curve * (1.0 - o * 0.55);
	float d = abs(uv.y) - gap;
	// lashes: a ragged, dark fringe along the edge
	float lash = (rnd(floor(UV.x * 260.0)) - 0.5) * 0.012 * (1.0 - o);
	float a = smoothstep(-0.05, 0.015, d + lash);
	vec3 col = mix(vec3(0.07, 0.012, 0.01), vec3(0.0), smoothstep(0.0, 0.18, d));
	COLOR = vec4(col, a * (1.0 - smoothstep(0.92, 1.0, o)));
}
