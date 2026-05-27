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
// Back to alpha-blend after a Mobile-renderer regression: opaque rendering
// with depth_prepass_alpha was supposed to let transparent halos skip
// depth-writing, but on Mobile the halo still wrote depth, so overlapping
// quads punched holes through each other's figure bodies (Pete's torso
// disappeared behind another Pete's halo). blend_mix never writes depth
// for transparent pixels, so the holes go away. Trade-off: the alpha-blend
// sort isn't always camera-depth-correct, so close-by figures + grass can
// swap front/back during movement — a smaller visible bug than Pete's
// transparent torso.
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

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
uniform float shadow_dim : hint_range(0.0, 1.0) = 0.55;   // unused; kept for compatibility

// "Milling" drift — per-instance sinusoidal world-space offset so an idle
// crowd jostles around instead of standing perfectly still. Phase comes
// from INSTANCE_CUSTOM.r (start_time), which is randomised per member when
// FlipbookCrowd adds them, so all members drift on independent rhythms.
// Set mill_amp=0 to disable.
uniform float mill_amp : hint_range(0.0, 2.0) = 0.0;
uniform float mill_freq : hint_range(0.0, 5.0) = 0.4;

varying float v_start;
varying float v_phase;
varying float v_flip;

void vertex() {
    v_start = use_instance == 1 ? INSTANCE_CUSTOM.r : start_time;
    v_phase = use_instance == 1 ? INSTANCE_CUSTOM.g : phase;
    v_flip  = use_instance == 1 ? INSTANCE_CUSTOM.b : 0.0;

    // Per-instance milling drift in world space. Each instance jostles
    // around its spawn position on independent x/z sinusoids; phase from
    // its own start_time so the whole crowd doesn't sway in unison.
    float mp = v_start * 6.28318;
    vec3 mill = vec3(
        sin(TIME * mill_freq + mp),
        0.0,
        sin(TIME * mill_freq * 0.7 + mp + 1.5)
    ) * mill_amp;

    // Y-axis billboard: face the camera, stay upright. Apply mill to the
    // world position before billboarding so the offset is in WORLD space
    // (not view space), keeping motion grounded as the camera moves.
    vec3 world_pos = MODEL_MATRIX[3].xyz + mill;
    mat4 mv = VIEW_MATRIX;
    mv[3] = VIEW_MATRIX * vec4(world_pos, 1.0);
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
    ALPHA = c.a;   // pass-through alpha so blend_mix doesn't fight the discard
}
