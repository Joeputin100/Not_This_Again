shader_type canvas_item;
// Fluid fog pass 1: advect velocity, subtract last frame's pressure gradient,
// inject splat forces. Velocity stored 0.5-centered in RG (RGBA8-safe).

uniform sampler2D vel_tex;
uniform sampler2D pressure_tex;
uniform float dt = 0.016;
uniform float dissipation = 0.992;
uniform vec2 texel = vec2(1.0 / 192.0, 1.0 / 108.0);
uniform int n_splats = 0;
uniform vec2 splat_pos[16];
uniform vec2 splat_vel[16];
uniform float splat_radius[16];
uniform float splat_dye[16];

const float VMAX = 1.0;     // max |v| in UV/sec the encode can carry
const float PGRAD = 1.0;    // pressure-gradient strength

vec2 dec(vec4 c) { return (c.rg - 0.5) * 2.0 * VMAX; }
vec4 enc(vec2 v) { return vec4(clamp(v / (2.0 * VMAX) + 0.5, 0.0, 1.0), 0.0, 1.0); }

void fragment() {
	vec2 v = dec(texture(vel_tex, UV));
	vec2 prev = clamp(UV - v * dt, texel, vec2(1.0) - texel);
	v = dec(texture(vel_tex, prev)) * dissipation;
	// subtract pressure gradient (one frame stale — temporal amortization)
	float L = texture(pressure_tex, UV - vec2(texel.x, 0.0)).r - 0.5;
	float R = texture(pressure_tex, UV + vec2(texel.x, 0.0)).r - 0.5;
	float B = texture(pressure_tex, UV - vec2(0.0, texel.y)).r - 0.5;
	float T = texture(pressure_tex, UV + vec2(0.0, texel.y)).r - 0.5;
	v -= vec2(R - L, T - B) * 0.5 * PGRAD;
	for (int i = 0; i < 16; i++) {
		if (i >= n_splats) { break; }
		vec2 d = UV - splat_pos[i];
		d.x *= texel.y / texel.x;   // aspect-correct round splats
		float s = exp(-dot(d, d) / max(splat_radius[i] * splat_radius[i], 1e-5));
		v += splat_vel[i] * s;
	}
	COLOR = enc(v);
}
