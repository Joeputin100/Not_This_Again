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

// Iter 335: horizon mountains BAKED INTO THE SKY (not a separate sprite — a
// transparent sprite over the sky erases it in the SubViewport; see memory).
// The matted candy-mountain texture is composited at the forward horizon band.
uniform sampler2D mountains_tex : source_color, filter_linear;
uniform bool mountains_on = false;
uniform float mtn_az_half = 0.62;   // half azimuth span (rad) the range covers
uniform float mtn_base = -0.26;     // bottom of band (below true horizon, ≈ the
                                    // terrain far-edge elevation, so bases sit on it)
uniform float mtn_top = 0.19;       // top elevation (rad) of the mountain band (peaks) — iter339: raised so peaks clear the hilly terrain
uniform float mtn_pan = 0.0;        // iter343: horizontal UV shift driven by path panning → slight mountain parallax

void sky() {
	// Height factor: 0 at the horizon, 1 straight up.
	float hy = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 skycolour = mix(sky_color_bot, sky_color_top, hy);

	// Project the view direction onto a plane overhead so clouds recede toward
	// the horizon (same mapping the old shader used).
	vec2 uv = EYEDIR.xz / max(EYEDIR.y * 0.8 + 0.25, 0.18) * 0.35;
	float t = TIME * cloud_speed;

	// Two prerendered cloud layers (the SAME baked high-octave noise) at
	// different scales + drift rates → parallax depth and billowing, the look
	// the heavy live shader produced but for ~2 texture taps. A near layer
	// carries the big masses, a far layer adds finer wisps that scroll faster.
	float near = texture(noise_tex, uv * 0.9 + vec2(t,        t * 0.15)).r;
	float far  = texture(noise_tex, uv * 1.9 + vec2(-t * 0.6, t * 0.45)).r;
	// Billow combine: emphasise where both layers agree → puffy cores with
	// torn edges rather than a flat wash.
	float d = clamp(near * 0.6 + far * 0.4 + near * far * 0.25, 0.0, 1.0);

	// cloudcover drives coverage across the whole weather range: low cover
	// shows only the densest puffs (clear/fair); high cover fills the sky in
	// (overcast → stormy). `lo` is the density threshold clouds start at.
	float lo = mix(0.80, 0.02, cloudcover);
	float density = smoothstep(lo, lo + 0.30, d);
	float core = smoothstep(lo + 0.16, lo + 0.46, d);  // brighter dense centres
	// Fade clouds out at the horizon so the projection singularity there
	// doesn't smear into a band.
	density *= smoothstep(0.0, 0.22, EYEDIR.y);

	// Self-shading: bright sunlit tops over darker bulk for volume. With a
	// dark cloud_color + high cover (stormy preset) this reads as heavy,
	// menacing cloud; with a bright tint + low cover it's fair-weather puffs.
	vec3 lit = cloud_color * (0.80 + 0.38 * core);
	vec3 result = mix(skycolour, lit, clamp(density, 0.0, 1.0));

	// Horizon mountains: forward-facing band from the horizon (EYEDIR.y≈0) up to
	// mtn_top, spanning ±mtn_az_half in azimuth. Texture V runs bottom (base, at
	// the horizon) → top (peaks/transparent), so the matted silhouette's alpha
	// draws the candy ridge directly into the opaque sky.
	if (mountains_on && -EYEDIR.z > 0.0 && EYEDIR.y > mtn_base && EYEDIR.y < mtn_top) {
		float az = atan(EYEDIR.x, -EYEDIR.z);
		if (abs(az) < mtn_az_half) {
			float v = (mtn_top - EYEDIR.y) / (mtn_top - mtn_base);
			vec4 m = texture(mountains_tex, vec2(0.5 + az / (2.0 * mtn_az_half) + mtn_pan, v));
			result = mix(result, m.rgb, m.a);
		}
	}
	COLOR = result;
}
