shader_type spatial;
// NOT unshaded: dropping unshaded so the material participates in the shadow
// pass — Godot 4's GL Compatibility & Mobile renderers skip shadow casting
// for unshaded materials. We get pre-shaded-art behaviour back via a custom
// light() function that ignores diffuse direction but applies shadow
// attenuation (so figures darken in someone else's shadow).
render_mode cull_disabled, depth_draw_opaque, depth_prepass_alpha;

// Atlas playback. The same shader serves singletons (Pete, Humbug) and
// MultiMesh crowds (cowboy, chicken, etc.) — set use_instance=1 for crowds
// so each instance reads its own start_time/phase/flip from INSTANCE_CUSTOM.
//
// Lighting model: figures are drawn as pre-shaded art, so we don't want
// directional Lambert re-shading them. The light() function below applies
// ATTENUATION only (which carries the shadow factor), tinted toward
// shadow_dim_color when shadowed. Casting works automatically because the
// fragment's discard fires in the depth/shadow pass.

uniform sampler2D atlas : source_color, filter_nearest;
uniform int cols = 10;
uniform int rows = 10;
uniform int frame_count = 96;
uniform float fps = 24.0;
uniform float start_time = 0.0;   // used when use_instance == 0
uniform float phase = 0.0;
uniform int use_instance = 0;     // 1 = read start/phase/flip from INSTANCE_CUSTOM
uniform float alpha_clip = 0.2;
uniform float shadow_dim : hint_range(0.0, 1.0) = 0.55;   // 0=black in shadow, 1=no dimming

varying float v_start;
varying float v_phase;
varying float v_flip;

void vertex() {
    v_start = use_instance == 1 ? INSTANCE_CUSTOM.r : start_time;
    v_phase = use_instance == 1 ? INSTANCE_CUSTOM.g : phase;
    v_flip  = use_instance == 1 ? INSTANCE_CUSTOM.b : 0.0;
    // Y-axis billboard: face the camera, stay upright.
    mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
    mv[0] = vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0);
    mv[1] = vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0);
    mv[2] = vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0);
    POSITION = PROJECTION_MATRIX * mv * vec4(VERTEX, 1.0);
}

void fragment() {
    float t = TIME - v_start + v_phase * float(frame_count) / fps;
    int frame = int(floor(t * fps)) % frame_count;
    if (frame < 0) { frame += frame_count; }
    vec2 cell = vec2(float(frame % cols), float(frame / cols));
    vec2 fuv = UV;
    if (v_flip > 0.5) { fuv.x = 1.0 - fuv.x; }   // mirrored variations (chickens)
    vec2 uv = (fuv + cell) / vec2(float(cols), float(rows));
    vec4 c = texture(atlas, uv);
    if (c.a < alpha_clip) { discard; }
    ALBEDO = c.rgb;
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    ALPHA = 1.0;
}

void light() {
    // Preserve the pre-shaded paper-cutout look: ignore the Lambert dot
    // product and just modulate by ATTENUATION (1.0 fully lit, 0.0 in shadow).
    // shadow_dim controls the minimum brightness when fully shadowed.
    float f = mix(shadow_dim, 1.0, ATTENUATION);
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * f;
}
