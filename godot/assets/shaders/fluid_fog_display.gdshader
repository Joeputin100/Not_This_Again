shader_type canvas_item;
// Fluid fog display: composite the dye field as a wispy pink ground-fog band
// over the 3D scene. Full-rect ColorRect under the HUD; the sim maps to the
// lower band of the screen. Alpha capped — entities stay readable (spec).

uniform sampler2D dye_tex;
uniform float density = 0.5;      // FluidFog.density(distance, boss_frac)
uniform float band_top = 0.52;    // screen-UV where the fog band begins
const float ALPHA_CAP = 0.55;

void fragment() {
	if (UV.y < band_top) {
		COLOR = vec4(0.0);
	} else {
		vec2 sim_uv = vec2(UV.x, (UV.y - band_top) / (1.0 - band_top));
		float dye = texture(dye_tex, sim_uv).r;
		// soft top edge so the band has no hard line
		float band = smoothstep(0.0, 0.35, sim_uv.y);
		// cotton-candy palette: lit pale-rose tops -> deeper magenta in the thick
		vec3 pale = vec3(1.0, 0.86, 0.93);
		vec3 deep = vec3(0.95, 0.55, 0.78);
		vec3 col = mix(pale, deep, clamp(dye * 1.4, 0.0, 1.0));
		float a = clamp(dye * band * density, 0.0, 1.0) * ALPHA_CAP;
		COLOR = vec4(col, a);
	}
}
