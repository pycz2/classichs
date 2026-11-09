// Spell Damage on a minion: an arcane glow breathing around its portrait and sparkles
// twinkling as they drift up around it. Light only (added to what is under it); one cheap pass
// over a small rect. The rect's colour: r = a seed (each minion twinkles its own way), a = fade.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 size = vec2(128.0, 148.0);  // the rect in pixels
uniform vec2 center = vec2(64.0, 70.0);  // the portrait's centre in it
uniform vec2 radii = vec2(36.0, 46.0);  // the portrait's half size
uniform vec4 glow : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform vec4 spark : source_color = vec4(0.92, 0.82, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float seed = COLOR.r * 97.0;
	float fade = COLOR.a;
	vec2 px = UV * size;
	vec2 q = (px - center) / radii;  // 1.0 on the portrait's edge
	float r = length(q);
	float t = TIME + seed;
	// the glow: a soft band just outside the edge, swirling round and breathing
	float ang = atan(q.y, q.x);
	float swirl = 0.55 + 0.45 * sin(ang * 3.0 - t * 1.7) * sin(ang * 2.0 + t * 1.1);
	float rim = exp(-pow((r - 1.06) * 7.0, 2.0)) * swirl * (0.8 + 0.2 * sin(t * 2.3));
	float haze = (1.0 - smoothstep(1.05, 1.5, r)) * smoothstep(0.75, 1.05, r) * 0.22;
	// arcane mist: thin bright streaks winding along the inside of the edge
	float mist = smoothstep(0.72, 0.98, r) * (1.0 - smoothstep(0.98, 1.04, r))
		* pow(0.5 + 0.5 * sin(ang * 7.0 + r * 18.0 - t * 2.6), 6.0) * 0.55;
	vec3 hue = mix(glow.rgb, vec3(0.35, 0.65, 1.0), 0.5 + 0.5 * sin(ang * 2.0 + t * 0.9));  // violet into arcane blue
	vec3 col = hue * (rim * 1.1 + haze) + spark.rgb * mist;
	// sparkles: two layers of cells drifting up, some with a four-rayed glint that twinkles
	float s = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float cell = mix(17.0, 11.0, fl);
		vec2 p = px + vec2(sin(t * 0.7 + fl) * 3.0, t * mix(12.0, 20.0, fl));
		vec2 id = floor(p / cell);
		float h = hash(id + seed + fl * 17.0);
		if (h > 0.5) {
			continue;
		}
		vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
		vec2 d = (fract(p / cell) - 0.5 - o * 0.5) * cell;
		float tw = pow(0.5 + 0.5 * sin(t * (2.5 + h * 6.0) + h * 40.0), 4.0);
		float len = mix(7.0, 4.5, fl) * (0.5 + tw);
		float rays = exp(-abs(d.x) * 1.4) * (1.0 - smoothstep(0.0, len, abs(d.y))) + exp(-abs(d.y) * 1.4) * (1.0 - smoothstep(0.0, len, abs(d.x)));
		float core = exp(-dot(d, d) * 0.35);
		s += (rays * 0.8 + core * 1.3) * tw;
	}
	// they live around the portrait, a few over it
	float band = (1.0 - smoothstep(1.1, 1.55, r)) * (0.3 + 0.7 * smoothstep(0.6, 0.98, r));
	col += spark.rgb * s * band;
	COLOR = vec4(col, fade);
}
