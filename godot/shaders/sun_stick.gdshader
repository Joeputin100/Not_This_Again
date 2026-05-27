shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 stick_color_base : source_color = vec3(0.78, 0.56, 0.28);
uniform vec3 stick_color_tip : source_color = vec3(0.96, 0.86, 0.65);
uniform float highlight_speed : hint_range(0.0, 1.0) = 0.25;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec3 col = mix(stick_color_tip, stick_color_base, UV.y);

    float center = 0.5 + sin(TIME * highlight_speed * 2.0 * 3.14159) * 0.08;
    float dist = abs(UV.x - center);
    float highlight = smoothstep(0.07, 0.0, dist) * highlight_strength;
    col += vec3(1.0, 0.95, 0.85) * highlight * (1.0 - UV.y * 0.5);

    ALBEDO = col;
    ALPHA = 1.0;
}
