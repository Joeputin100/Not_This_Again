shader_type sky;

// Procedural 2D cloud sky. Ported from drift's Shadertoy "2D Clouds"
// (https://www.shadertoy.com/view/4tdSWr). LICENSE: the author granted
// blanket permission in the shader comments ("use it in any way you
// choose") — CLEARED for commercial use (credit: drift), unlike the candy
// prototypes. Implemented as a real sky shader so it sits behind ALL
// geometry: the terrain/horizon and the sun/moon render over it with no
// depth fighting. Mapped onto the view direction (EYEDIR).

uniform vec3 sky_color_top : source_color = vec3(0.2, 0.4, 0.6);
uniform vec3 sky_color_bot : source_color = vec3(0.4, 0.7, 1.0);
uniform vec3 cloud_color : source_color = vec3(1.1, 1.1, 0.9);
uniform float cloudcover : hint_range(0.0, 1.0) = 0.2;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.006;

const float cloudscale = 1.1;
const float clouddark = 0.5;
const float cloudlight = 0.3;
const float cloudalpha = 8.0;
const float skytint = 0.5;
const mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

vec2 hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	const float K1 = 0.366025404;
	const float K2 = 0.211324865;
	vec2 i = floor(p + (p.x + p.y) * K1);
	vec2 a = p - i + (i.x + i.y) * K2;
	vec2 o = (a.x > a.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 b = a - o + K2;
	vec2 c = a - 1.0 + 2.0 * K2;
	vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	vec3 n = h * h * h * h * vec3(dot(a, hash(i + 0.0)), dot(b, hash(i + o)), dot(c, hash(i + 1.0)));
	return dot(n, vec3(70.0));
}

float fbm(vec2 n) {
	float total = 0.0;
	float amplitude = 0.1;
	// 4 octaves (was 7): a drifting cloud background hides the missing
	// high-frequency detail, and the per-pixel noise() cost dominates the
	// mobile frame budget (iter 330 perf fix).
	for (int i = 0; i < 4; i++) {
		total += noise(n) * amplitude;
		n = m * n;
		amplitude *= 0.4;
	}
	return total;
}

void sky() {
	// Height factor: 0 at the horizon, 1 straight up.
	float hy = clamp(EYEDIR.y, 0.0, 1.0);
	// Cloud-plane UV: project the view direction onto a plane overhead so
	// clouds recede toward the horizon. Bias y so the horizon band isn't
	// singular.
	vec2 uv = EYEDIR.xz / max(EYEDIR.y * 0.8 + 0.25, 0.18);
	uv *= 0.35;
	vec2 p = uv;
	float time = TIME * cloud_speed;
	float q = fbm(uv * cloudscale * 0.5);

	// Octave counts cut (8→4, 8→4, 7→3) and the 4th detail layer (c1)
	// dropped entirely — these are the dominant per-pixel cost and the lost
	// detail is invisible on a slow-moving cloud background (iter 330).
	float r = 0.0;
	uv *= cloudscale;
	uv -= q - time;
	float weight = 0.8;
	for (int i = 0; i < 4; i++) {
		r += abs(weight * noise(uv));
		uv = m * uv + time;
		weight *= 0.7;
	}

	float f = 0.0;
	uv = p * cloudscale;
	uv -= q - time;
	weight = 0.7;
	for (int i = 0; i < 4; i++) {
		f += weight * noise(uv);
		uv = m * uv + time;
		weight *= 0.6;
	}
	f *= r + f;

	float c = 0.0;
	time = TIME * cloud_speed * 2.0;
	uv = p * cloudscale * 2.0;
	uv -= q - time;
	weight = 0.4;
	for (int i = 0; i < 3; i++) {
		c += weight * noise(uv);
		uv = m * uv + time;
		weight *= 0.6;
	}

	vec3 skycolour = mix(sky_color_bot, sky_color_top, hy);
	vec3 cloudcolour = cloud_color * clamp((clouddark + cloudlight * c), 0.0, 1.0);
	// Fade clouds toward the horizon so they don't smear into a singularity.
	float horizon_fade = smoothstep(0.0, 0.25, EYEDIR.y);
	f = (cloudcover + cloudalpha * f * r) * horizon_fade;
	vec3 result = mix(skycolour, clamp(skytint * skycolour + cloudcolour, 0.0, 1.0), clamp(f + c * horizon_fade, 0.0, 1.0));

	COLOR = result;
}
