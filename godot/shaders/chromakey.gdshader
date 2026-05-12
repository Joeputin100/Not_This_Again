shader_type canvas_item;

// Chromakey shader for video clips with solid-color background.
// Default: green-screen (#00FF00) removal, matching Pete's source MP4s.
//
// Usage: attach as material on a VideoStreamPlayer (or any CanvasItem).
// Pixels close to `chroma_color` get alpha=0; pixels farther than
// `similarity + blend` get full alpha. The blend band smooths the
// edge so the keyed sprite doesn't have hard-cut green halos.
//
// Tune `similarity` looser (higher) if greens with motion blur are
// surviving as fringe; tune it tighter (lower) if the actual sprite
// has green-adjacent tones (red bandana on dark hair often has olive
// pixels that get keyed too aggressively).

uniform vec3 chroma_color : source_color = vec3(0.0, 1.0, 0.0);
uniform float similarity : hint_range(0.0, 1.0) = 0.22;
uniform float blend_amount : hint_range(0.0, 0.5) = 0.10;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float dist = distance(c.rgb, chroma_color);
	float alpha = smoothstep(similarity, similarity + blend_amount, dist);
	COLOR = vec4(c.rgb, c.a * alpha);
}
