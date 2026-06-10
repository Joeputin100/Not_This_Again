shader_type canvas_item;
// Fluid fog pass 4: advect the pink + dye splats + dissipation.
// R = dye amount, G = flavor·amount (cool<->warm pink family, swirls with
// the fluid — the owner-approved cotton-candy marbling).
uniform sampler2D dye_tex;
uniform sampler2D vel_tex;
uniform float dt = 0.016;
uniform float dissipation = 0.985;
uniform vec2 texel = vec2(1.0 / 192.0, 1.0 / 108.0);
uniform int n_splats = 0;
uniform vec2 splat_pos[16];
uniform vec2 splat_vel[16];
uniform float splat_radius[16];
uniform float splat_dye[16];
uniform float splat_flavor[16];
const float VMAX = 1.0;
vec2 dec(vec4 c) { return (c.rg - 0.5) * 2.0 * VMAX; }
void fragment() {
	vec2 v = dec(texture(vel_tex, UV));
	vec2 prev = clamp(UV - v * dt, texel, vec2(1.0) - texel);
	vec2 dye = texture(dye_tex, prev).rg * dissipation;
	for (int i = 0; i < 16; i++) {
		if (i >= n_splats) { break; }
		vec2 d = UV - splat_pos[i];
		d.x *= texel.y / texel.x;
		float s = exp(-dot(d, d) / max(splat_radius[i] * splat_radius[i], 1e-5));
		dye.r += splat_dye[i] * s;
		dye.g += splat_dye[i] * splat_flavor[i] * s;
	}
	COLOR = vec4(clamp(dye, vec2(0.0), vec2(1.0)), 0.0, 1.0);
}
