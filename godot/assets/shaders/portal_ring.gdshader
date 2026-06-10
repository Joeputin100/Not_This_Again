shader_type canvas_item;

// Jawbreaker charge-telegraph ground ring — the "portal" look from the
// roguelike webgl_effects_demo (swirling vortex + rainbow shimmer + dark
// core + circular vignette), captured in ONE canvas_item pass instead of
// the demo's multi-pass Navier-Stokes sim (mobile-safe: this is the same
// shader class as chromakey.gdshader; spatial shaders white-rect on the
// Android renderer, canvas shaders do not).
//
// Rendered into a transparent SubViewport, sampled by a flat ground
// Sprite3D at the boss's feet. `progress` (0..1) grows the ring across the
// charge window; the driver frees the viewport on blast.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float time_scale = 1.0;

// cheap value noise + 3-octave fbm (enough for swirl wisps at telegraph size)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	v += 0.5 * vnoise(p);
	v += 0.25 * vnoise(p * 2.1);
	v += 0.125 * vnoise(p * 4.3);
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = TIME * time_scale;

	// vortex: rotate UV by an angle that grows toward the center (the
	// portal's swirl read), then advect noise along it
	float ang = atan(p.y, p.x);
	float swirl = ang + (1.4 - r) * 3.0 + t * 1.2;
	vec2 sp = vec2(cos(swirl), sin(swirl)) * r;
	float wisps = fbm(sp * 3.0 + vec2(t * 0.35, -t * 0.2));

	// rainbow shimmer (the demo's display-pass hue trick)
	float hue = fract(t * 0.2 + UV.x * 2.0 + UV.y * 1.5);
	vec3 c6 = abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0;
	vec3 rainbow = clamp(c6, 0.0, 1.0);

	// icy portal palette: dark blue-violet base + cold cyan wisps + shimmer
	vec3 base = vec3(0.04, 0.06, 0.18);
	vec3 col = base + vec3(0.35, 0.75, 1.0) * wisps * 0.9 + rainbow * 0.20;

	// ring mask: outer edge expands with charge progress; bright rim,
	// translucent swirling interior, dark hole at the very center
	float outer = 0.25 + 0.75 * progress;
	float rim = smoothstep(outer, outer - 0.06, r) - smoothstep(outer - 0.10, outer - 0.30, r) * 0.55;
	float interior = smoothstep(outer, 0.0, r) * 0.5;
	float core_hole = smoothstep(0.10, 0.22, r);
	float alpha = clamp((rim + interior * wisps) * core_hole, 0.0, 1.0);
	// pulse harder as release approaches
	alpha *= 0.65 + 0.35 * sin(t * (6.0 + 8.0 * progress));

	COLOR = vec4(col * (1.2 + progress), alpha * (0.55 + 0.45 * progress));
}
