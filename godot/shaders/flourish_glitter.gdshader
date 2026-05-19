shader_type canvas_item;

// Iter 143: glitter overlay for FlourishBanner labels.
// Adds animated sparkle dots ONLY on opaque label pixels so the text body
// twinkles without bleeding sparkles into the bounding-box transparent area.
// User request: "can we add a glitter shader to the sugar rush text?"

uniform float glitter_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float glitter_density : hint_range(0.0, 1.0) = 0.5;
uniform vec4 glitter_color : source_color = vec4(1.0, 0.95, 0.55, 1.0);
uniform float time_speed : hint_range(0.5, 8.0) = 4.0;
uniform float hue_shift_amount : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		// Sparkle: high-frequency noise threshold animated over TIME.
		// Density 0.5 → step(0.975) ≈ 2.5% of pixels active at any moment.
		vec2 sparkle_uv = UV * vec2(160.0, 60.0);
		float n = fract(sin(dot(sparkle_uv, vec2(12.9898, 78.233)) + TIME * time_speed) * 43758.5453);
		float threshold = mix(1.0, 0.90, glitter_density);
		float sparkle = step(threshold, n);
		float pulse = 0.6 + sin(TIME * 6.0) * 0.4;

		// Slow hue cycle: cyclic RGB permutation at low amplitude
		vec3 cycled = mix(tex.rgb, tex.rbg, sin(TIME * 2.0) * 0.5 + 0.5);
		cycled = mix(cycled, cycled.gbr, sin(TIME * 2.0 + 2.094) * 0.5 + 0.5);
		vec3 base = mix(tex.rgb, cycled, hue_shift_amount);

		COLOR = vec4(base + glitter_color.rgb * sparkle * pulse * glitter_intensity, tex.a);
	}
}
