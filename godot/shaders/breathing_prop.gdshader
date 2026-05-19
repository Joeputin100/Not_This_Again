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

// Iter 132: glitz layer — emission pulse / hue cycle / rotation / halo.
//   pulse_glow      — emission amplitude on a sin(TIME*4) wave
//   hue_cycle       — slow color rotation amount (0..1)
//   halo_strength   — additive bright fringe behind silhouette
//   sparkle_orbit   — texture-coordinate noise glitter intensity
//   rotation_mode   — 0=none (keeps Y-billboard), 1=UV-spin (texture spins
//                     in place but billboard frame is static), 2=Y-spin
//                     (sprite physically rotates around vertical axis,
//                     billboard disabled, flashes edge-on each half-rotation)
//   rotation_speed  — rotations per second baseline
uniform float pulse_glow : hint_range(0.0, 2.0) = 0.0;
uniform float hue_cycle : hint_range(0.0, 1.0) = 0.0;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.0;
uniform float sparkle_orbit : hint_range(0.0, 1.0) = 0.0;
uniform int rotation_mode : hint_range(0, 2) = 0;
uniform float rotation_speed : hint_range(0.0, 5.0) = 1.0;

void vertex() {
	// Iter 132: rotation_mode 2 (Y-SPIN) disables billboard — the plane
	// physically rotates around its vertical axis. Edge-on every half
	// rotation gives the "paper sign spinning in wind" effect.
	vec3 obj_pos = MODEL_MATRIX[3].xyz;
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	if (rotation_mode == 2) {
		float ang = TIME * rotation_speed * 6.2831853;
		mat3 spin_rot = mat3(
			vec3(cos(ang), 0.0, sin(ang)),
			vec3(0.0, 1.0, 0.0),
			vec3(-sin(ang), 0.0, cos(ang)));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(spin_rot[0] * scale.x, 0.0),
			vec4(spin_rot[1] * scale.y, 0.0),
			vec4(spin_rot[2] * scale.z, 0.0),
			vec4(obj_pos, 1.0));
	} else {
		// Y-axis billboard: face camera around vertical axis only.
		vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
		vec3 to_cam = cam_pos - obj_pos;
		to_cam.y = 0.0;
		if (length(to_cam) < 0.001) { to_cam = vec3(0, 0, 1); }
		to_cam = normalize(to_cam);
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 right = normalize(cross(up, to_cam));
		mat3 billboard_rot = mat3(right, up, to_cam);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(billboard_rot[0] * scale.x, 0.0),
			vec4(billboard_rot[1] * scale.y, 0.0),
			vec4(billboard_rot[2] * scale.z, 0.0),
			vec4(obj_pos, 1.0));
	}

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
	// Iter 132: UV-spin (rotation_mode 1) rotates texture coordinates
	// around (0.5, 0.5) — texture spins inside the static billboard frame.
	vec2 uv = UV;
	if (rotation_mode == 1) {
		float ang = TIME * rotation_speed * 6.2831853;
		vec2 c = vec2(0.5);
		vec2 d = uv - c;
		uv = c + vec2(d.x * cos(ang) - d.y * sin(ang),
		              d.x * sin(ang) + d.y * cos(ang));
		// Iter 142: discard pixels outside [0,1] to prevent texture-repeat
		// "wraparound tile" artifact at rotated corners (user reported
		// "uvspin shows weird artifacts").
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			discard;
		}
	}
	vec4 tex = texture(albedo_tex, uv) * modulate;
	// Iter 144: outward halo — transparent pixels NEAR opaque pixels render
	// halo color instead of being discarded. Creates the glow-OUTSIDE-the-
	// silhouette effect the user has been asking about. Sampling 8 directions
	// at k=0.05 in UV space gives a halo band ~5% of texture wide.
	if (tex.a < alpha_cutoff && halo_strength > 0.001) {
		float k_outer = 0.05;
		float max_neighbor = 0.0;
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2(0.0,    -k_outer)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2(0.0,     k_outer)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2( k_outer, 0.0)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2(-k_outer, 0.0)).a);
		float k_diag = k_outer * 0.707;
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2( k_diag,  k_diag)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2(-k_diag,  k_diag)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2( k_diag, -k_diag)).a);
		max_neighbor = max(max_neighbor, texture(albedo_tex, uv + vec2(-k_diag, -k_diag)).a);
		if (max_neighbor >= alpha_cutoff) {
			float pulse = 0.7 + sin(TIME * 3.0) * 0.3;
			ALBEDO = vec3(1.0, 0.85, 0.40);
			ALPHA = halo_strength * max_neighbor * pulse * 0.85;
			return;
		}
		discard;
	}
	if (tex.a < alpha_cutoff) { discard; }
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	// damage tint: flash white on impact, decay with damage_strength
	if (damage_strength > 0.001) {
		ALBEDO = mix(ALBEDO, vec3(1.0, 1.0, 0.85), damage_strength * 0.6);
	}
	// Iter 132/135: glitz layers — add to ALBEDO directly since the
	// `unshaded` render_mode ignores EMISSION. iter 132 used EMISSION
	// which silently dropped these effects.
	if (pulse_glow > 0.001) {
		float pulse = sin(TIME * 4.0) * 0.5 + 0.5;
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.95, 0.50), pulse * pulse_glow * 0.35);
	}
	if (hue_cycle > 0.001) {
		// Cheap "hue cycle": cyclic permutation of RGB channels at low amplitude
		vec3 cycled = mix(ALBEDO.rgb, ALBEDO.brg, sin(TIME * 1.5) * 0.5 + 0.5);
		cycled = mix(cycled, cycled.gbr, sin(TIME * 1.5 + 2.094) * 0.3);
		ALBEDO = mix(ALBEDO, cycled, hue_cycle);
	}
	// Iter 144: halo is handled BEFORE the discard above (outward glow on
	// transparent pixels near opaque ones). No inner-rim work here.
	if (sparkle_orbit > 0.001) {
		// Iter 144: cranked further — threshold 0.97 → 0.90 (10% pixels
		// active), pulse magnitude 0.3 → 0.5, double-band noise for more
		// "twinkle scatter" feel. User reported sparkle "barely noticeable".
		float n1 = fract(sin(dot(uv * 40.0, vec2(12.9898, 78.233)) + TIME * 5.0) * 43758.5453);
		float n2 = fract(sin(dot(uv * 25.0, vec2(8.9, 24.7)) + TIME * 3.0) * 33458.5453);
		float glitter = max(step(0.90, n1), step(0.93, n2)) * (0.5 + sin(TIME * 8.0) * 0.5);
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.92, 0.55), clamp(glitter * sparkle_orbit, 0.0, 1.0));
	}
}
