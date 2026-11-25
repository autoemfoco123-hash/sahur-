shader_type spatial;
// Varnished, hand-carved honey wood with vertical grain (object space).
// COLOR.r carries baked cavity occlusion from the sculpt.

uniform vec3 base : source_color = vec3(0.80, 0.53, 0.22);
uniform vec3 dark : source_color = vec3(0.48, 0.27, 0.09);
uniform vec3 light : source_color = vec3(0.97, 0.74, 0.42);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float grain_freq = 230.0;
uniform float radius = 0.33;
uniform bool cylindrical = true;
uniform float cavity = 1.0;

varying vec3 lp;
varying float ao;

void vertex() {
	lp = VERTEX;
	ao = COLOR.r;
}

float nz(vec2 p) { return texture(noise_tex, p).r; }

void fragment() {
	vec2 p;
	if (cylindrical) {
		p = vec2(atan(lp.x, -lp.z) * radius, lp.y);
	} else {
		p = vec2(lp.x + lp.z * 0.7, lp.y);
	}
	float warp = (nz(p * vec2(0.5, 0.12)) - 0.5) * 0.07 + (nz(p * vec2(2.0, 0.5)) - 0.5) * 0.015;
	float lines = sin((p.x + warp) * grain_freq) * 0.5 + 0.5;
	float lines2 = sin((p.x + warp * 1.7) * grain_freq * 2.3 + 1.3) * 0.5 + 0.5;
	float broad = nz(vec2(p.x * 2.2, p.y * 0.18));
	float fine = nz(vec2(p.x * 14.0, p.y * 0.9));
	vec3 col = mix(dark, base, smoothstep(0.15, 0.85, broad));
	col = mix(col, light, smoothstep(0.55, 0.95, broad) * 0.35);
	col *= 0.95 + 0.06 * lines2;
	col = mix(col, dark * 0.8, pow(1.0 - lines, 10.0) * 0.16);
	col *= 0.95 + 0.08 * fine;
	// rounded log: darker toward the silhouette
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col *= mix(1.0, 0.62, fres);
	float occ = mix(1.0, ao, cavity);
	ALBEDO = col * occ;
	ROUGHNESS = mix(0.42, 0.62, fine) + (1.0 - occ) * 0.3;
	SPECULAR = 0.45;
	CLEARCOAT = 0.35;
	CLEARCOAT_ROUGHNESS = 0.3;
	BACKLIGHT = col * 0.05;
	// grain relief
	float h = pow(1.0 - lines, 8.0) * -0.6 + fine * 0.4;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.0015);
}
