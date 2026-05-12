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

// Iter 40c: kill near-black letterbox bars too. Every Veo-rendered clip
// (24 of them at time of writing) is 720×1280 with 280-pixel pure-black
// bars on top and bottom — the content lives in the middle 720×720
// square. Discarding pixels darker than this threshold removes the bars
// at render time without needing to re-encode 24 videos.
//
// Threshold = 0.04 is safe because:
//   - Pure-black letterbox: RGB(0,0,0) — discarded
//   - Pete's black cowboy hat: RGB ~(0.08, 0.07, 0.07) — survives
//   - Vagrant outlaw's dark vest: RGB ~(0.10, 0.07, 0.05) — survives
// Two videos (pete_celebrate, pete_death) have no letterbox and only
// figure content; this check is a no-op on them.
uniform float black_threshold : hint_range(0.0, 0.2) = 0.04;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float dist = distance(c.rgb, chroma_color);
	float alpha = smoothstep(similarity, similarity + blend_amount, dist);
	// Letterbox cut: if all three channels are below threshold, this is
	// near-pure-black background, not figure content — drop to alpha 0.
	float brightness = max(c.r, max(c.g, c.b));
	if (brightness < black_threshold) {
		alpha = 0.0;
	}
	COLOR = vec4(c.rgb, c.a * alpha);
}
