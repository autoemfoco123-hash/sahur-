shader_type canvas_item;
// Light-bake second pass: r = bounce light (wide blur of direct), g = wall occlusion (narrow blur).
uniform sampler2D direct;
uniform sampler2D walls;
uniform float wide = 0.05;
uniform float narrow = 0.012;

void fragment() {
	vec2 uv = UV;
	float b = 0.0;
	float ws = 0.0;
	for (int i = 0; i < 28; i++) {
		float fi = float(i);
		float a = fi * 2.39996;
		float r = sqrt((fi + 0.5) / 28.0);
		float w = 1.0 - r * 0.7;
		b += texture(direct, uv + vec2(cos(a), sin(a)) * r * wide).r * w;
		ws += w;
	}
	b /= ws;
	float occ = 0.0;
	for (int i = 0; i < 16; i++) {
		float fi = float(i);
		float a = fi * 2.39996;
		float r = sqrt((fi + 0.5) / 16.0);
		occ += texture(walls, uv + vec2(cos(a), sin(a)) * r * narrow).r;
	}
	occ /= 16.0;
	COLOR = vec4(b, occ, 0.0, 1.0);
}
