shader_type spatial;

// Blob-shadow shader: renders a soft dark oval on a flat PlaneMesh. Used
// by FlipbookCrowd as a fake shadow under each crowd member — works on
// any renderer (no shadow map required), supports configurable colour /
// softness / offset via the spawning script. The shadow's POSITION (and
// offset from the character) is set per-instance on the MultiMesh.

render_mode unshaded, depth_draw_opaque, cull_disabled, blend_mix, depth_test_disabled;
// `depth_test_disabled` so the shadow always draws on top of the grass
// plane without z-fighting at y=0.01.

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
uniform float softness : hint_range(0.0, 1.0) = 0.40;

void fragment() {
	// UV maps the plane 0..1 across; centre is (0.5, 0.5). Radius 1 at edge.
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	// 1.0 fully inside, 0.0 fully outside — soft falloff over `softness`
	// fraction of the radius.
	float a = smoothstep(1.0, 1.0 - softness, r);
	if (a < 0.01) { discard; }
	ALBEDO = shadow_color.rgb;
	ALPHA = a * shadow_color.a;
}
