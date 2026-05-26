shader_type spatial;
// `unshaded` (back from a brief attempt to use a custom light() for shadow
// tinting — that produced "Pete's white shirt invisible" artifacts on the
// Mobile renderer, best guess being NaN ATTENUATION or platform-specific
// clamping inside the custom light() path. Reverted to plain unshaded so
// the texture renders exactly as drawn.)
//
// `depth_prepass_alpha` REQUIRED: without it, the depth pre-pass uses a
// simpler shader that doesn't run discard, so the depth buffer treats the
// entire quad rectangle as solid. Behind-quad fragments then get Z-rejected
// even where the quad is transparent, causing other crowd members + grass
// tufts to render with figure-quad-shaped holes punched through them.
// Forward+ renderer is lenient; Mobile renderer is strict.
//
// Shadow casting from these figures is not supported by `unshaded`. The
// shadow-casting feature target uses blob-shadow planes (separate
// implementation) so the figure outline still casts a directional shadow
// without forcing the figure shader to participate in lighting.
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_prepass_alpha;

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
    ALPHA = 1.0;
}
