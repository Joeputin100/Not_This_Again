shader_type canvas_item;

// Single gummy/chocolate candy, baked to a sprite. Extracted from fizzer's
// Shadertoy "Unlimited Confectionery" (4dl3R4... lsj3zy) gummy() material —
// dropped the raymarched floor/camera/fly-through scene. Renders ONE candy
// (lit sphere) on transparent background; candy_colour picks the jewel tone.
// Bake the variants to PNG via the candy-sprite preview scene, then use them
// as the jellybean-frenzy projectiles.

uniform float candy_colour : hint_range(0.0, 3.0) = 0.0;  // 0 red, 1 green, 2 blue, 3 amber
uniform int candy_type : hint_range(0, 2) = 0;           // 0 gummy, 1 choc swirl, 2 choc stripe
uniform vec2 tc = vec2(0.0);
const vec3 LDIR = vec3(0.316, 0.949, 0.0);  // normalize(vec3(10,30,0))

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

float fbm3(vec3 p) {
	float f = 0.0;
	float x;
	for (int i = 1; i <= 9; ++i) {
		x = exp2(float(i));
		f += (noise(p * x) - 0.5) / x;
	}
	return f;
}
float fbm2(vec2 g) { return fbm3(vec3(g, 0.0)); }

// Chocolate material adapted from fizzer's trace() is_choc branch. surf is
// the candy's surface coord (sphere xy), n the normal, v the view dir.
vec3 chocolate(vec3 n, vec3 v, vec2 surf, int style) {
	vec3 h = normalize(LDIR - v);
	vec3 chocolour;
	if (style == 1) {
		float r = pow(length(surf) * 0.6, 2.0);
		chocolour = mix(vec3(2.0, 2.0, 1.3) * 2.0, vec3(1.3, 0.6, 0.2) * 0.6,
			smoothstep(0.5 + r, 0.6 + r, 0.4 + fbm2(surf * 10.0)));
	} else {
		chocolour = mix(vec3(1.3, 0.6, 0.2), vec3(2.0, 2.0, 1.3) * 2.0,
			smoothstep(0.7, 0.9, 0.5 + 0.5 * cos(surf.x * 10.0 + sin(surf.y * 5.0))));
	}
	// Brighter ambient than the original scene (0.5..1.0 wrap) so a single
	// camera-facing candy reads as chocolate rather than near-black — the
	// shader's scene had floor bounce + icing fill we don't get on a sprite.
	float diff = 0.55 + 0.45 * dot(n, LDIR);
	vec3 col = (0.22 * chocolour * vec3(diff)
		+ 0.10 * vec3(1.0, 1.0, 0.5) * vec3(pow(clamp(0.5 + 0.5 * dot(h, n), 0.0, 1.0), 20.0)))
		* (1.0 + 0.6 * pow(dot(n, -v), 2.0));
	return col * 5.0;
}

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
		vec3 col;
		if (candy_type == 0) {
			col = gummy(no, no, v) * 5.0;
		} else {
			col = chocolate(no, v, vec2(d.x, -d.y), candy_type);
		}
		col = sqrt(max(col, vec3(0.0)) * 1.4);
		// Soft 1px edge so the candy silhouette isn't aliased.
		float a = smoothstep(1.0, 0.97, r2);
		COLOR = vec4(col, a);
	}
}
