shader_type canvas_item;
// Fluid fog pass 2: divergence of velocity (0.5-centered R output).
uniform sampler2D vel_tex;
uniform vec2 texel = vec2(1.0 / 192.0, 1.0 / 108.0);
const float VMAX = 1.0;
vec2 dec(vec4 c) { return (c.rg - 0.5) * 2.0 * VMAX; }
void fragment() {
	float L = dec(texture(vel_tex, UV - vec2(texel.x, 0.0))).x;
	float R = dec(texture(vel_tex, UV + vec2(texel.x, 0.0))).x;
	float B = dec(texture(vel_tex, UV - vec2(0.0, texel.y))).y;
	float T = dec(texture(vel_tex, UV + vec2(0.0, texel.y))).y;
	float div = (R - L + T - B) * 0.5;
	COLOR = vec4(clamp(div * 0.5 + 0.5, 0.0, 1.0), 0.0, 0.0, 1.0);
}
