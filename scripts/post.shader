shader_type canvas_item;
// sahur post-processing (GLES2-safe: only plain texture reads).
// fisheye (true equidistant remap) -> motion blur (1/5/12 samples) -> grade -> goggles -> vignette -> grain.

uniform float intensity = 1.0;
uniform float fisheye = 1.0;
uniform vec2 blur_dir = vec2(0.0);
uniform float radial = 0.0;
uniform float blur_amount = 1.0;
uniform float samples = 5.0;
uniform float danger = 0.0;
uniform float madness = 0.0;
uniform float flash = 0.0;
uniform float fade = 0.0;
uniform float brightness = 1.0;
uniform vec3 tint = vec3(1.02, 1.0, 0.88);
uniform float pulse = 0.0;
uniform float grain = 0.01;
uniform float nv = 0.0;
uniform float nv_gain = 22.0;
uniform bool cheap = false;
uniform float ca_amount = 1.0;      // chromatic aberration (0 = none)

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 fish(vec2 uv, float aspect, float k) {
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float R = length(vec2(aspect, 1.0) * 0.5);
	float r = length(c) / R;
	float a = mix(0.02, 1.22, k);
	float rs = tan(r * a) / tan(a);
	c *= rs / max(r, 0.0001);
	return c / vec2(aspect, 1.0) + 0.5;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	float t = TIME;
	float k = intensity;
	vec2 uv = SCREEN_UV;
	float fe = clamp(fisheye * k * 0.92 + danger * 0.05 + madness * 0.08, 0.0, 1.0);
	uv = fish(uv, aspect, fe);
	uv += vec2(sin(uv.y * 16.0 + t * 2.5), cos(uv.x * 12.0 + t * 2.0)) * 0.004 * madness * madness * k;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 ca = normalize(c + 0.00001) * (0.0006 + r2 * 0.008 + danger * 0.004 + madness * 0.008 + flash * 0.02) * k * ca_amount;

	vec3 col = vec3(0.0);
	float wsum = 0.0;
	float bl = blur_amount * k;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		if (fi >= samples) {
			break;
		}
		float f = samples > 1.0 ? fi / (samples - 1.0) - 0.5 : 0.0;
		float w = 1.0 - abs(f) * 0.8;
		vec2 o = blur_dir * f * bl + c * radial * bl * (f + 0.5) * -0.5;
		vec2 su = uv + o;
		vec3 s;
		if (samples > 4.0) {
			s = vec3(texture(SCREEN_TEXTURE, su + ca).r, texture(SCREEN_TEXTURE, su).g, texture(SCREEN_TEXTURE, su - ca).b);
		} else {
			s = texture(SCREEN_TEXTURE, su).rgb;
		}
		col += s * w;
		wsum += w;
	}
	col /= max(wsum, 0.0001);

	col *= brightness;
	col = mix(col, col * 0.92 + 0.035, 0.6 * k * (1.0 - nv));
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, mix(1.0, 0.82, k));
	col *= mix(vec3(1.0), tint, k);

	// hush nv-7 goggles: auto gain from five probes, sensor noise.
	if (nv > 0.001) {
		float avg = 0.25;
		if (!cheap) {
			vec3 pr = texture(SCREEN_TEXTURE, vec2(0.5)).rgb + texture(SCREEN_TEXTURE, vec2(0.25, 0.3)).rgb
				+ texture(SCREEN_TEXTURE, vec2(0.75, 0.3)).rgb + texture(SCREEN_TEXTURE, vec2(0.25, 0.7)).rgb
				+ texture(SCREEN_TEXTURE, vec2(0.75, 0.7)).rgb;
			avg = dot(pr / 5.0, vec3(0.333));
		}
		float gain = clamp(0.2 / max(avg, 0.004), 1.0, nv_gain);
		vec3 amp = col * gain;
		amp = amp / (1.0 + amp * 0.35) * 1.18;
		float al = dot(amp, vec3(0.299, 0.587, 0.114));
		amp = mix(vec3(al), amp, 0.9) * vec3(0.97, 1.0, 1.03);
		vec2 px = floor(SCREEN_UV * res);
		float fr = floor(t * 30.0);
		float ns = 0.006 + 0.0007 * gain;
		amp += (rnd(px * 0.5 + fr * 7.0) - 0.5 + (rnd(px + fr * 1.37) - 0.5) * 0.7) * ns;
		col = mix(col, amp, nv);
	}

	float vig = 1.0 - smoothstep(0.3 - danger * 0.15, 0.95, length((SCREEN_UV - 0.5) * vec2(aspect * 0.75, 1.0)) * (1.0 + pulse * 0.08));
	col *= mix(1.0, vig, (0.45 + danger * 0.4) * k);
	col = mix(col, col * vec3(1.0, 0.25, 0.2), danger * 0.2 * (1.0 - vig) * k);
	col += (rnd(SCREEN_UV * res + fract(t * 7.13) * 100.0) - 0.5) * (grain + madness * 0.08) * k;
	col = mix(col, vec3(0.9, 0.9, 0.88), flash * 0.5);
	col = mix(col, vec3(0.0), fade);
	COLOR = vec4(col, 1.0);
}
