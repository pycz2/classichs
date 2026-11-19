// A grey ghostly flame licking over the top of a card: an Echo copy that goes away at the end of the turn.
// Value noise from a hash (no texture), two layers rising at different speeds: cheap on the web's renderer too.
// Strongest at the rect's top, gone by its bottom; the rect's colour tints it.
shader_type canvas_item;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float n = noise(vec2(UV.x * 7.0, UV.y * 5.0 + TIME * 1.4)) * 0.6 + noise(vec2(UV.x * 15.0, UV.y * 9.0 + TIME * 2.6)) * 0.4;
	float tongue = (1.0 - UV.y) + (n - 0.5) * 0.9;  // the flames' tongues: noise on a fall from the top
	float a = smoothstep(0.35, 0.85, tongue) * (0.45 + 0.55 * n);
	a *= smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.x);  // soft at the sides
	COLOR = vec4(COLOR.rgb * (0.75 + 0.45 * n), COLOR.a * a);
}
