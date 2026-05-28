shader_type canvas_item;

// Cotton-candy projectile, baked to a sprite. The "cotton candy" look is the
// volumetric fbm-cloud rendering from Nrx's Shadertoy "Cotton candy Pac-Man"
// (MlfGR4) — we keep that fluffy pastel volumetric material but march it over
// a SPHERE instead of the Pac-Man/ghost SDFs, and output accumulated density
// as alpha so the fluff has soft transparent edges over any background.
// iChannel0 noise-texture lookup is replaced with procedural value noise.

uniform vec3 candy_a : source_color = vec3(1.0, 0.62, 0.85);  // pink floss
uniform vec3 candy_b : source_color = vec3(0.62, 0.80, 1.0);  // blue floss
uniform float fluff : hint_range(2.0, 12.0) = 7.0;            // noiseFactor
uniform float density_factor : hint_range(0.1, 1.0) = 0.45;

const int RAY_STEP_MAX = 90;
const float RAY_LENGTH_MAX = 220.0;
const float DIST_CORRECTION = 0.8;
const float DIST_MIN = 1.5;
const float CAM_DIST = 80.0;
const float SPHERE_R = 30.0;

float hash(float n) { return fract(sin(n) * 43758.5453123); }

float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n = p.x + p.y * 157.0 + 113.0 * p.z;
	return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
			mix(hash(n + 157.0), hash(n + 158.0), f.x), f.y),
		mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
			mix(hash(n + 270.0), hash(n + 271.0), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise(p) + noise(p * 2.0) / 2.0 + noise(p * 4.0) / 4.0;
}

// Distance to the fluffy sphere + a colour-blend factor in .y.
vec2 distScene(vec3 p) {
	float sphere = length(p) - SPHERE_R;
	// Pink/blue swirl factor from a low-frequency noise.
	float t = 0.5 + 0.5 * sin(p.x * 0.05 + fbm(p * 0.06) * 3.0);
	vec2 d = vec2(sphere, t);
	// Fluff: push the surface outward by fbm so it reads as cloud, not ball.
	d.x += fluff * (fbm(p * 0.06) - 1.4);
	return d;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0;
	uv.y = -uv.y;
	vec3 ro = vec3(0.0, 0.0, -CAM_DIST);
	vec3 rd = normalize(vec3(uv, 2.2));

	float densityTotal = 0.0;
	vec3 colorTotal = vec3(0.0);
	float rayLength = 0.0;
	for (int s = 0; s < RAY_STEP_MAX; ++s) {
		float densityMax = 1.0 - rayLength / RAY_LENGTH_MAX;
		if (densityTotal > densityMax) {
			break;
		}
		vec3 p = ro + rd * rayLength;
		vec2 data = distScene(p);
		float dist = data.x * DIST_CORRECTION;
		if (dist < 0.0) {
			float densityLocal = (densityTotal - densityMax) * dist * density_factor;
			densityTotal += densityLocal;
			vec3 colorLocal = mix(candy_a, candy_b, data.y);
			colorTotal += colorLocal * densityLocal;
		}
		rayLength += max(dist, DIST_MIN);
	}

	densityTotal = clamp(densityTotal, 0.0, 1.0);
	vec3 rgb = densityTotal > 0.001 ? colorTotal / densityTotal : vec3(0.0);
	COLOR = vec4(rgb, densityTotal);
}
