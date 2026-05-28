shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D wink_tex : source_color, filter_linear_mipmap;
uniform float wink_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 corona_color : source_color = vec3(0.78, 0.85, 1.0);
uniform float corona_strength : hint_range(0.0, 2.0) = 0.70;
// Wide, gentle falloff for a dreamy "out-of-focus moon" glow: the halo
// starts inside the disc edge and fades all the way out to the quad
// corners. A second, even softer bloom term spreads the light further.
uniform float corona_inner : hint_range(0.3, 0.6) = 0.36;
uniform float corona_outer : hint_range(0.4, 0.9) = 0.78;
uniform float breath_speed : hint_range(0.0, 1.0) = 0.333;
uniform float corona_burst : hint_range(0.0, 3.0) = 0.0;

void fragment() {
	vec4 normal_tex = texture(albedo_tex, UV);
	vec4 wink = texture(wink_tex, UV);
	vec4 tex = mix(normal_tex, wink, wink_progress);
	vec3 disc_rgb = tex.rgb * tint;
	float disc_a = tex.a;

	float r = length(UV - vec2(0.5));
	float halo = smoothstep(corona_outer, corona_inner, r);
	// Extra-soft bloom: a gentle quadratic falloff over the whole quad,
	// blurring the moon's light into the night the way an out-of-focus
	// lens would.
	float bloom = pow(clamp(1.0 - r / 0.72, 0.0, 1.0), 2.0) * 0.5;
	float breath = 1.0 + sin(TIME * breath_speed * 2.0 * 3.14159) * 0.15;
	float corona = (halo + bloom) * (corona_strength * breath + corona_burst);
	corona *= 1.0 - disc_a;

	ALBEDO = disc_rgb + corona_color * corona;
	ALPHA = max(disc_a, clamp(corona, 0.0, 1.0) * 0.7);
}
