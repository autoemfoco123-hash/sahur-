shader_type canvas_item;
// rot post-processing.
// fisheye (true equidistant remap) -> camera motion blur (directional + radial)
// -> chromatic fringe -> bloom haze -> liminal grade -> soft vignette -> a little grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 1.0;
uniform float fisheye = 0.85;
uniform vec2 blur_dir = vec2(0.0);
uniform float radial = 0.0;
uniform float blur_amount = 1.0;
uniform float danger = 0.0;
uniform float madness = 0.0;
uniform float pixelate = 0.0;
uniform float flash = 0.0;
uniform float fade = 0.0;
uniform float brightness = 1.0;
uniform vec3 tint = vec3(1.0, 0.98, 0.9);
uniform float pulse = 0.0;
uniform float haze = 0.35;
uniform float grain = 0.01;
uniform float freeze = 0.0;
uniform float nv = 0.0;
uniform float nv_gain = 22.0;

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 fish(vec2 uv, float aspect, float k) {
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float R = length(vec2(aspect, 1.0) * 0.5);
	float r = length(c) / R;
	float a = mix(0.02, 1.22, k);
	float rs = tan(r * a) / tan(a);
	c *= rs / max(r, 1e-4);
	return c / vec2(aspect, 1.0) + 0.5;
}

vec3 sample_ca(vec2 uv, vec2 dir) {
	return vec3(texture(screen_tex, uv + dir).r, texture(screen_tex, uv).g, texture(screen_tex, uv - dir).b);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	float t = TIME;
	float k = intensity;
	vec2 uv = SCREEN_UV;

	// Fisheye: the room bulges toward you.
	float fe = clamp(fisheye * k * 0.92 + danger * 0.05 + madness * 0.08, 0.0, 1.0);
	uv = fish(uv, aspect, fe);
	// Madness wobble
	uv += vec2(sin(uv.y * 16.0 + t * 2.5), cos(uv.x * 12.0 + t * 2.0)) * 0.004 * madness * madness * k;
	// Deep-fry pixelation
	if (pixelate > 0.0) {
		float px = mix(1.0, 7.0, pixelate);
		uv = (floor(uv * res / px) + 0.5) * px / res;
	}

	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 ca = normalize(c + 1e-5) * (0.0006 + r2 * 0.008 + danger * 0.004 + madness * 0.008 + flash * 0.02) * k;

	// Motion blur: directional (camera turn) + radial (moving forward)
	vec3 col = vec3(0.0);
	float bl = blur_amount * k;
	const int N = 12;
	float wsum = 0.0;
	for (int i = 0; i < N; i++) {
		float f = float(i) / float(N - 1) - 0.5;
		float w = 1.0 - abs(f) * 0.8;
		vec2 o = blur_dir * f * bl + c * radial * bl * (f + 0.5) * -0.5;
		col += sample_ca(uv + o, ca) * w;
		wsum += w;
	}
	col /= wsum;
	// Optics are soft, like an old camcorder; the image is never razor sharp.
	col = mix(col, textureLod(screen_tex, uv, 1.2).rgb, 0.14);

	// Bloom haze: everything glows a little too much, like a dream you can't leave.
	vec3 glow = textureLod(screen_tex, uv, 4.0).rgb + textureLod(screen_tex, uv, 6.0).rgb;
	col += max(glow * 0.5 - 0.15, 0.0) * haze * k;

	// Grade: lifted blacks, washed out, fluorescent tint
	col *= brightness;
	col = mix(col, col * 0.92 + 0.035, 0.6 * k * (1.0 - nv));
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, mix(1.0, 0.78, k) + pixelate * 1.6);
	col *= mix(vec3(1.0), tint, k);
	if (pixelate > 0.0) {
		col = floor(col * mix(64.0, 5.0, pixelate)) / mix(64.0, 5.0, pixelate);
		col = mix(col, col * vec3(1.4, 1.1, 0.6), pixelate);
	}

	// hush nv-7: full-colour digital night vision filling the whole view.
	if (nv > 0.001) {
		float avg = dot(textureLod(screen_tex, vec2(0.5), 8.0).rgb, vec3(0.333));
		float gain = clamp(0.2 / max(avg, 0.004), 1.0, nv_gain);
		vec3 amp = col * gain;
		vec3 halo = textureLod(screen_tex, uv, 3.0).rgb * gain;
		amp += max(halo - 0.9, 0.0) * 0.35;
		amp = amp / (1.0 + amp * 0.35) * 1.18;
		float al = dot(amp, vec3(0.299, 0.587, 0.114));
		amp = mix(vec3(al), amp, 0.9) * vec3(0.97, 1.0, 1.03);
		// sensor noise grows with gain
		vec2 px = floor(SCREEN_UV * res);
		float fr = floor(t * 30.0);
		float ns = 0.006 + 0.0007 * gain;
		vec3 cn = vec3(rnd(px + fr * 1.37), rnd(px + fr * 2.71 + 11.0), rnd(px + fr * 3.13 + 37.0)) - 0.5;
		float ln = rnd(px * 0.5 + fr * 7.0) - 0.5;
		amp += (ln + cn * 0.7) * ns;
		amp *= 1.0 + (rnd(px * 0.37) - 0.5) * 0.035;
		amp += step(0.99992, rnd(px + fr)) * 0.7;
		col = mix(col, amp, nv);
	}

	// Soft vignette, tightening with danger
	float vig = 1.0 - smoothstep(0.3 - danger * 0.15, 0.95, length((SCREEN_UV - 0.5) * vec2(aspect * 0.75, 1.0)) * (1.0 + pulse * 0.08));
	col *= mix(1.0, vig, (0.45 + danger * 0.4) * k);
	col = mix(col, col * vec3(1.0, 0.25, 0.2), danger * 0.2 * (1.0 - vig) * k);

	// A little grain
	float g = rnd(SCREEN_UV * res + fract(t * 7.13) * 100.0) - 0.5;
	col += g * (grain + madness * 0.08) * k;

	// Tracking glitch when the brain is rotting
	float band = step(0.996 - madness * 0.04, rnd(vec2(floor(SCREEN_UV.y * 40.0), floor(t * 12.0))));
	col = mix(col, col.gbr * 1.3, band * madness);

	col = mix(col, vec3(0.9, 0.9, 0.88), flash * 0.5);
	col = mix(col, vec3(0.0), fade);
	COLOR = vec4(col, 1.0);
}
