shader_type spatial;
// ROT world surfaces. Box-mapped in world space like an old Source map.
// pattern: 0 planks, 1 tiles, 2 concrete, 3 wallpaper, 4 devgrid, 5 missing, 6 carpet, 7 metal

uniform int pattern = 0;
uniform vec3 color_a : source_color = vec3(0.5, 0.35, 0.2);
uniform vec3 color_b : source_color = vec3(0.3, 0.2, 0.1);
uniform float scale = 1.0;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform float grime = 0.6;
uniform float stains = 0.5;
uniform float bump = 1.0;
uniform float emission = 0.0;
uniform float floor_y = 0.0;
uniform float wainscot = 0.0;
uniform vec3 wood_a : source_color = vec3(0.32, 0.2, 0.11);
uniform vec3 wood_b : source_color = vec3(0.2, 0.12, 0.06);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) { return texture(noise_tex, p).r; }
float fbm(vec2 p) { return nz(p) * 0.55 + nz(p * 2.13 + 0.31) * 0.3 + nz(p * 4.7 + 0.77) * 0.15; }

// Returns albedo in rgb, height in a.
vec4 surface(vec2 p, vec3 n, float wall) {
	vec3 col = color_a;
	float h = 1.0;
	if (pattern == 0) {
		// Planks: across = p.x, along = p.y
		float w = 0.22;
		float idx = floor(p.x / w);
		float f = fract(p.x / w);
		float along = p.y + hash(vec2(idx, 3.0)) * 7.0;
		float bidx = floor(along / 2.4);
		float bf = fract(along / 2.4);
		float r = hash(vec2(idx, bidx));
		float g = nz(vec2(f * 0.08 + r, along * 0.018));
		float rings = sin((g * 40.0 + f * 3.0)) * 0.5 + 0.5;
		col = mix(color_b, color_a, r * 0.6 + 0.2) * (0.72 + 0.45 * g) * (0.9 + 0.1 * rings);
		float seam = smoothstep(0.0, 0.04, f) * smoothstep(0.0, 0.04, 1.0 - f) * smoothstep(0.0, 0.006, bf) * smoothstep(0.0, 0.006, 1.0 - bf);
		col *= mix(0.12, 1.0, seam);
		h = seam * (0.8 + 0.2 * g);
	} else if (pattern == 1) {
		vec2 q = p / (0.3 * scale);
		vec2 id = floor(q);
		vec2 f = fract(q);
		float checker = mod(id.x + id.y, 2.0);
		float r = hash(id);
		col = mix(color_a, color_b, checker) * (0.9 + 0.15 * r);
		float grout = smoothstep(0.0, 0.035, f.x) * smoothstep(0.0, 0.035, 1.0 - f.x) * smoothstep(0.0, 0.035, f.y) * smoothstep(0.0, 0.035, 1.0 - f.y);
		col = mix(color_b * 0.35 + vec3(0.04), col, grout);
		h = grout;
	} else if (pattern == 2) {
		float b = fbm(p * 0.05);
		float pores = step(0.82, nz(p * 1.7));
		col = mix(color_b, color_a, b) * (1.0 - pores * 0.25);
		// formwork panel lines
		vec2 f = fract(p / vec2(2.4, 1.2));
		float line = smoothstep(0.0, 0.004, f.x) * smoothstep(0.0, 0.008, f.y);
		col *= mix(0.6, 1.0, line);
		h = 0.6 + 0.4 * b - pores * 0.2;
	} else if (pattern == 3) {
		// Old wallpaper: stripes + diamond motif, yellowed, peeling
		float s = sin(p.x * 3.14159 / 0.12) * 0.5 + 0.5;
		vec2 m = fract(p / vec2(0.36, 0.5)) - 0.5;
		float diamond = smoothstep(0.22, 0.18, abs(m.x) + abs(m.y) * 0.7);
		col = mix(color_a, color_b, 0.25 * s + 0.35 * diamond);
		float peel = smoothstep(0.72, 0.75, fbm(p * 0.08 + 3.1));
		col = mix(col, vec3(0.35, 0.32, 0.26), peel);
		h = 1.0 - peel * 0.6;
	} else if (pattern == 4) {
		// Dev measure texture
		vec2 q = p * scale;
		vec2 f1 = abs(fract(q) - 0.5);
		vec2 f4 = abs(fract(q * 4.0) - 0.5);
		float major = 1.0 - smoothstep(0.47, 0.49, max(f1.x, f1.y));
		float minor = 1.0 - smoothstep(0.44, 0.48, max(f4.x, f4.y));
		float cell = mod(floor(q.x) + floor(q.y), 2.0);
		col = color_a * (0.92 + 0.08 * cell);
		col = mix(col, color_b, minor * 0.35);
		col = mix(col, vec3(0.95), major * 0.85);
		h = 1.0;
	} else if (pattern == 5) {
		vec2 id = floor(p * 2.0);
		float c = mod(id.x + id.y, 2.0);
		col = mix(vec3(0.0), vec3(1.0, 0.0, 1.0), c);
		h = 1.0;
	} else if (pattern == 6) {
		// Damp office carpet: fine pile + soggy darker patches
		float pile = nz(p * 9.0) * 0.5 + nz(p * 23.0) * 0.5;
		float g = nz(p * 0.35) * 0.6 + nz(p * 1.3) * 0.4;
		col = mix(color_b, color_a, smoothstep(0.25, 0.8, g)) * (0.88 + 0.22 * pile);
		h = pile;
	} else if (pattern == 8) {
		// Plain painted / mono-yellow wallpaper: barely-there vertical stripes
		float st = sin(p.x * 3.14159 / 0.05) * 0.5 + 0.5;
		float g = nz(p * vec2(0.6, 0.15)) * 0.7 + nz(p * 4.0) * 0.3;
		col = mix(color_b, color_a, 0.55 + 0.35 * g) * (0.985 + 0.03 * st);
		h = 0.95 + st * 0.05;
	} else if (pattern == 9) {
		// Drop ceiling: 60 cm tiles on a light T-bar grid, perforated mineral fibre
		vec2 q = p / 0.6;
		vec2 f = fract(q);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float bar = 1.0 - smoothstep(0.012, 0.022, edge);
		float bevel = smoothstep(0.022, 0.05, edge);
		float fib = nz(p * 7.0) * 0.6 + nz(p * 19.0) * 0.4;
		float holes = step(0.86, nz(p * 31.0));
		col = color_a * (0.93 + 0.1 * fib) * (1.0 - holes * 0.12);
		col *= mix(0.86, 1.0, bevel);
		col = mix(col, color_b, bar);
		h = bevel * (0.9 + fib * 0.1) - holes * 0.05 + bar * 0.3;
	} else {
		vec2 f = fract(p / 1.2);
		float panel = smoothstep(0.0, 0.01, f.x) * smoothstep(0.0, 0.01, f.y);
		vec2 rv = fract(p / 0.15) - 0.5;
		float rivet = smoothstep(0.08, 0.05, length(rv)) * (1.0 - smoothstep(0.03, 0.06, min(f.x, f.y) * 1.2 - 0.0));
		float brushed = nz(vec2(p.x * 0.02, p.y * 3.0));
		col = mix(color_b, color_a, brushed) * mix(0.5, 1.0, panel);
		h = panel * 0.8 + rivet * 0.2 + brushed * 0.1;
	}
	return vec4(col, h);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 p;
	float wall = 0.0;
	if (an.y >= an.x && an.y >= an.z) {
		p = vec2(wpos.z, wpos.x);
	} else if (an.x >= an.z) {
		p = vec2(wpos.z, wpos.y);
		wall = 1.0;
	} else {
		p = vec2(wpos.x, wpos.y);
		wall = 1.0;
	}
	vec4 s = surface(p, wnrm, wall);
	if (wall > 0.5 && wainscot > 0.0 && wpos.y - floor_y < wainscot + 0.06) {
		float hy = wpos.y - floor_y;
		// Dark wooden wainscot with a chair rail
		float w = 0.18;
		float f = fract(p.x / w);
		float g = nz(vec2(f * 0.08 + floor(p.x / w) * 0.37, p.y * 0.02));
		vec3 wc = mix(wood_b, wood_a, g) * (0.75 + 0.4 * g);
		float seam = smoothstep(0.0, 0.05, f) * smoothstep(0.0, 0.05, 1.0 - f);
		wc *= mix(0.25, 1.0, seam);
		float rail = smoothstep(wainscot - 0.02, wainscot, hy);
		wc = mix(wc, wood_b * 0.5, rail);
		s = vec4(wc, seam * (1.0 - rail * 0.5) + rail);
	}
	vec3 col = s.rgb;
	// Water stains + grime that gather near the floor and drip from the ceiling
	float st = fbm(vec2(p.x * 0.03, p.y * (wall > 0.5 ? 0.008 : 0.03)) + 7.0);
	col *= mix(1.0, smoothstep(0.35, 0.75, st) * 0.45 + 0.55, stains);
	if (wall > 0.5) {
		col *= mix(1.0, 0.45 + 0.55 * smoothstep(0.0, 0.7, wpos.y - floor_y), grime * 0.6);
	} else {
		col *= mix(1.0, 0.7 + 0.3 * fbm(p * 0.2), grime * 0.5);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(roughness + (0.5 - fbm(p * 0.4)) * 0.25, 0.03, 1.0);
	METALLIC = metallic;
	if (pattern == 5) {
		EMISSION = col * 0.6;
	}
	EMISSION += col * emission;
	// Bump from height (screen-space derivatives)
	float h = s.a * bump;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.02);
}
