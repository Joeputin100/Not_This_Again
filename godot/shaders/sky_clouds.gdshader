shader_type sky;

// Lean procedural cloud sky (iter 331 perf rewrite).
//
// REPLACES the earlier drift "2D Clouds" port, which computed ~15 simplex-
// noise evaluations PER SCREEN PIXEL PER FRAME. On a 1080x1920 mobile
// viewport that is ~30M noise evals/frame — the dominant cost that pinned the
// SP1 preview at ~23fps even after octave cuts.
//
// Here the noise is BAKED ONCE into a seamless texture (see CloudNoiseTex in
// sp1_crowd_viewer.tscn) and the shader just samples it a few times with
// scrolling/scaled UVs. GPU texture fetches are far cheaper than per-pixel
// simplex noise, so the animation cost collapses while the look is preserved.
// It is also from-scratch/original — no third-party shader license to honor.
//
// Uniform names match the old shader so sky_bodies._push_cloud_uniforms keeps
// driving per-preset sky colour / cloud tint / cover with no code change.

uniform vec3 sky_color_top : source_color = vec3(0.2, 0.4, 0.6);
uniform vec3 sky_color_bot : source_color = vec3(0.4, 0.7, 1.0);
uniform vec3 cloud_color : source_color = vec3(1.1, 1.1, 0.9);
uniform float cloudcover : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.006;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

// 3 octaves of the SAME precomputed noise, at rising frequency + independent
// drift directions so the layers don't slide in lockstep. ~3 texture taps.
float cloud_fbm(vec2 uv, float t) {
	float n  = texture(noise_tex, uv * 1.0 + vec2(t,        t * 0.2)).r * 0.55;
	n       += texture(noise_tex, uv * 2.3 + vec2(-t * 1.6, t * 0.7)).r * 0.30;
	n       += texture(noise_tex, uv * 4.9 + vec2(t * 2.4, -t * 0.4)).r * 0.15;
	return n; // ~0..1
}

void sky() {
	// Height factor: 0 at the horizon, 1 straight up.
	float hy = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 skycolour = mix(sky_color_bot, sky_color_top, hy);

	// Project the view direction onto a plane overhead so clouds recede toward
	// the horizon (same mapping the old shader used).
	vec2 uv = EYEDIR.xz / max(EYEDIR.y * 0.8 + 0.25, 0.18) * 0.35;
	float t = TIME * cloud_speed;
	float d = cloud_fbm(uv, t);

	// cloudcover raises the cloud floor (more sky covered). Soft edges via
	// smoothstep keep the clouds wispy rather than hard-edged.
	float density = smoothstep(0.55 - cloudcover * 0.5, 0.95, d);
	// Fade clouds out at the horizon so the projection singularity there
	// doesn't smear into a band.
	density *= smoothstep(0.0, 0.25, EYEDIR.y);

	// Subtle self-shading: denser cores read slightly brighter.
	vec3 lit = cloud_color * (0.85 + 0.15 * d);
	COLOR = mix(skycolour, lit, clamp(density, 0.0, 1.0));
}
