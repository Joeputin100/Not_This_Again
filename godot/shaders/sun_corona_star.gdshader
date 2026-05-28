shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled;

// Animated star corona. Ported from Shadertoy 4lfSzS "Awesome star"
// (Panteleymonov A K, 2015). Renders the star body + glow ring + rays;
// the deep-space nebula pass from the original is dropped for mobile perf.
// Drawn on a quad BEHIND the Imagen sun disc (additive), so the bright
// body sits behind the opaque disc and only the rays/glow read as corona.

uniform float star_scale : hint_range(1.0, 4.0) = 2.3;   // maps star body to the disc size inside a larger corona quad
uniform float time_scale : hint_range(0.0, 3.0) = 1.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float burst : hint_range(0.0, 2.0) = 0.0;        // tap variant-B flares the rays
uniform vec3 body_color : source_color = vec3(1.0, 1.0, 0.0);
uniform vec3 light_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 base_color : source_color = vec3(1.0, 0.0, 0.0);
uniform vec3 dark_color : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 ray_color : source_color = vec3(1.0, 0.6, 0.1);
uniform vec3 ray_light : source_color = vec3(1.0, 0.95, 1.0);

vec4 hash4(vec4 n) { return fract(sin(n) * 1399763.5453123); }

float noise4q(vec4 x) {
	vec4 n3 = vec4(0.0, 0.25, 0.5, 0.75);
	vec4 p2 = floor(x.wwww + n3);
	vec4 b = floor(x.xxxx + n3) + floor(x.yyyy + n3) * 157.0 + floor(x.zzzz + n3) * 113.0;
	vec4 p1 = b + fract(p2 * 0.00390625) * vec4(164352.0, -164352.0, 163840.0, -163840.0);
	p2 = b + fract((p2 + 1.0) * 0.00390625) * vec4(164352.0, -164352.0, 163840.0, -163840.0);
	vec4 f1 = fract(x.xxxx + n3);
	vec4 f2 = fract(x.yyyy + n3);
	f1 = f1 * f1 * (3.0 - 2.0 * f1);
	f2 = f2 * f2 * (3.0 - 2.0 * f2);
	vec4 n1 = vec4(0.0, 1.0, 157.0, 158.0);
	vec4 n2 = vec4(113.0, 114.0, 270.0, 271.0);
	vec4 vs1 = mix(hash4(p1), hash4(n1.yyyy + p1), f1);
	vec4 vs2 = mix(hash4(n1.zzzz + p1), hash4(n1.wwww + p1), f1);
	vec4 vs3 = mix(hash4(p2), hash4(n1.yyyy + p2), f1);
	vec4 vs4 = mix(hash4(n1.zzzz + p2), hash4(n1.wwww + p2), f1);
	vs1 = mix(vs1, vs2, f2);
	vs3 = mix(vs3, vs4, f2);
	vs2 = mix(hash4(n2.xxxx + p1), hash4(n2.yyyy + p1), f1);
	vs4 = mix(hash4(n2.zzzz + p1), hash4(n2.wwww + p1), f1);
	vs2 = mix(vs2, vs4, f2);
	vs4 = mix(hash4(n2.xxxx + p2), hash4(n2.yyyy + p2), f1);
	vec4 vs5 = mix(hash4(n2.zzzz + p2), hash4(n2.wwww + p2), f1);
	vs4 = mix(vs4, vs5, f2);
	f1 = fract(x.zzzz + n3);
	f2 = fract(x.wwww + n3);
	f1 = f1 * f1 * (3.0 - 2.0 * f1);
	f2 = f2 * f2 * (3.0 - 2.0 * f2);
	vs1 = mix(vs1, vs2, f1);
	vs3 = mix(vs3, vs4, f1);
	vs1 = mix(vs1, vs3, f2);
	float r = dot(vs1, vec4(0.25));
	return r * r * (3.0 - 2.0 * r);
}

float noiseSpere(vec3 ray, vec3 pos, float r, mat3 mr, float zoom, vec3 subnoise, float anim) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	vec3 r1 = vec3(0.0);
	float s = 0.0;
	float d = 0.03125;
	float d2 = zoom / (d * d);
	float ar = 5.0;
	for (int i = 0; i < 3; i++) {
		float rq = r * r;
		if (c < rq) {
			float l1 = sqrt(rq - c);
			r1 = ray * (b - l1) - pos;
			r1 = r1 * mr;
			s += abs(noise4q(vec4(r1 * d2 + subnoise * ar, anim * ar)) * d);
		}
		ar -= 2.0;
		d *= 4.0;
		d2 *= 0.0625;
		r = r - r * 0.02;
	}
	return s;
}

float ring(vec3 ray, vec3 pos, float r, float size) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	return max(0.0, (1.0 - size * abs(r - sqrt(c))));
}

float ringRayNoise(vec3 ray, vec3 pos, float r, float size, mat3 mr, float anim) {
	float b = dot(ray, pos);
	vec3 pr = ray * b - pos;
	float c = length(pr);
	pr *= mr;
	pr = normalize(pr);
	float s = max(0.0, (1.0 - size * abs(r - c)));
	float nd = noise4q(vec4(pr * 1.0, -anim + c)) * 2.0;
	nd = pow(nd, 2.0);
	float n = 0.4;
	float ns = 1.0;
	if (c > r) {
		n = noise4q(vec4(pr * 10.0, -anim + c));
		ns = noise4q(vec4(pr * 50.0, -anim * 2.5 + c * 2.0)) * 2.0;
	}
	n = n * n * nd * ns;
	return pow(s, 4.0) + s * s * n;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * star_scale;
	float time = TIME * time_scale;
	float mx = time * 0.025;
	float my = -0.6;
	vec2 sins = sin(vec2(mx, my));
	vec2 coss = cos(vec2(mx, my));
	mat3 mr = mat3(vec3(coss.x, 0.0, sins.x), vec3(0.0, 1.0, 0.0), vec3(-sins.x, 0.0, coss.x));
	mr = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, coss.y, sins.y), vec3(0.0, -sins.y, coss.y)) * mr;

	vec3 ray = normalize(vec3(p, 2.0));
	vec3 pos = vec3(0.0, 0.0, 3.0);

	float s1 = noiseSpere(ray, pos, 1.0, mr, 0.5, vec3(0.0), time);
	s1 = pow(min(1.0, s1 * 2.4), 2.0);
	float s2 = noiseSpere(ray, pos, 1.0, mr, 4.0, vec3(83.23, 34.34, 67.453), time);
	s2 = min(1.0, s2 * 2.2);

	vec3 col = mix(body_color, light_color, pow(s1, 60.0)) * s1;
	col += mix(mix(base_color, dark_color, pow(s2, 2.0)), light_color, pow(s2, 10.0)) * s2;
	col -= vec3(ring(ray, pos, 1.03, 11.0)) * 2.0;
	col = max(vec3(0.0), col);

	float s3 = ringRayNoise(ray, pos, 0.96, 1.0, mr, time);
	col += mix(ray_color, ray_light, pow(s3, 3.0)) * s3 * (1.0 + burst);

	col = clamp(col, vec3(0.0), vec3(1.0));
	ALBEDO = col * intensity;
	ALPHA = 1.0;
}
