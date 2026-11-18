// Frozen: ice crystals over a portrait (a minion's oval, a hero's arch). The crystals spread in from the
// edge as `progress` grows (and melt back as it falls), with a frost rim and slow glints. One cheap pass
// over a small rect (nine cell lookups a pixel). The rect's colour: r = a seed, a = progress (0..1).
shader_type canvas_item;

uniform vec2 size = vec2(80.0, 100.0);  // the rect in pixels
uniform vec2 center = vec2(40.0, 50.0);  // the oval's centre (arch: the middle of its top)
uniform vec2 radii = vec2(36.0, 46.0);  // the oval's half size (arch: half width, the cap's height)
uniform vec4 box = vec4(0.0);  // arch only: x0, y0, x1, y1 of the portrait
uniform float arch = 0.0;  // 1: a hero's arch, 0: an oval
uniform vec3 hole_a = vec3(0.0, 0.0, 0.0);  // stat gems left clear: x, y, radius (radius 0: none)
uniform vec3 hole_b = vec3(0.0, 0.0, 0.0);
uniform vec3 hole_c = vec3(0.0, 0.0, 0.0);
uniform float cell = 13.0;  // a crystal's size in pixels

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// How far inside the portrait a pixel is (px; negative outside).
float inside(vec2 px) {
	if (arch < 0.5) {
		vec2 q = (px - center) / radii;
		return (1.0 - length(q)) * min(radii.x, radii.y);
	}
	float cap = box.y + radii.y;
	float sides = min(min(px.x - box.x, box.z - px.x), box.w - px.y);
	if (px.y >= cap) {
		return sides;
	}
	vec2 q = (px - vec2(center.x, cap)) / radii;
	return min((1.0 - length(q)) * radii.y, box.w - px.y);
}

float hole(vec2 px, vec3 h) {
	return h.z > 0.0 ? smoothstep(h.z - 1.5, h.z + 1.0, distance(px, h.xy)) : 1.0;
}

void fragment() {
	float seed = COLOR.r * 53.0;
	float p = COLOR.a;
	vec2 px = UV * size;
	float d = inside(px);
	float depth = clamp(d / max(1.0, min(radii.x, radii.y)), 0.0, 1.0);  // 0 at the edge, 1 in the middle
	// crystals: the nearest two cell points (the border between them is a vein of frost)
	vec2 g = px / cell + seed;
	vec2 gi = floor(g);
	vec2 gf = fract(g);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 near = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash2(gi + o) - gf;
			float dd = dot(r, r);
			if (dd < d1) {
				d2 = d1;
				d1 = dd;
				near = gi + o;
			} else if (dd < d2) {
				d2 = dd;
			}
		}
	}
	float h = hash2(near + 7.3).x;
	float vein = 1.0 - smoothstep(0.02, 0.16, sqrt(d2) - sqrt(d1));
	// the frost grows in from the edge, crystal by crystal
	float front = p * 1.45 - depth - h * 0.3;
	float cover = smoothstep(0.0, 0.07, front);
	// facets: each crystal its own shade of icy blue, lit from the top left; thick frost at the edge, thin in the
	// middle (the portrait shows through), bright crystal borders
	vec2 tilt = hash2(near + 3.1) - 0.5;
	float lit = 0.5 + 0.5 * dot(normalize(tilt + vec2(0.001)), vec2(-0.7, -0.7));
	vec3 ice = mix(vec3(0.35, 0.62, 0.98), vec3(0.72, 0.88, 1.0), lit * 0.6 + (1.0 - depth) * 0.4);
	float alpha = (mix(0.42, 0.08, depth) + 0.06 * lit) * cover + vein * mix(0.5, 0.18, depth) * cover;
	// a frost rim just inside the edge
	float rim = (1.0 - smoothstep(0.0, 4.5, d)) * smoothstep(-1.0, 0.5, d) * smoothstep(0.0, 0.25, p);
	// glints: a slow light sweeping across, and a few crystals twinkling
	float sweep = pow(max(0.0, sin((px.x + px.y) * 0.045 - TIME * 1.1 + seed)), 28.0);
	float twinkle = step(0.86, h) * pow(0.5 + 0.5 * sin(TIME * (1.5 + h * 3.0) + h * 40.0), 8.0) * (1.0 - smoothstep(0.0, 0.25, sqrt(d1)));
	vec3 col = ice + vec3(0.2) * vein + vec3(1.0) * (sweep * 0.5 + twinkle);
	alpha = alpha + rim * 0.95 + (sweep * 0.35 + twinkle * 0.8) * cover;
	alpha *= smoothstep(-1.2, 0.3, d) * hole(px, hole_a) * hole(px, hole_b) * hole(px, hole_c);
	COLOR = vec4(mix(col, vec3(0.95, 0.99, 1.0), rim * 0.6), clamp(alpha, 0.0, 0.85));
}
