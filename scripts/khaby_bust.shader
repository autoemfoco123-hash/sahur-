shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The mechanism's head, neck and chest: the reference photo projected straight from the front
// (model space), so the face is exactly the one in the photo. Surfaces that turn away from the
// front fade into the bust's own dark colour instead of repeating the face on the back.

uniform sampler2D face_tex : hint_albedo;
uniform float px = 0.0058;          // metres per photo pixel
uniform float table_h = 0.85;       // model y of the photo's y = 350 line
uniform vec3 back_col = vec3(0.16, 0.075, 0.055);

varying vec2 puv;
varying float front;

void vertex() {
	float xp = 318.0 - VERTEX.x / px;
	float yp = 350.0 - (VERTEX.y - table_h) / px;
	puv = vec2((xp - 220.0) / 200.0, yp / 250.0);
	front = -NORMAL.z;
}

void fragment() {
	vec3 c = texture(face_tex, puv).rgb;
	float k = smoothstep(-0.25, 0.25, front);
	ALBEDO = mix(back_col, c, k);
	ROUGHNESS = 0.48;
	SPECULAR = 0.45;
}
