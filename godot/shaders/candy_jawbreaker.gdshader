shader_type canvas_item;

// Jawbreaker candy, baked to a sprite. PROTOTYPE — pattern from
// Dave_Hoskins' Shadertoy "Warp Speed 2" (CC-BY-NC-SA, see memory
// project_candy_shader_licensing). The warp's chaotic multicolour fractal
// field gives the jawbreaker's swirly layers; we wrap it onto a sphere
// (spherical UV), add glossy round shading + a fresnel rim + a few bright
// sugar speckles, and a crisp circular alpha (hard candy).

uniform float bake_time : hint_range(0.0, 6.0) = 1.0;
uniform float speckle_amount : hint_range(0.0, 1.0) = 0.5;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 hsv2rgb(vec3 c) {
	vec3 r = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), r, c.y);
}

void fragment() {
	vec2 dd = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(dd, dd);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float nz = sqrt(1.0 - r2);
		// Spherical wrap: compress the warp field toward the rim.
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
		// Recolour the warp's radial streaks into multicolour candy bands:
		// brightness from the warp, hue from the fragment angle so each streak
		// is a different jawbreaker layer-colour.
		float intensity = length(tanh(col * 1.4));
		float hue = fract(atan(dd.y, dd.x) / 6.2831853 + 0.5 + intensity * 0.4);
		col = hsv2rgb(vec3(hue, 0.75, 1.0)) * intensity * 1.6;

		// Glossy round candy shading + fresnel rim.
		col *= 0.55 + 0.55 * nz;
		col += vec3(1.0, 0.95, 0.9) * pow(1.0 - nz, 4.0) * 0.35;
		col += vec3(1.0) * pow(nz, 16.0) * 0.25;  // hot specular dot

		// Bright sugar speckles scattered over the surface.
		float sp = hash21(floor((dd * 0.5 + 0.5) * 44.0));
		if (sp > 1.0 - 0.05 * speckle_amount) {
			col += vec3(1.0) * nz * 0.9;
		}

		float edge = smoothstep(1.0, 0.965, r2);
		COLOR = vec4(col, edge);
	}
}
