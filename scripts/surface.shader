shader_type spatial;
// Office surfaces, box-mapped in world space like an old Source map. GLES2-safe.
// pattern: 5 missing · 6 carpet · 8 plain wall · 9 drop ceiling

uniform int pattern = 8;
uniform vec4 color_a : hint_color = vec4(0.83, 0.79, 0.5, 1.0);
uniform vec4 color_b : hint_color = vec4(0.74, 0.7, 0.43, 1.0);
uniform float roughness = 0.9;
uniform float grime = 0.35;
uniform float stains = 0.35;
uniform float floor_y = 0.0;
uniform float wainscot = 0.0;
uniform vec4 wood_a : hint_color = vec4(0.26, 0.2, 0.12, 1.0);
uniform vec4 wood_b : hint_color = vec4(0.16, 0.12, 0.07, 1.0);
uniform sampler2D noise_tex;
uniform bool lite = false;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float nz(vec2 p) { return texture(noise_tex, p).r; }
float fbm(vec2 p) { return nz(p) * 0.6 + nz(p * 2.13 + 0.31) * 0.4; }

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
	vec3 col = color_a.rgb;
	if (lite) {
		// Potato: one noise read, no stains/grime layers.
		float g = nz(p * (pattern == 6 ? 1.3 : 0.6));
		col = mix(color_b.rgb, color_a.rgb, g);
		if (pattern == 9) {
			vec2 f = fract(p / 0.6);
			float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
			col = mix(col, color_b.rgb, 1.0 - step(0.02, edge));
		}
		if (wall > 0.5 && wainscot > 0.0 && wpos.y - floor_y < wainscot) {
			col = wood_b.rgb;
		}
		ALBEDO = col;
		ROUGHNESS = roughness;
		METALLIC = 0.0;
	} else if (pattern == 6) {
		float pile = nz(p * 9.0) * 0.5 + nz(p * 23.0) * 0.5;
		float g = nz(p * 0.35) * 0.6 + nz(p * 1.3) * 0.4;
		col = mix(color_b.rgb, color_a.rgb, smoothstep(0.25, 0.8, g)) * (0.88 + 0.22 * pile);
	} else if (pattern == 8) {
		float st = sin(p.x * 3.14159 / 0.05) * 0.5 + 0.5;
		float g = nz(p * vec2(0.6, 0.15)) * 0.7 + nz(p * 4.0) * 0.3;
		col = mix(color_b.rgb, color_a.rgb, 0.55 + 0.35 * g) * (0.985 + 0.03 * st);
	} else if (pattern == 9) {
		vec2 f = fract(p / 0.6);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float bar = 1.0 - smoothstep(0.012, 0.022, edge);
		float bevel = smoothstep(0.022, 0.05, edge);
		float fib = nz(p * 7.0) * 0.6 + nz(p * 19.0) * 0.4;
		float holes = step(0.86, nz(p * 31.0));
		col = color_a.rgb * (0.93 + 0.1 * fib) * (1.0 - holes * 0.12);
		col *= mix(0.86, 1.0, bevel);
		col = mix(col, color_b.rgb, bar);
	} else if (pattern == 5) {
		vec2 id = floor(p * 2.0);
		col = mix(vec3(0.0), vec3(1.0, 0.0, 1.0), mod(id.x + id.y, 2.0));
	}
	// Dark baseboard
	if (!lite && wall > 0.5 && wainscot > 0.0 && wpos.y - floor_y < wainscot + 0.01) {
		float rail = smoothstep(wainscot - 0.015, wainscot, wpos.y - floor_y);
		col = mix(mix(wood_b.rgb, wood_a.rgb, nz(p * vec2(0.1, 2.0))), wood_b.rgb * 0.5, rail);
	}
	if (!lite) {
		// Water stains and grime
		float st2 = fbm(vec2(p.x * 0.03, p.y * (wall > 0.5 ? 0.008 : 0.03)) + 7.0);
		col *= mix(1.0, smoothstep(0.35, 0.75, st2) * 0.45 + 0.55, stains);
		if (wall > 0.5) {
			col *= mix(1.0, 0.45 + 0.55 * smoothstep(0.0, 0.7, wpos.y - floor_y), grime * 0.6);
		} else {
			col *= mix(1.0, 0.7 + 0.3 * fbm(p * 0.2), grime * 0.5);
		}
		ALBEDO = col;
		ROUGHNESS = roughness;
		METALLIC = 0.0;
		if (pattern == 5) {
			EMISSION = col * 0.4;
		}
	}
}
