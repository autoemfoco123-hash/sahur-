shader_type spatial;
// 6-7 Ultra's hide (ultra_model.gd): near-black wet skin over a network of swollen veins that
// glow red from inside, pulsing with its heartbeat; a cold rim where the light grazes it.
// hurt: a photo got through (the veins flare white-hot). Godot 3 / GLES2.

uniform sampler2D albedo_tex : hint_albedo;
uniform sampler2D normal_tex : hint_normal;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float vein_glow = 1.0;       // how hot the veins burn (rises with the phases)
uniform float pulse_rate = 1.1;      // heartbeats per second
uniform float hurt = 0.0;            // 0..1, a flinch
uniform float wet = 0.6;
uniform vec4 rim_color : hint_color = vec4(0.55, 0.6, 0.65, 1.0);
uniform float dying = 0.0;           // 0..1: the glow going out
uniform bool bone = false;           // ribs, spines, teeth, claws: no veins, drier

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = texture(albedo_tex, uv).rgb;
	ALBEDO = bone ? c : c * vec3(0.75, 0.62, 0.62);
	NORMALMAP = texture(normal_tex, uv).rgb;
	NORMALMAP_DEPTH = bone ? 0.4 : 1.4;
	ROUGHNESS = bone ? 0.62 : mix(0.55, 0.2, wet);
	SPECULAR = bone ? 0.35 : 0.6;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = rim * rim * rim;
	vec3 em = rim_color.rgb * rim * (bone ? 0.15 : 0.35);
	if (!bone) {
		// the veins are the reddest parts of the hide
		float vein = smoothstep(0.09, 0.17, c.r - max(c.g, c.b));
		float beat = pow(0.5 + 0.5 * sin(TIME * pulse_rate * 6.2831), 6.0);
		float g = vein * vein_glow * (0.18 + 0.5 * beat) * (1.0 - dying);
		em += vec3(0.9, 0.05, 0.02) * g * 0.55;
		em += vec3(1.0, 0.7, 0.55) * vein * hurt * 1.6;
	}
	em += vec3(1.0, 0.2, 0.15) * hurt * 0.25 * rim;
	EMISSION = em;
}
