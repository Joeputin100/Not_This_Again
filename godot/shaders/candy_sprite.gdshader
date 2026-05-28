shader_type canvas_item;

// Single gummy/chocolate candy, baked to a sprite. Extracted from fizzer's
// Shadertoy "Unlimited Confectionery" (4dl3R4... lsj3zy) gummy() material —
// dropped the raymarched floor/camera/fly-through scene. Renders ONE candy
// (lit sphere) on transparent background; candy_colour picks the jewel tone.
// Bake the variants to PNG via the candy-sprite preview scene, then use them
// as the jellybean-frenzy projectiles.

uniform float candy_colour : hint_range(0.0, 3.0) = 0.0;  // 0 red, 1 green, 2 blue, 3 amber
uniform vec2 tc = vec2(0.0);

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

float smN2(vec2 p) { return noise(vec3(p, 0.0)); }

vec3 gumColour(float i) {
	if (i < 1.0) return vec3(0.11, 0.0, 0.002);
	else if (i < 2.0) return vec3(0.002, 0.06, 0.0);
	else if (i < 3.0) return vec3(0.0, 0.02, 0.11);
	else return vec3(0.11, 0.012, 0.0);
}

vec3 gumRamp(float i) {
	if (i < 1.0) return vec3(0.8, 1.0, 1.0);
	else if (i < 2.0) return vec3(0.8, 0.8, 1.0);
	else if (i < 3.0) return vec3(1.0, 0.8, 1.0);
	else return vec3(0.8, 0.8, 1.0);
}

vec2 rotate(float a, vec2 v) {
	return vec2(cos(a) * v.x + sin(a) * v.y, cos(a) * v.y - sin(a) * v.x);
}

float sugarybit(vec2 p) {
	p = clamp(p, vec2(-1.0), vec2(1.0));
	float a = 1.0 - pow((1.0 - pow(abs(p.x), 8.0)) * (1.0 - pow(abs(p.y), 8.0)) * 0.95, 0.5);
	float b = pow((1.0 - pow(abs(p.x), 8.0)) * (1.0 - pow(abs(p.y), 8.0)), 4.0);
	return a * b * 3.0;
}

float sugarlayer(vec2 t, float ndotv) {
	vec2 t2 = t.xy * 8.0;
	vec2 p = fract(t2) - vec2(0.5);
	vec2 c = floor(t2);
	float a = c.x + c.y * 5.0;
	vec2 o = vec2(cos(c.y * 53.0), sin(c.x * 125.0)) * 2.5;
	vec2 s = 1.0 + vec2(smN2(c), smN2(c + vec2(100.0)));
	float fres = mix(1.0, pow(1.0 - ndotv, 4.0), 0.9) * 25.0;
	return sugarybit(rotate(a, p * s * 4.0 + o)) * max(0.0, smN2(t2.xy * 5.0) - 0.5) * fres;
}

vec3 saturatecol(vec3 c) { return pow(c, gumRamp(candy_colour)); }

float sprinkles2(vec2 coord, float ndotv) {
	float sprinkle = 0.0;
	for (int i = 0; i < 4; ++i)
		sprinkle += sugarlayer((coord + vec2(float(i) * 10.45)) * (1.0 + float(i) * 0.2), ndotv) * pow(1.0 - float(i) / 4.0, 4.0);
	return sprinkle;
}

float sprinkles(vec2 coord, float ndotv) {
	return sprinkles2(coord * 0.75, ndotv) + sprinkles2(coord * 2.0, ndotv) * 0.3;
}

vec3 gummy(vec3 no, vec3 vo, vec3 v) {
	float ndotv = dot(no, -v);
	float s0 = sprinkles(vec2(atan(no.z, no.x), asin(no.y)) * 0.75, ndotv);
	float s1 = sprinkles(vo.xz, ndotv);
	float sprinkle = mix(s0, s1, smoothstep(0.3, 0.5, no.y));
	float ssf = clamp((no.y - 0.3) * 5.0, 0.0, 1.0);
	vec3 tex = saturatecol(mix(mix(vec3(0.5), gumColour(candy_colour), 0.98) * (0.1 + pow((1.0 - abs(tc.x)) * 0.5, 0.2)), vec3(2.0),
		sprinkle * ssf));
	tex *= 1.05 - ndotv;
	tex += vec3(pow(1.0 - ndotv, 8.0)) * 0.01;
	return tex;
}

void fragment() {
	// Map UV (0..1) to a unit disc; derive a sphere normal for the candy.
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(d, d);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 no = vec3(d.x, -d.y, sqrt(1.0 - r2));
		vec3 v = vec3(0.0, 0.0, -1.0);
		vec3 col = gummy(no, no, v) * 5.0;
		col = sqrt(max(col, vec3(0.0)) * 1.4);
		// Soft 1px edge so the candy silhouette isn't aliased.
		float a = smoothstep(1.0, 0.97, r2);
		COLOR = vec4(col, a);
	}
}
