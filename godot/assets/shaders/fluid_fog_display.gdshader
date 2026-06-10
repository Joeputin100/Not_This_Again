shader_type canvas_item;
// Fluid fog display — owner-approved look (look-dev report 2026-06-10:
// density 0.54 / dye 0.15 / cap 0.55 + flavor-marbling palette):
// dual 3-stop pink ramps picked by the advected flavor channel, drifting
// hue-tilting shimmer, soft band top.
uniform sampler2D dye_tex;
uniform float density = 0.54;
uniform float band_top = 0.52;
const float ALPHA_CAP = 0.55;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vno(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x),
		mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	if (UV.y < band_top) {
		COLOR = vec4(0.0);
	} else {
		vec2 sim_uv = vec2(UV.x, (UV.y - band_top) / (1.0 - band_top));
		vec2 d = texture(dye_tex, sim_uv).rg;
		float dye = d.r;
		float flavor = clamp(d.g / max(dye, 1e-4), 0.0, 1.0);
		float band = smoothstep(0.0, 0.35, sim_uv.y);
		float shim = vno(sim_uv * vec2(7.0, 4.0) + vec2(TIME * 0.06, -TIME * 0.03));
		// cool line: lavender-pink -> bubblegum -> orchid
		vec3 a1 = vec3(0.93, 0.82, 1.0);
		vec3 a2 = vec3(1.0, 0.62, 0.88);
		vec3 a3 = vec3(0.76, 0.45, 0.85);
		// warm line: peach-pink -> taffy -> raspberry
		vec3 b1 = vec3(1.0, 0.82, 0.74);
		vec3 b2 = vec3(1.0, 0.55, 0.62);
		vec3 b3 = vec3(0.88, 0.30, 0.50);
		float k = clamp(dye * 2.2, 0.0, 1.0);
		vec3 ca = k < 0.5 ? mix(a1, a2, k * 2.0) : mix(a2, a3, k * 2.0 - 1.0);
		vec3 cb = k < 0.5 ? mix(b1, b2, k * 2.0) : mix(b2, b3, k * 2.0 - 1.0);
		vec3 col = mix(ca, cb, flavor);
		col *= 0.85 + 0.25 * shim;
		col.rb += vec2(0.06, -0.06) * (shim - 0.5);
		float a = clamp(dye * band * density, 0.0, 1.0) * ALPHA_CAP;
		COLOR = vec4(col, a);
	}
}
