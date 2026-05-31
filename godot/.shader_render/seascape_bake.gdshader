shader_type canvas_item;

// Offline-bake port of "Seascape" by Alexander Alekseev (TDM), 2014 —
// CC BY-NC-SA 3.0. Rendered to a PNG sequence on the desktop (lavapipe) and
// shipped as frames; the phone never runs this. NonCommercial → prototype
// asset, recreate before any commercial release (see project memory).
//
// Adapted to canvas_item: fixed low camera over moving water (no forward fly,
// so the wave motion can be looped); `u_time` is driven per frame by the bake
// harness. iResolution is the render size; we read it from a uniform.

uniform float u_time = 0.0;
uniform vec2 u_res = vec2(512.0, 512.0);

const int NUM_STEPS = 24;
const float EPSILON = 1e-3;

const int ITER_GEOMETRY = 3;
const int ITER_FRAGMENT = 5;
const float SEA_HEIGHT = 0.6;
const float SEA_CHOPPY = 4.0;
const float SEA_SPEED = 0.8;
const float SEA_FREQ = 0.16;
const vec3 SEA_BASE = vec3(0.0, 0.09, 0.18);
const vec3 SEA_WATER_COLOR = vec3(0.48, 0.54, 0.36);  // (0.8,0.9,0.6)*0.6
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

float sea_time() { return 1.0 + u_time * SEA_SPEED; }

float hash(vec2 p) {
	float h = dot(p, vec2(127.1, 311.7));
	return fract(sin(h) * 43758.5453123);
}
float noise(in vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return -1.0 + 2.0 * mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
							mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float diffuse(vec3 n, vec3 l, float p) { return pow(dot(n, l) * 0.4 + 0.6, p); }
float specular(vec3 n, vec3 l, vec3 e, float s) {
	float nrm = (s + 8.0) / (PI * 8.0);
	return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}
vec3 getSkyColor(vec3 e) {
	e.y = (max(e.y, 0.0) * 0.8 + 0.2) * 0.8;
	return vec3(pow(1.0 - e.y, 2.0), 1.0 - e.y, 0.6 + (1.0 - e.y) * 0.4) * 1.1;
}
float sea_octave(vec2 uv, float choppy) {
	uv += noise(uv);
	vec2 wv = 1.0 - abs(sin(uv));
	vec2 swv = abs(cos(uv));
	wv = mix(wv, swv, wv);
	return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}
float map(vec3 p) {
	float freq = SEA_FREQ;
	float amp = SEA_HEIGHT;
	float choppy = SEA_CHOPPY;
	vec2 uv = p.xz; uv.x *= 0.75;
	float d;
	float h = 0.0;
	for (int i = 0; i < ITER_GEOMETRY; i++) {
		d = sea_octave((uv + sea_time()) * freq, choppy);
		d += sea_octave((uv - sea_time()) * freq, choppy);
		h += d * amp;
		uv *= octave_m; freq *= 1.9; amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return p.y - h;
}
float map_detailed(vec3 p) {
	float freq = SEA_FREQ;
	float amp = SEA_HEIGHT;
	float choppy = SEA_CHOPPY;
	vec2 uv = p.xz; uv.x *= 0.75;
	float d;
	float h = 0.0;
	for (int i = 0; i < ITER_FRAGMENT; i++) {
		d = sea_octave((uv + sea_time()) * freq, choppy);
		d += sea_octave((uv - sea_time()) * freq, choppy);
		h += d * amp;
		uv *= octave_m; freq *= 1.9; amp *= 0.22;
		choppy = mix(choppy, 1.0, 0.2);
	}
	return p.y - h;
}
vec3 getSeaColor(vec3 p, vec3 n, vec3 l, vec3 eye, vec3 dist) {
	float fresnel = clamp(1.0 - dot(n, -eye), 0.0, 1.0);
	fresnel = min(fresnel * fresnel * fresnel, 0.5);
	vec3 reflected = getSkyColor(reflect(eye, n));
	vec3 refracted = SEA_BASE + diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;
	vec3 color = mix(refracted, reflected, fresnel);
	float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
	color += SEA_WATER_COLOR * (p.y - SEA_HEIGHT) * 0.18 * atten;
	color += specular(n, l, eye, 60.0);
	return color;
}
vec3 getNormal(vec3 p, float eps) {
	vec3 n;
	n.y = map_detailed(p);
	n.x = map_detailed(vec3(p.x + eps, p.y, p.z)) - n.y;
	n.z = map_detailed(vec3(p.x, p.y, p.z + eps)) - n.y;
	n.y = eps;
	return normalize(n);
}
float heightMapTracing(vec3 ori, vec3 dir, out vec3 p) {
	float tm = 0.0;
	float tx = 1000.0;
	float hx = map(ori + dir * tx);
	if (hx > 0.0) { p = ori + dir * tx; return tx; }
	float hm = map(ori);
	for (int i = 0; i < NUM_STEPS; i++) {
		float tmid = mix(tm, tx, hm / (hm - hx));
		p = ori + dir * tmid;
		float hmid = map(p);
		if (hmid < 0.0) { tx = tmid; hx = hmid; } else { tm = tmid; hm = hmid; }
		if (abs(hmid) < EPSILON) break;
	}
	return mix(tm, tx, hm / (hm - hx));
}

void fragment() {
	vec2 uv = UV;
	uv = uv * 2.0 - 1.0;
	uv.x *= u_res.x / u_res.y;
	// Fixed camera looking steeply DOWN at the water so the whole frame is sea
	// surface (no horizon/sky split) — reads as a water disc for the orb halo.
	vec3 ori = vec3(0.0, 6.0, 0.0);
	vec3 dir = normalize(vec3(uv.x, uv.y * 0.8 - 2.2, -1.4));
	vec3 p;
	heightMapTracing(ori, dir, p);
	vec3 dist = p - ori;
	vec3 n = getNormal(p, dot(dist, dist) * (0.1 / u_res.x));
	vec3 light = normalize(vec3(0.0, 1.0, 0.8));
	vec3 col = mix(getSkyColor(dir), getSeaColor(p, n, light, dir, dist),
				pow(smoothstep(0.0, -0.02, dir.y), 0.2));
	col = pow(col, vec3(0.65));  // tonemap (Seascape's final pow)
	COLOR = vec4(col, 1.0);
}
