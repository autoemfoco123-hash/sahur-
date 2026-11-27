shader_type spatial;
render_mode unshaded;
// Static office surfaces lit from the baked light maps (light_bake.gd). No runtime lights:
// one pass per chunk, three texture reads on potato.
// kind: 0 carpet floor · 1 wallpaper wall · 2 drop ceiling · 3 light panel (uses mesh UV)

uniform int kind = 1;
uniform sampler2D albedo_tex : hint_albedo;
uniform float tex_scale = 1.0;            // metres per texture tile
uniform sampler2D noise_tex;
uniform sampler2D lm_direct;
uniform sampler2D lm_soft;
uniform vec4 lm_rect;                     // origin x, origin z, 1/span, 1/span
uniform float lm_gain = 2.0;
uniform float exposure = 1.0;
uniform vec3 light_tint = vec3(1.0, 0.95, 0.76);
uniform float ambient = 0.05;
uniform float wall_h = 2.75;
uniform float base_h = 0.09;
uniform vec4 off0;                        // dead / flickering lamps: x, z, amount
uniform vec4 off1;
uniform vec4 off2;
uniform vec4 off3;
uniform float blackout = 0.0;
uniform vec4 actor;                       // a brainrot's own top light: x, z, intensity, radius
uniform vec3 fog_color = vec3(0.62, 0.6, 0.42);
uniform vec4 fog = vec4(8.0, 60.0, 1.7, 1.0); // begin, end, curve, amount
uniform bool lite = false;
uniform bool mono = false;                // monochrome sectors: no colour on the walls at all
uniform float photo_gain = 1.0;           // the field camera's auto exposure (the shutter frame only)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float nz(vec2 p) { return texture(noise_tex, p).r; }

float lamp(vec4 o, vec2 p) {
	vec2 d = p - o.xy;
	float h2 = 7.5625;
	return o.z * pow(h2 / (dot(d, d) + h2), 1.5);
}

void fragment() {
	// ---- surface
	vec2 p;
	float y = wpos.y;
	if (kind == 0 || kind == 2) {
		p = wpos.xz;
	} else if (abs(wnrm.x) > abs(wnrm.z)) {
		p = vec2(wpos.z, -y);
	} else {
		p = vec2(wpos.x, -y);
	}
	vec3 alb;
	if (kind == 3) {
		alb = texture(albedo_tex, UV).rgb;
	} else {
		alb = texture(albedo_tex, p / tex_scale).rgb;
	}
	if (!lite && kind != 3) {
		float n1 = nz(p * 0.045);
		if (kind == 0) {
			// damp patches: darker, a touch more saturated
			float wet = smoothstep(0.52, 0.74, n1);
			alb *= mix(vec3(1.0), vec3(0.62, 0.6, 0.55), wet);
			alb *= 0.9 + 0.2 * nz(p * 0.21);
		} else if (kind == 1) {
			// rising damp along the bottom, faint drips from the ceiling
			float damp = smoothstep(0.45, 0.75, n1) * (1.0 - smoothstep(0.05, 0.7 + n1 * 0.5, y));
			alb *= mix(vec3(1.0), vec3(0.78, 0.7, 0.52), damp);
			float drip = smoothstep(0.62, 0.8, nz(vec2(p.x * 0.35, y * 0.018) + 3.0)) * smoothstep(0.8, 2.7, y);
			alb *= 1.0 - drip * 0.12;
		} else {
			// water-stained tiles: brown rings
			float s = nz(p * 0.06 + 11.0);
			float ring = smoothstep(0.66, 0.675, s) - smoothstep(0.69, 0.72, s);
			float inside = smoothstep(0.68, 0.7, s);
			alb = mix(alb, alb * vec3(0.93, 0.86, 0.7), inside * 0.6);
			alb = mix(alb, vec3(0.55, 0.44, 0.27), ring * 0.55);
		}
	}
	// ---- baked light
	vec2 lp = wpos.xz + wnrm.xz * 0.14;
	vec2 luv = (lp - lm_rect.xy) * lm_rect.zw;
	float dir = texture(lm_direct, luv).r * lm_gain;
	vec3 sft = texture(lm_soft, luv).rgb;
	float bounce = sft.r * lm_gain;
	float occ = sft.g;
	float dead = lamp(off0, lp) + lamp(off1, lp) + lamp(off2, lp) + lamp(off3, lp);
	dir = max(0.0, dir - dead * 1.05);
	bounce = max(0.0, bounce - dead * 0.25);
	float E;
	if (kind == 0) {
		E = dir + bounce * 0.5;
		E *= 1.0 - 0.55 * smoothstep(0.06, 0.5, occ);
	} else if (kind == 2) {
		E = dir * 0.16 + bounce * 0.75;
		E *= 1.0 - 0.5 * smoothstep(0.06, 0.5, occ);
	} else if (kind == 1) {
		// close to a lamp the wall gets a bright scallop high up and falls off below;
		// far from lamps it is evenly lit.
		float t = clamp(dir * 0.85, 0.0, 1.0);
		float sc = smoothstep(-0.3, 2.1, y) * (1.0 - 0.6 * smoothstep(2.3, wall_h, y));
		float prof = mix(0.78 + 0.22 * y / wall_h, 0.22 + 1.3 * sc, t * t);
		E = dir * prof + bounce * 0.5;
		E *= mix(0.5, 1.0, smoothstep(0.0, 0.5, y));                 // floor contact
		E *= mix(0.72, 1.0, smoothstep(0.0, 0.3, wall_h - y));        // ceiling corner
		E *= 1.0 - 0.45 * smoothstep(0.52, 0.85, occ);                // inside corners
		if (y < base_h) {
			alb = vec3(0.11, 0.085, 0.06) * (0.85 + 0.3 * smoothstep(base_h - 0.012, base_h, y));
		}
	} else {
		E = 2.15;
	}
	// a brainrot's personal light: a pool on the floor, a dark contact shadow at its feet
	if (actor.z > 0.0 && kind != 3) {
		float d = distance(wpos.xz, actor.xy);
		float pool = actor.z * (1.0 - smoothstep(0.0, actor.w, d));
		E += pool * (kind == 2 ? 0.25 : (kind == 1 ? 0.6 * (1.0 - smoothstep(0.4, 2.6, y)) : 1.0));
		if (kind == 0) {
			E *= 1.0 - 0.55 * (1.0 - smoothstep(0.12, 0.6, d));
		}
	}
	if (kind == 3) {
		float k = 1.0;
		vec2 c = wpos.xz;
		k -= off0.z * (1.0 - step(0.45, distance(c, off0.xy)));
		k -= off1.z * (1.0 - step(0.45, distance(c, off1.xy)));
		k -= off2.z * (1.0 - step(0.45, distance(c, off2.xy)));
		k -= off3.z * (1.0 - step(0.45, distance(c, off3.xy)));
		k = max(k, 0.0) * (1.0 - blackout * 0.97);
		E = mix(0.32, 2.15, k);
	} else {
		E = (E + ambient) * (1.0 - blackout * 0.94);
	}
	vec3 col = alb * E * light_tint * exposure * photo_gain;
	if (mono) {
		col = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
	}
	// distance haze
	float fd = length(VERTEX);
	float f = pow(clamp((fd - fog.x) / (fog.y - fog.x), 0.0, 1.0), fog.z) * fog.w;
	col = mix(col, fog_color * (1.0 - blackout * 0.9), f);
	ALBEDO = col;
}
