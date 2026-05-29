shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D wink_tex : source_color, filter_linear_mipmap;
uniform float wink_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 corona_color : source_color = vec3(0.78, 0.85, 1.0);
uniform float corona_strength : hint_range(0.0, 2.0) = 0.70;
// Dreamy "out-of-focus moon" glow. The halo + bloom MUST fade to zero before
// the quad's inscribed-circle radius (UV r = 0.5), otherwise the round glow
// gets clipped by the square quad edges and shows as a rectangle (iter 331).
uniform float corona_inner : hint_range(0.3, 0.6) = 0.36;
uniform float corona_outer : hint_range(0.4, 0.5) = 0.48;
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
	// Extra-soft bloom, but contained within the inscribed circle (/0.5 so it
	// reaches 0 at r=0.5) — blurs the moon's light like an out-of-focus lens
	// without spilling to the square quad edge.
	float bloom = pow(clamp(1.0 - r / 0.5, 0.0, 1.0), 2.0) * 0.5;
	float breath = 1.0 + sin(TIME * breath_speed * 2.0 * 3.14159) * 0.15;
	float corona = (halo + bloom) * (corona_strength * breath + corona_burst);
	corona *= 1.0 - disc_a;
	// Hard guarantee the glow is fully gone by the quad edge → circular, never
	// a rectangle, regardless of corona_strength/burst.
	corona *= smoothstep(0.5, 0.44, r);

	ALBEDO = disc_rgb + corona_color * corona;
	ALPHA = max(disc_a, clamp(corona, 0.0, 1.0) * 0.7);
}
