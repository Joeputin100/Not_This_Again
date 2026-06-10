shader_type canvas_item;
// Fluid fog pass 3: ONE Jacobi pressure iteration per frame (converges
// across frames — fog tolerates the slight compressibility).
uniform sampler2D pressure_tex;
uniform sampler2D div_tex;
uniform vec2 texel = vec2(1.0 / 192.0, 1.0 / 108.0);
void fragment() {
	float L = texture(pressure_tex, UV - vec2(texel.x, 0.0)).r - 0.5;
	float R = texture(pressure_tex, UV + vec2(texel.x, 0.0)).r - 0.5;
	float B = texture(pressure_tex, UV - vec2(0.0, texel.y)).r - 0.5;
	float T = texture(pressure_tex, UV + vec2(0.0, texel.y)).r - 0.5;
	float div = (texture(div_tex, UV).r - 0.5) * 2.0;
	float p = (L + R + T + B - div) * 0.25;
	COLOR = vec4(clamp(p + 0.5, 0.0, 1.0), 0.0, 0.0, 1.0);
}
