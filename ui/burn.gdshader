// A card burning away: holes eaten by noise from the edges in, a glowing rim
// (white, yellow, orange, dark red) at the burning edge, charred brown just inside.
shader_type canvas_item;

uniform sampler2D noise : repeat_enable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 size = vec2(144.0, 204.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 uv = local / size;
	float n = texture(noise, uv * 1.3).r;
	// burn starts at the bottom right corner and the edges, then eats inwards
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float v = n * 0.75 + edge * 0.6 + (1.0 - uv.y) * 0.15;
	float t = progress * 1.35;
	float d = v - t;
	if (d < 0.0) {
		discard;
	}
	vec4 c = COLOR;
	if (d < 0.025) {
		c.rgb = mix(vec3(1.0, 1.0, 0.85), vec3(1.0, 0.75, 0.2), d / 0.025);
	} else if (d < 0.06) {
		c.rgb = mix(vec3(1.0, 0.45, 0.05), vec3(0.45, 0.08, 0.02), (d - 0.025) / 0.035);
	} else if (d < 0.12) {
		c.rgb = mix(c.rgb * 0.25, c.rgb, (d - 0.06) / 0.06);
	}
	COLOR = c;
}
