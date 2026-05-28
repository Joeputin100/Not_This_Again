shader_type canvas_item;

// Freeze-ray candy, baked to a sprite. PROTOTYPE — pattern from
// Dave_Hoskins' Shadertoy "Warp Speed 2" (CC-BY-NC-SA, see memory
// project_candy_shader_licensing). Tinted electric blue and wrapped on a
// sphere, with a few jagged lightning bolts overlaid for a frozen-energy
// look (Fudgicle Frostbite Pistol projectile).

uniform float bake_time : hint_range(0.0, 6.0) = 1.0;
uniform vec3 ice_color : source_color = vec3(0.35, 0.7, 1.0);
uniform float bolt_count : hint_range(0.0, 10.0) = 5.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 dd = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(dd, dd);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float nz = sqrt(1.0 - r2);
		vec2 uv = dd / (0.65 + 0.35 * nz);

		float s = 0.0;
		float v = 0.0;
		float time = (bake_time - 2.0) * 58.0;
		vec3 col = vec3(0.0);
		vec3 init = vec3(sin(time * 0.0032) * 0.3, 0.35 - cos(time * 0.005) * 0.3, time * 0.002);
		for (int r = 0; r < 60; r++) {
			vec3 p = init + s * vec3(uv, 0.05);
			p.z = fract(p.z);
			for (int i = 0; i < 10; i++) p = abs(p * 2.04) / dot(p, p) - 0.9;
			v += pow(dot(p, p), 0.7) * 0.06;
			col += vec3(v * 0.2 + 0.4, 12.0 - s * 2.0, 0.1 + v * 1.0) * v * 0.00003;
			s += 0.025;
		}
		// Electric-blue tint: drive brightness from the warp, recolour to ice.
		// Keep the core from blowing fully white — only the brightest cores
		// get a touch of white-hot, the rest stays electric blue.
		float warp = clamp(length(tanh(col * 1.4)), 0.0, 1.0);
		col = ice_color * warp * 1.4 + vec3(0.85, 0.95, 1.0) * pow(warp, 6.0) * 0.6;

		// Lightning bolts: radial jagged bright lines from the centre.
		float ang = atan(dd.y, dd.x);
		float rad = sqrt(r2);
		float bolts = 0.0;
		for (int b = 0; b < 10; b++) {
			if (float(b) >= bolt_count) break;
			float ba = (float(b) / bolt_count) * 6.2831853;
			// jagged: wobble the angle by a hash along the radius
			float jag = (hash21(vec2(float(b), floor(rad * 12.0))) - 0.5) * 0.5;
			float da = abs(mod(ang - ba - jag + 3.14159, 6.2831853) - 3.14159);
			bolts += smoothstep(0.06, 0.0, da) * smoothstep(1.0, 0.1, rad);
		}
		col += vec3(0.8, 0.95, 1.0) * bolts * 1.2;

		// Icy rim + crisp mask.
		col += ice_color * pow(1.0 - nz, 4.0) * 0.4;
		float edge = smoothstep(1.0, 0.96, r2);
		COLOR = vec4(col, clamp(max(col.r, max(col.g, col.b)) * 1.2, 0.0, 1.0) * edge);
	}
}
