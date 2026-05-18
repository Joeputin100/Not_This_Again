shader_type spatial;

// Iter 130: paper-cutout breathing shader for static props.
//
// Designed for MeshInstance3D + PlaneMesh (subdivided ≥4×6) since vertex
// displacement needs more than a 4-vert quad to read as wave motion.
//
// The shader handles:
//   - Y-axis billboard so the prop always faces the camera but stays
//     upright (rooted at y=0 in local space).
//   - Top-weighted sway: bottom of the sprite (rooted at the ground)
//     stays still while the top wobbles in the wind. Gives a "paper
//     sign on a stick" feel.
//   - Subtle breathing pulse (uniform scale on a sine wave).
//   - Crumple-on-damage: temporary high-frequency crinkle + downward
//     compression toward the impact point. Tween damage_strength 1.0→0.0
//     over ~0.4s on hit.
//   - Bonk squash: vertical compression for collision recoil. Tween
//     bonk_squash 1.0 → 0.6 → 1.0 on impact.
//
// All effects compose additively — breathing keeps running during a
// damage pulse. Lighting baked into the texture stays in UV space, so
// highlights don't rotate with the wobble (the trick that makes the
// motion feel "alive" rather than "rigid sprite swinging").

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, unshaded;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.40;

// Breathing motion — tune per prop type via set_shader_parameter.
// Cactus: low sway (rigid), low bob.   sway=0.04 bob=0.015
// Fence:  moderate sway, no bob.       sway=0.06 bob=0.0
// Scrub:  high sway (flexible), high bob. sway=0.10 bob=0.025
// Building: ~zero sway, tiny bob.      sway=0.005 bob=0.005
uniform float sway_amp : hint_range(0.0, 0.5) = 0.06;
uniform float sway_freq : hint_range(0.1, 5.0) = 1.5;
uniform float bob_amp : hint_range(0.0, 0.10) = 0.015;
uniform float bob_freq : hint_range(0.1, 5.0) = 2.2;

// Per-instance offset prevents all props of one type from swaying in
// unison (which reads as artificial). Set to a random value per spawn.
uniform float time_offset : hint_range(0.0, 6.283185) = 0.0;

// Damage / bonk effects (pulse via tween)
uniform float damage_strength : hint_range(0.0, 1.0) = 0.0;
uniform float bonk_squash : hint_range(0.5, 1.5) = 1.0;

void vertex() {
	// Y-axis billboard: face camera around vertical axis only. Keeps the
	// prop's "up" pointing world-up so sway reads correctly.
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 obj_pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = cam_pos - obj_pos;
	to_cam.y = 0.0;
	if (length(to_cam) < 0.001) { to_cam = vec3(0, 0, 1); }
	to_cam = normalize(to_cam);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, to_cam));
	mat3 billboard_rot = mat3(right, up, to_cam);
	// Preserve original mesh scale
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(billboard_rot[0] * scale.x, 0.0),
		vec4(billboard_rot[1] * scale.y, 0.0),
		vec4(billboard_rot[2] * scale.z, 0.0),
		vec4(obj_pos, 1.0));

	float t = TIME + time_offset;

	// Sway: top of mesh leans, bottom is anchored.
	// PlaneMesh defaults the origin at center, so we shift the weight
	// function so bottom (VERTEX.y = -0.5 × height in local) = 0 weight
	// and top (= +0.5) = 1.0 weight.
	float height_weight = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	VERTEX.x += sin(t * sway_freq) * sway_amp * height_weight;
	VERTEX.z += cos(t * sway_freq * 1.3) * sway_amp * 0.4 * height_weight;

	// Breathing: subtle full-mesh pulse
	VERTEX.xyz *= 1.0 + sin(t * bob_freq) * bob_amp;

	// Crumple on damage: high-freq crinkle + downward compression
	if (damage_strength > 0.001) {
		float crinkle = sin(VERTEX.y * 30.0 + t * 25.0) * cos(VERTEX.x * 25.0);
		VERTEX.x += crinkle * damage_strength * 0.05;
		VERTEX.z += crinkle * damage_strength * 0.05;
		VERTEX.y -= damage_strength * 0.15 * height_weight;
	}

	// Bonk squash: vertical compress for collision recoil
	VERTEX.y *= bonk_squash;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * modulate;
	if (tex.a < alpha_cutoff) { discard; }
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	// damage tint: flash white on impact, decay with damage_strength
	if (damage_strength > 0.001) {
		ALBEDO = mix(ALBEDO, vec3(1.0, 1.0, 0.85), damage_strength * 0.6);
	}
}
