shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 corona_color : source_color = vec3(1.0, 0.85, 0.55);
uniform float corona_strength : hint_range(0.0, 2.0) = 0.65;
uniform float corona_inner : hint_range(0.3, 0.6) = 0.42;
uniform float corona_outer : hint_range(0.4, 0.8) = 0.58;
uniform float breath_speed : hint_range(0.0, 1.0) = 0.333;
uniform float corona_burst : hint_range(0.0, 3.0) = 0.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 disc_rgb = tex.rgb * tint;
	float disc_a = tex.a;

	float r = length(UV - vec2(0.5));
	float halo = smoothstep(corona_outer, corona_inner, r);
	float breath = 1.0 + sin(TIME * breath_speed * 2.0 * 3.14159) * 0.15;
	float corona = halo * (corona_strength * breath + corona_burst);
	corona *= 1.0 - disc_a;

	ALBEDO = disc_rgb + corona_color * corona;
	ALPHA = max(disc_a, corona * 0.7);
}
