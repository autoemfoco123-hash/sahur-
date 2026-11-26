shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
// Handwriting on a wall, lit exactly like the wall under it (world_lit.shader, wall branch):
// the baked lamps, the bounce, the dark corners, dead lamps and blackouts all reach the ink.
// text_tex: the line, rendered once in white on transparent (alpha is the ink).

uniform sampler2D text_tex;
uniform vec4 ink : hint_color = vec4(0.15, 0.14, 0.11, 0.95);
uniform sampler2D lm_direct;
uniform sampler2D lm_soft;
uniform vec4 lm_rect;                     // origin x, origin z, 1/span, 1/span
uniform float lm_gain = 2.0;
uniform float exposure = 1.0;
uniform vec3 light_tint = vec3(1.0, 0.95, 0.76);
uniform float ambient = 0.05;
uniform float wall_h = 2.75;
uniform vec4 off0;
uniform vec4 off1;
uniform vec4 off2;
uniform vec4 off3;
uniform float blackout = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lamp(vec4 o, vec2 p) {
	vec2 d = p - o.xy;
	float h2 = 7.5625;
	return o.z * pow(h2 / (dot(d, d) + h2), 1.5);
}

void fragment() {
	float a = texture(text_tex, UV).a * ink.a;
	float y = wpos.y;
	vec2 lp = wpos.xz + wnrm.xz * 0.14;
	vec2 luv = (lp - lm_rect.xy) * lm_rect.zw;
	float dir = texture(lm_direct, luv).r * lm_gain;
	vec3 sft = texture(lm_soft, luv).rgb;
	float bounce = sft.r * lm_gain;
	float occ = sft.g;
	float dead = lamp(off0, lp) + lamp(off1, lp) + lamp(off2, lp) + lamp(off3, lp);
	dir = max(0.0, dir - dead * 1.05);
	bounce = max(0.0, bounce - dead * 0.25);
	float t = clamp(dir * 0.85, 0.0, 1.0);
	float sc = smoothstep(-0.3, 2.1, y) * (1.0 - 0.6 * smoothstep(2.3, wall_h, y));
	float prof = mix(0.78 + 0.22 * y / wall_h, 0.22 + 1.3 * sc, t * t);
	float E = dir * prof + bounce * 0.5;
	E *= mix(0.72, 1.0, smoothstep(0.0, 0.3, wall_h - y));
	E *= 1.0 - 0.45 * smoothstep(0.52, 0.85, occ);
	E = (E + ambient) * (1.0 - blackout * 0.94);
	ALBEDO = ink.rgb * E * light_tint * exposure;
	ALPHA = a;
}
