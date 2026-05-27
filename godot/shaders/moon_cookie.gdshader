shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 cookie_color_cream : source_color = vec3(0.96, 0.90, 0.78);
uniform vec3 cookie_color_speckle : source_color = vec3(0.62, 0.48, 0.30);
uniform vec3 glow_amber : source_color = vec3(0.88, 0.69, 0.44);
uniform float bite_depth : hint_range(0.0, 1.0) = 0.4;
uniform vec2 bite_dir = vec2(0.7, 0.7);
uniform float breath_speed : hint_range(0.0, 1.0) = 0.333;
uniform float speckle_density : hint_range(0.0, 50.0) = 12.0;
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.2;

uniform vec3 face_color : source_color = vec3(0.62, 0.48, 0.30);
uniform vec2 face_eye_left_uv = vec2(0.38, 0.50);
uniform vec2 face_eye_right_uv = vec2(0.56, 0.50);
uniform float face_eye_half_height : hint_range(0.001, 0.04) = 0.008;
uniform float face_eye_half_width : hint_range(0.0, 0.1) = 0.04;
uniform float face_smile_y : hint_range(0.3, 0.7) = 0.62;
uniform float face_smile_width : hint_range(0.0, 0.5) = 0.12;
uniform float face_smile_thickness : hint_range(0.001, 0.05) = 0.010;
uniform float blink_period_sec : hint_range(1.0, 30.0) = 8.0;
uniform float blink_duration_sec : hint_range(0.05, 0.5) = 0.15;
uniform float wink_override : hint_range(0.0, 1.0) = 0.0;

const float DISC_RADIUS = 0.48;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float r = length(uv);
    if (r > DISC_RADIUS) {
        discard;
    }

    vec2 bn = normalize(bite_dir);
    vec2 bite_center = bn * (DISC_RADIUS + DISC_RADIUS * (1.0 - bite_depth));
    if (length(uv - bite_center) < DISC_RADIUS) {
        discard;
    }

    float n = hash21(floor(UV * speckle_density));
    vec3 base = mix(cookie_color_cream, cookie_color_speckle, n * speckle_strength);

    float breath = 0.15 + 0.075 * sin(TIME * breath_speed * 2.0 * 3.14159);
    vec3 col = mix(base, glow_amber, breath);

    float blink_phase = mod(TIME, blink_period_sec) / blink_duration_sec;
    float blink = clamp(abs(blink_phase - 0.5) * 2.0, 0.1, 1.0);

    float left_open = mix(blink, 0.05, wink_override);
    vec2 d_left = (UV - face_eye_left_uv) / vec2(face_eye_half_width, face_eye_half_height * left_open);
    float eye_left = smoothstep(1.05, 0.95, length(d_left));
    vec2 d_right = (UV - face_eye_right_uv) / vec2(face_eye_half_width, face_eye_half_height * blink);
    float eye_right = smoothstep(1.05, 0.95, length(d_right));
    float smile_x = UV.x - 0.5;
    float smile_y_target = face_smile_y - 0.15 * 4.0 * smile_x * smile_x;
    float smile_dist = abs(UV.y - smile_y_target);
    float smile = smoothstep(face_smile_thickness, face_smile_thickness * 0.4, smile_dist);
    smile *= smoothstep(face_smile_width, face_smile_width * 0.7, abs(smile_x));

    float face_mask = clamp(eye_left + eye_right + smile, 0.0, 1.0);
    col = mix(col, face_color, face_mask);

    ALBEDO = col;
    ALPHA = smoothstep(DISC_RADIUS, DISC_RADIUS - 0.005, r);
}
