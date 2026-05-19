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
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Iter 144: glyph textures are grayscale-white. Multiply by the
		// label's modulate (canvas_item COLOR) to get the actual font tint.
		// Previous version dropped this multiply and rendered every banner
		// as solid bright white regardless of preset color.
		vec3 tinted = tex.rgb * COLOR.rgb;

		// Sparkle: high-frequency noise threshold animated over TIME.
		// Density 0.5 → step(0.95) ≈ 5% pixels active at any moment.
		vec2 sparkle_uv = UV * vec2(160.0, 60.0);
		float n = fract(sin(dot(sparkle_uv, vec2(12.9898, 78.233)) + TIME * time_speed) * 43758.5453);
		float threshold = mix(1.0, 0.88, glitter_density);
		float sparkle = step(threshold, n);
		float pulse = 0.5 + sin(TIME * 7.0) * 0.5;

		// Hue cycle on the tinted base (now non-grayscale so this actually shifts)
		vec3 cycled = mix(tinted, tinted.rbg, sin(TIME * 2.5) * 0.5 + 0.5);
		cycled = mix(cycled, cycled.gbr, sin(TIME * 2.5 + 2.094) * 0.5 + 0.5);
		vec3 base = mix(tinted, cycled, hue_shift_amount);

		COLOR = vec4(base + glitter_color.rgb * sparkle * pulse * glitter_intensity, tex.a * COLOR.a);
	}
}
