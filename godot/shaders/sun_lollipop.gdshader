shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

// Sun disc: just the Imagen candy art, tinted per lighting preset. The
// glow/corona is a separate additive layer (sun_corona_star.gdshader)
// drawn behind this disc.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint;
	ALPHA = tex.a;
}
