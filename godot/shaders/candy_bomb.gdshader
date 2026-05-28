shader_type canvas_item;

// "Candy bomb" projectile, baked to a sprite. Ported from bradjamesgrant's
// Shadertoy "fractal pyramid" (fractal SDF raymarch with step-accumulated
// glow). Self-contained (no globals, no texture channels). A fixed bake_time
// freezes one frame; the glow's soft edges are recovered to alpha via the
// 2-pass diff-matte (scripts/diff_matte.py) at bake time.

uniform float bake_time : hint_range(0.0, 6.28) = 3.0;
uniform vec3 glow_a : source_color = vec3(0.2, 0.7, 0.9);  // cyan
uniform vec3 glow_b : source_color = vec3(1.0, 0.0, 1.0);  // magenta
uniform float brightness : hint_range(0.5, 3.0) = 1.0;

vec3 palette(float d) { return mix(glow_a, glow_b, d); }

vec2 rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return p * mat2(vec2(c, s), vec2(-s, c));
}

float map(vec3 p) {
	for (int i = 0; i < 8; ++i) {
		float t = bake_time * 0.2;
		p.xz = rotate(p.xz, t);
		p.xy = rotate(p.xy, t * 1.89);
		p.xz = abs(p.xz);
		p.xz -= 0.5;
	}
	return dot(sign(p), p) / 5.0;
}

vec4 rm(vec3 ro, vec3 rd) {
	float t = 0.0;
	vec3 col = vec3(0.0);
	float d = 0.0;
	for (float i = 0.0; i < 64.0; i++) {
		vec3 p = ro + rd * t;
		d = map(p) * 0.5;
		if (d < 0.02) break;
		if (d > 100.0) break;
		col += palette(length(p) * 0.1) / (400.0 * d);
		t += d;
	}
	return vec4(col, 1.0 / (d * 100.0));
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	vec3 ro = vec3(0.0, 0.0, -50.0);
	ro.xz = rotate(ro.xz, bake_time);
	vec3 cf = normalize(-ro);
	vec3 cs = normalize(cross(cf, vec3(0.0, 1.0, 0.0)));
	vec3 cu = normalize(cross(cf, cs));
	vec3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;
	vec3 rd = normalize(uuv - ro);
	vec4 col = rm(ro, rd);
	COLOR = vec4(col.rgb * brightness, 1.0);
}
