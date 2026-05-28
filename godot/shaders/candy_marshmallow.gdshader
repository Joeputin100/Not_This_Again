shader_type canvas_item;

// Marshmallow candy, baked to a sprite. ORIGINAL — written from scratch (no
// third-party shader source), so unlike the prototype candies this one is
// clean to ship. Combines the soft-volumetric feel of the cotton-candy bake
// with cloud-style fbm surface mottle, shaped as a rounded cylinder with a
// matte top-lit form + warm subsurface glow + powdery sugar dusting.

uniform vec3 base_color : source_color = vec3(0.97, 0.95, 0.93);  // matte white
uniform vec3 warm_color : source_color = vec3(1.0, 0.88, 0.82);   // subsurface cream-pink
uniform float dust_amount : hint_range(0.0, 1.0) = 0.4;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(p);
	float b = hash21(p + vec2(1.0, 0.0));
	float c = hash21(p + vec2(0.0, 1.0));
	float d = hash21(p + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float t = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		t += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return t;
}

// Rounded-box (rounded-cylinder silhouette) signed distance.
float rbox(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - half_size + vec2(r);
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	p.y = -p.y;  // +y up

	// Marshmallow silhouette: a squat rounded cylinder (wider than tall).
	float sdf = rbox(p, vec2(0.66, 0.5), 0.34);
	float inside = smoothstep(0.02, -0.02, sdf);  // soft edge
	if (inside <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		// Fake form normal from the SDF: a dome that bulges toward the viewer.
		float h = clamp(-sdf * 2.2, 0.0, 1.0);   // 0 at rim → 1 at centre
		float nz = sqrt(h);

		// Matte top-lit shading (light from upper-left, soft).
		float topLight = clamp(0.55 + 0.5 * p.y + 0.25 * nz, 0.0, 1.0);
		vec3 col = base_color * (0.65 + 0.45 * topLight);

		// Warm subsurface glow toward the centre/bottom (light scattering
		// through the soft candy).
		float sub = pow(h, 1.5) * (0.5 - 0.4 * p.y);
		col = mix(col, warm_color, clamp(sub, 0.0, 0.55));

		// Powdery surface mottle + a soft top "cylinder cap" highlight band.
		float mottle = fbm(p * 6.0 + 11.0);
		col *= 0.93 + 0.10 * mottle;
		float cap = smoothstep(0.25, 0.55, p.y) * smoothstep(0.0, 0.4, nz);
		col += vec3(1.0) * cap * 0.10;

		// Sugar dusting speckles.
		float dust = hash21(floor((p * 0.5 + 0.5) * 60.0));
		if (dust > 1.0 - 0.05 * dust_amount) col += vec3(0.18) * nz;

		// Soft, slightly fuzzy edge alpha.
		float a = inside * (0.85 + 0.15 * fbm(p * 8.0));
		COLOR = vec4(col, clamp(a, 0.0, 1.0));
	}
}
