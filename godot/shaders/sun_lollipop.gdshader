shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 swirl_color_a : source_color = vec3(0.96, 0.78, 0.42);
uniform vec3 swirl_color_b : source_color = vec3(0.90, 0.64, 0.23);
uniform float rotation_speed : hint_range(0.0, 1.0) = 0.087;
uniform float spin_boost : hint_range(1.0, 8.0) = 1.0;
uniform int swirl_wedges : hint_range(2, 12) = 6;

uniform float shimmer_speed : hint_range(0.0, 1.0) = 0.286;
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.4;

uniform vec3 face_color : source_color = vec3(0.30, 0.18, 0.06);
uniform vec2 face_eye_left_uv = vec2(0.40, 0.43);
uniform vec2 face_eye_right_uv = vec2(0.60, 0.43);
uniform float face_eye_radius : hint_range(0.0, 0.1) = 0.035;
uniform float face_smile_y : hint_range(0.3, 0.7) = 0.60;
uniform float face_smile_width : hint_range(0.0, 0.5) = 0.18;
uniform float face_smile_thickness : hint_range(0.001, 0.05) = 0.012;
uniform float face_smile_curve : hint_range(0.0, 1.0) = 0.40;
uniform float blink_period_sec : hint_range(1.0, 30.0) = 6.0;
uniform float blink_duration_sec : hint_range(0.05, 0.5) = 0.12;

const float DISC_RADIUS = 0.48;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float r = length(uv);
    if (r > DISC_RADIUS) {
        discard;
    }

    float ang = atan(uv.y, uv.x) + TIME * rotation_speed * spin_boost;
    float wedge_f = ang * float(swirl_wedges) / PI;
    float wedge = step(0.5, fract(wedge_f * 0.5));
    vec3 col = mix(swirl_color_a, swirl_color_b, wedge);

    float shimmer_pos = sin(TIME * shimmer_speed * 2.0 * PI) * 0.35;
    float shimmer = exp(-pow((uv.x - shimmer_pos) * 4.0, 2.0));
    col += vec3(1.0, 0.95, 0.85) * shimmer * shimmer_strength * smoothstep(DISC_RADIUS, 0.0, r);

    vec2 face_uv = UV;
    float blink_phase = mod(TIME, blink_period_sec) / blink_duration_sec;
    float blink = smoothstep(0.0, 1.0, abs(blink_phase - 0.5) * 2.0);
    blink = clamp(blink, 0.05, 1.0);
    vec2 d_left = (face_uv - face_eye_left_uv) / vec2(1.0, blink);
    float eye_left = smoothstep(face_eye_radius * 1.05, face_eye_radius * 0.95, length(d_left));
    vec2 d_right = (face_uv - face_eye_right_uv) / vec2(1.0, blink);
    float eye_right = smoothstep(face_eye_radius * 1.05, face_eye_radius * 0.95, length(d_right));
    float smile_x = face_uv.x - 0.5;
    float smile_y_target = face_smile_y - face_smile_curve * 4.0 * smile_x * smile_x;
    float smile_dist = abs(face_uv.y - smile_y_target);
    float smile = smoothstep(face_smile_thickness, face_smile_thickness * 0.4, smile_dist);
    smile *= smoothstep(face_smile_width, face_smile_width * 0.7, abs(smile_x));
    float face_mask = clamp(eye_left + eye_right + smile, 0.0, 1.0);
    col = mix(col, face_color, face_mask);

    ALBEDO = col;
    ALPHA = smoothstep(DISC_RADIUS, DISC_RADIUS - 0.005, r);
}
