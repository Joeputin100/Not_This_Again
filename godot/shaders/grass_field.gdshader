shader_type spatial;

// Grass-field shader for a MultiMesh of billboarded grass-tuft sprites.
// Single-tuft sway lifted from breathing_prop.gdshader (top-weighted x/z
// sway + tiny scale bob) — stripped of the damage/halo/glitz/puppet code
// so the per-instance work stays cheap when there are hundreds of tufts.
//
// Per-instance phase comes from MultiMesh.set_instance_custom_data — the
// red channel is reinterpreted as a 0..2π time offset. Without that
// offset, every tuft would sway in lock-step, which reads as artificial.
// Bottom of each quad stays planted (top sways) so the field looks like
// grass anchored to the ground, not floating cards.
//
// NOT unshaded so the material participates in shadow casting + receiving.
// Like flipbook.gdshader, the light() function preserves the pre-shaded
// look (no Lambert dot product) and just applies ATTENUATION/shadow tint.

render_mode blend_mix, depth_draw_opaque, cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.30;
uniform float sway_amp : hint_range(0.0, 0.5) = 0.10;
uniform float sway_freq : hint_range(0.1, 5.0) = 1.5;
uniform float bob_amp : hint_range(0.0, 0.10) = 0.020;
uniform float bob_freq : hint_range(0.1, 5.0) = 2.2;
uniform float mesh_height : hint_range(0.1, 5.0) = 0.7;
uniform float shadow_dim : hint_range(0.0, 1.0) = 0.55;

void vertex() {
	// MultiMesh.instance_custom_data.r in [0,1] -> phase offset 0..2π.
	float t_off = INSTANCE_CUSTOM.r * 6.2831853;
	float t = TIME + t_off;

	// Y-axis billboard — face the camera around the vertical axis only
	// so each tuft stays upright. Preserve per-instance scale so the
	// field can vary tuft size.
	vec3 obj_pos = MODEL_MATRIX[3].xyz;
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam_pos - obj_pos;
	to_cam.y = 0.0;
	if (length(to_cam) < 0.001) { to_cam = vec3(0.0, 0.0, 1.0); }
	to_cam = normalize(to_cam);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, to_cam));
	mat3 billboard_rot = mat3(right, up, to_cam);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(billboard_rot[0] * scale.x, 0.0),
		vec4(billboard_rot[1] * scale.y, 0.0),
		vec4(billboard_rot[2] * scale.z, 0.0),
		vec4(obj_pos, 1.0));

	// Top-weighted sway: 0 at the mesh's true bottom, 1 at the top.
	// PlaneMesh is centered, so VERTEX.y spans -mesh_height/2..+mesh_height/2.
	float height_weight = clamp((VERTEX.y + mesh_height * 0.5) / mesh_height, 0.0, 1.0);
	VERTEX.x += sin(t * sway_freq) * sway_amp * height_weight;
	VERTEX.z += cos(t * sway_freq * 1.3) * sway_amp * 0.4 * height_weight;
	VERTEX.xyz *= 1.0 + sin(t * bob_freq) * bob_amp;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * modulate;
	if (tex.a < alpha_cutoff) { discard; }
	ALBEDO = tex.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = 1.0;
}

void light() {
	// Same pattern as flipbook.gdshader — preserve pre-shaded art, only
	// modulate by ATTENUATION (shadow factor).
	float f = mix(shadow_dim, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * f;
}
