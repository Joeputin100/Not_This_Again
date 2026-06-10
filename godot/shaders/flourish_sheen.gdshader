shader_type canvas_item;

// Soda-Crush-style embossed text MAIN layer: vertical two-tone gradient of
// the tint (golden by default) + a moving diagonal light band so the shine
// visibly travels as the text moves. Glyph alpha comes from COLOR.a; we
// REPLACE rgb (theme font color is white). Box-space coords come from the
// vertex shader (text UV is the glyph atlas — useless for gradients).

uniform vec4 tint : source_color = vec4(1.0, 0.84, 0.35, 1.0);
uniform float row_height = 160.0;   // px; set per row for the gradient
uniform float sheen_speed = 220.0;  // px/sec the light band travels
uniform float sheen_width = 140.0;  // px band width

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float g = clamp(v_pos.y / max(row_height, 1.0), 0.0, 1.0);
	// lit top -> deeper bottom (embossed gold read)
	vec3 hi = min(tint.rgb * 1.30 + vec3(0.10), vec3(1.0));
	vec3 lo = tint.rgb * 0.62;
	vec3 col = mix(hi, lo, g);
	// travelling diagonal shine: position-driven, so motion changes the glint
	float band = mod(v_pos.x + v_pos.y * 0.6 - TIME * sheen_speed, 900.0);
	float shine = smoothstep(0.0, sheen_width * 0.5, band)
		* (1.0 - smoothstep(sheen_width * 0.5, sheen_width, band));
	col += vec3(0.55, 0.50, 0.35) * shine;
	COLOR = vec4(min(col, vec3(1.0)), COLOR.a);
}
