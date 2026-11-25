shader_type spatial;
// Varnished, hand-carved honey wood with vertical grain (object space). GLES2-safe.
// COLOR.r carries baked cavity occlusion from the sculpt.

uniform vec4 base : hint_color = vec4(0.80, 0.53, 0.22, 1.0);
uniform vec4 dark : hint_color = vec4(0.48, 0.27, 0.09, 1.0);
uniform vec4 light : hint_color = vec4(0.97, 0.74, 0.42, 1.0);
uniform sampler2D noise_tex;
uniform float grain_freq = 230.0;
uniform float radius = 0.33;
uniform bool cylindrical = true;
uniform float cavity = 1.0;
uniform bool lite = false;

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
	float warp = lite ? 0.0 : (nz(p * vec2(0.5, 0.12)) - 0.5) * 0.07;
	float lines = sin((p.x + warp) * grain_freq) * 0.5 + 0.5;
	float broad = nz(vec2(p.x * 2.2, p.y * 0.18));
	float fine = lite ? 0.5 : nz(vec2(p.x * 14.0, p.y * 0.9));
	vec3 col = mix(dark.rgb, base.rgb, smoothstep(0.15, 0.85, broad));
	col = mix(col, light.rgb, smoothstep(0.55, 0.95, broad) * 0.35);
	col = mix(col, dark.rgb * 0.8, pow(1.0 - lines, 10.0) * 0.16);
	col *= 0.95 + 0.08 * fine;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col *= mix(1.0, 0.62, fres);
	float occ = mix(1.0, ao, cavity);
	ALBEDO = col * occ;
	ROUGHNESS = mix(0.6, 0.8, fine) + (1.0 - occ) * 0.2;
	SPECULAR = 0.2;
}
