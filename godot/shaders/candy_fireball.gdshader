shader_type canvas_item;

// Candy fireball, baked to a sprite. The sparkly pattern is simonsdev's
// Shadertoy "Kaleidoscopix 3" kaleidoscope fold, re-tinted to fire tones and
// wrapped onto a sphere: the 2D fold-coords are compressed toward the rim by
// the sphere normal so the kaleidoscope reads as a glowing 3D orb rather than
// a flat disc. Baked as glow-on-black (alpha from luminance) with a circular
// containment.

uniform float bake_time : hint_range(0.0, 12.0) = 1.0;
uniform vec3 fire_core : source_color = vec3(1.0, 0.85, 0.45);  // hot yellow-white
uniform vec3 fire_mid : source_color = vec3(1.0, 0.35, 0.08);   // orange
uniform vec3 fire_edge : source_color = vec3(0.75, 0.05, 0.02);  // deep red
uniform float sparkle : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	vec2 dd = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(dd, dd);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float nz = sqrt(1.0 - r2);
		float rr = sqrt(r2);
		// Mild spherical compression so the kaleidoscope curves over the ball,
		// but keep it dense (small factor) so it stays bright.
		vec2 u = dd * 2.2 / (0.7 + 0.3 * nz);

		float t = bake_time * 0.2;
		float d = 1e3;
		vec3 c = vec3(0.0);
		float cs = cos(t);
		float sn = sin(t);
		mat2 rot = mat2(vec2(cs, -sn), vec2(sn, cs));
		for (int i = 0; i < 8; i++) {
			u = abs(u * rot) - 0.25;
			u -= 0.05 / (dot(u, u) + 0.06);
			float lu = length(u);
			d = min(d, lu);
			vec3 tone = mix(fire_core, fire_mid, clamp(lu * 2.0, 0.0, 1.0));
			c += 0.02 / (lu + 0.02) * tone;
		}
		vec3 col = c * exp(-d * 2.0) * sparkle;
		// Radial fire shaping: hot bright center → deep-red fiery rim.
		col *= mix(vec3(1.4), fire_edge * 2.5, smoothstep(0.25, 1.0, rr));
		col += fire_core * pow(nz, 4.0) * 0.25;  // hot specular-ish core

		float lum = clamp(dot(col, vec3(0.4, 0.4, 0.4)), 0.0, 1.0);
		float edge = smoothstep(1.0, 0.9, r2);
		COLOR = vec4(col, clamp(lum * 1.6, 0.0, 1.0) * edge);
	}
}
