shader_type canvas_item;

// Sour candy, baked to a sprite. PROTOTYPE — 3D marble fractal from guil's
// Shadertoy "Playing marble" (CC-BY-NC-SA, see memory
// project_candy_shader_licensing). The native green marbling reads as sour-
// apple. We drop the iChannel0 cubemap (background + reflection) for a
// transparent background and a procedural fresnel rim. The bake step then
// squashes the round render into an ovoid and dusts it with sugar.

uniform float bake_time : hint_range(0.0, 12.0) = 3.0;
uniform vec3 sour_tint : source_color = vec3(0.55, 1.0, 0.2);  // acid green

vec2 csqr(vec2 a) { return vec2(a.x * a.x - a.y * a.y, 2.0 * a.x * a.y); }

mat2 rot(float a) { return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))); }

vec2 iSphere(vec3 ro, vec3 rd, vec4 sph) {
	vec3 oc = ro - sph.xyz;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - sph.w * sph.w;
	float h = b * b - c;
	if (h < 0.0) return vec2(-1.0);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

float map(vec3 p) {
	float res = 0.0;
	vec3 c = p;
	for (int i = 0; i < 10; ++i) {
		p = 0.7 * abs(p) / dot(p, p) - 0.7;
		p.yz = csqr(p.yz);
		p = p.zxy;
		res += exp(-19.0 * abs(dot(p, c)));
	}
	return res / 2.0;
}

vec3 raymarch(vec3 ro, vec3 rd, vec2 tminmax) {
	float t = tminmax.x;
	float dt = 0.02;
	vec3 col = vec3(0.0);
	float c = 0.0;
	for (int i = 0; i < 64; i++) {
		t += dt * exp(-2.0 * c);
		if (t > tminmax.y) break;
		c = map(ro + t * rd);
		col = 0.99 * col + 0.08 * vec3(c * c, c, c * c * c);  // green marble
	}
	return col;
}

void fragment() {
	vec2 pp = (UV - vec2(0.5)) * 2.0;
	pp.y = -pp.y;
	float time = bake_time;

	vec3 ro = vec3(4.0);
	ro.xz *= rot(0.1 * time);
	vec3 ww = normalize(vec3(0.0) - ro);
	vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
	vec3 vv = normalize(cross(uu, ww));
	vec3 rd = normalize(pp.x * uu + pp.y * vv + 4.0 * ww);

	vec2 tmm = iSphere(ro, rd, vec4(0.0, 0.0, 0.0, 2.0));
	if (tmm.x < 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 col = raymarch(ro, rd, tmm);
		// Fresnel rim instead of the cubemap reflection.
		vec3 nor = normalize((ro + tmm.x * rd) / 2.0);
		float fre = pow(0.5 + clamp(dot(reflect(rd, nor), rd), 0.0, 1.0), 3.0) * 1.3;
		col += sour_tint * fre * 0.4;
		col = 0.5 * log(1.0 + col);
		col = clamp(col, 0.0, 1.0);
		// Bias toward acid-green so it reads as sour.
		col = mix(col, col * sour_tint * 1.8, 0.5);
		COLOR = vec4(col, 1.0);
	}
}
