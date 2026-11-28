shader_type spatial;
render_mode unshaded;
// Sector 3.5's hall (level_35.gd): the floor slabs, the walls and the pillars, lit right here
// in the shader instead of by real lights, so it looks the same on every machine and every
// quality (a real light is one more pass over the whole floor, and potato would light a 6 m
// slab only at its corners). The light:
//   the hanging lamps   a ring of lamp_n spots pointing straight down, each with its energy
//                       (they flicker in the last phase)
//   the boss            its red glow, where its head is
//   the anchors         a white pool round each one that is switched on
//   ambient             a little light everywhere
// mode 0: a floor slab (its own uv, from the mesh) · 1: wall / pillar (world triplanar)

uniform int mode = 0;
uniform sampler2D albedo_tex : hint_albedo;
uniform float tex_scale = 6.0;            // metres per texture tile (mode 1)
uniform vec3 tint = vec3(1.0);
uniform vec3 center;
uniform float ring_r = 24.5;
uniform float lamp_y = 20.7;
uniform int lamp_n = 8;
uniform vec4 lamp_e0 = vec4(1.0);         // energies of lamps 0..3
uniform vec4 lamp_e1 = vec4(1.0);         // and 4..7
uniform float lamp_power = 1.0;
uniform float cone_cos = 0.866;           // the lamps' cone (half angle 30 degrees)
uniform vec4 glow = vec4(0.0);            // the boss's red light: xyz, energy
uniform vec4 anc0 = vec4(0.0);            // anchors: xyz, on (0..1)
uniform vec4 anc1 = vec4(0.0);
uniform vec4 anc2 = vec4(0.0);
uniform vec4 anc3 = vec4(0.0);
uniform float ambient = 0.1;
uniform float photo_gain = 1.0;           // the field camera's auto exposure (the shutter frame only)

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	lnrm = NORMAL;
}

float spot(float k, float e) {
	float a = 6.2831853 * (k + 0.5) / float(lamp_n);
	vec3 L = center + vec3(sin(a) * ring_r, lamp_y, cos(a) * ring_r);
	vec3 v = wpos - L;
	float d = length(v);
	vec3 dir = v / d;
	float cone = smoothstep(cone_cos - 0.05, cone_cos + 0.06, -dir.y);
	float facing = max(dot(wnrm, -dir), 0.0);
	return e * cone * facing * (lamp_y * lamp_y) / (d * d);
}

float pool(vec4 a, float r) {
	if (a.w <= 0.0) {
		return 0.0;
	}
	vec3 v = a.xyz - wpos;
	float d = length(v);
	return a.w * max(dot(wnrm, v / max(d, 0.001)), 0.0) * (1.0 - smoothstep(0.0, r, d));
}

void fragment() {
	vec3 alb;
	if (mode == 0) {
		// the slab's own face: top / bottom by x,z, the sides by their other two axes
		vec2 uv;
		if (abs(lnrm.y) > 0.5) {
			uv = lpos.xz / 6.0 + 0.5;
		} else if (abs(lnrm.x) > 0.5) {
			uv = vec2(lpos.z / 6.0 + 0.5, lpos.y / 6.0 + 0.5);
		} else {
			uv = vec2(lpos.x / 6.0 + 0.5, lpos.y / 6.0 + 0.5);
		}
		alb = texture(albedo_tex, uv).rgb;
	} else {
		vec3 an = abs(wnrm);
		vec2 uv = an.y > 0.5 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
		alb = texture(albedo_tex, uv / tex_scale).rgb;
	}
	alb *= tint;
	float E = 0.0;
	if (lamp_n > 0) E += spot(0.0, lamp_e0.x);
	if (lamp_n > 1) E += spot(1.0, lamp_e0.y);
	if (lamp_n > 2) E += spot(2.0, lamp_e0.z);
	if (lamp_n > 3) E += spot(3.0, lamp_e0.w);
	if (lamp_n > 4) E += spot(4.0, lamp_e1.x);
	if (lamp_n > 5) E += spot(5.0, lamp_e1.y);
	if (lamp_n > 6) E += spot(6.0, lamp_e1.z);
	if (lamp_n > 7) E += spot(7.0, lamp_e1.w);
	E *= lamp_power;
	float A = pool(anc0, 10.0) + pool(anc1, 10.0) + pool(anc2, 10.0) + pool(anc3, 10.0);
	float G = 0.0;
	if (glow.w > 0.0) {
		vec3 v = glow.xyz - wpos;
		float d = length(v);
		G = glow.w * max(dot(wnrm, v / max(d, 0.001)), 0.0) * (1.0 - smoothstep(0.0, 16.0, d));
	}
	vec3 light = vec3(E + ambient) + vec3(0.9, 0.95, 1.0) * A * 0.8 + vec3(1.0, 0.12, 0.06) * G;
	ALBEDO = alb * light * photo_gain;
}
