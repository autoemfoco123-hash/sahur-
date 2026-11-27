shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
// The field's ground (sector 2): the grass texture at two scales so it never shows a tile,
// big soft patches (greener, darker, sun-bleached), and far away a single even green that the
// haze takes over. Mapped in the mesh's own space, so it stays on its half when the field tears.

uniform sampler2D grass_tex : hint_albedo;
uniform sampler2D noise_tex;
uniform vec4 far_col : hint_color = vec4(0.2, 0.37, 0.1, 1.0);

void fragment() {
	vec2 p = UV / 0.22;                                // metres
	vec3 a = texture(grass_tex, p * 0.31).rgb;
	vec3 b = texture(grass_tex, p * 0.077 + vec2(0.37, 0.11)).rgb;
	float m = texture(noise_tex, p * 0.011).r;
	float m2 = texture(noise_tex, p * 0.047 + vec2(0.3, 0.7)).r;
	vec3 c = mix(a, b, 0.42);
	c *= 0.8 + 0.38 * m;
	c = mix(c, c * vec3(1.12, 1.06, 0.72), smoothstep(0.58, 0.82, m2) * 0.55);
	c = mix(c, c * vec3(0.78, 0.92, 0.8), smoothstep(0.62, 0.85, 1.0 - m2) * 0.4);
	float d = length(VERTEX);
	vec3 far = far_col.rgb * (0.78 + 0.4 * m) * mix(vec3(1.0), vec3(1.1, 1.04, 0.8), smoothstep(0.55, 0.8, m2) * 0.5);
	c = mix(c * 0.88, far, smoothstep(25.0, 150.0, d));
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 0.95;
}
