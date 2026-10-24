shader_type spatial;
// The playfield: polished ice with painted markings and the grooved slots the
// figures ride in. Everything is drawn from math, so it stays sharp at any
// resolution. UV (0..1) maps to table pixels through `rink`.

uniform vec2 rink = vec2(600.0, 1100.0);
uniform float corner_radius = 80.0;
uniform float goal_width = 150.0;
// Slot segments in table pixels: (ax, ay, bx, by).
uniform vec4 slots[16];
uniform int slot_count = 0;
uniform vec3 ice_color : source_color = vec3(0.84, 0.9, 0.97);
uniform vec3 red_paint : source_color = vec3(0.86, 0.13, 0.16);
uniform vec3 blue_paint : source_color = vec3(0.12, 0.38, 0.9);
uniform vec3 groove_color : source_color = vec3(0.03, 0.05, 0.09);
uniform sampler2D logo : source_color, filter_linear_mipmap;
uniform bool has_logo = false;
// 0..1, flashes the center hole when the puck pops up.
uniform float pop_glow = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 1 inside a band of width `w` around distance 0, antialiased.
float band(float d, float w) {
	float aa = fwidth(d) * 1.2;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(d));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * rink;
	vec2 half_size = rink * 0.5;
	vec2 q = abs(p - half_size) - (half_size - corner_radius);
	float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
	if (edge > 0.5) {
		discard;
	}

	// Ice: faint frost and skate-scratch streaks, a little darker near the boards.
	float frost = noise(p * 0.05) * 0.5 + noise(p * 0.21) * 0.3 + noise(vec2(p.x * 0.9, p.y * 0.02)) * 0.2;
	vec3 col = ice_color * (0.955 + 0.045 * frost);
	col *= mix(0.86, 1.0, smoothstep(-60.0, -6.0, edge));

	float cx = half_size.x;
	float cy = half_size.y;
	// Center red line (with the classic dashes), blue lines.
	float red_line = band(p.y - cy, 9.0) * (0.75 + 0.25 * step(0.5, fract(p.x / 26.0)));
	float blue = band(p.y - rink.y * 0.32, 10.0) + band(p.y - rink.y * 0.68, 10.0);
	col = mix(col, red_paint, red_line * 0.9);
	col = mix(col, blue_paint, clamp(blue, 0.0, 1.0) * 0.85);

	// Center circle and dot.
	float center_d = length(p - vec2(cx, cy));
	if (has_logo && center_d < 72.0) {
		vec4 l = texture(logo, (p - vec2(cx, cy)) / 144.0 + 0.5);
		col = mix(col, l.rgb, l.a * 0.9);
	}
	col = mix(col, blue_paint, band(center_d - 74.0, 4.0));
	// Zone face-off circles.
	for (int i = 0; i < 4; i++) {
		vec2 c = vec2(i % 2 == 0 ? rink.x * 0.25 : rink.x * 0.75, i < 2 ? rink.y * 0.17 : rink.y * 0.83);
		float d = length(p - c);
		col = mix(col, red_paint, band(d - 52.0, 3.5) * 0.85);
		col = mix(col, red_paint, (1.0 - smoothstep(6.0, 7.5, d)) * 0.9);
	}
	// Goal creases and goal lines.
	for (int end = 0; end < 2; end++) {
		float gy = end == 0 ? 0.0 : rink.y;
		float d = length(p - vec2(cx, gy));
		float inside = 1.0 - smoothstep(76.0, 78.0, d);
		col = mix(col, vec3(0.45, 0.68, 0.96), inside * 0.45);
		col = mix(col, red_paint, band(d - 78.0, 3.5));
	}

	// Slots: dark grooves with a lit lower lip, so they read as cut into the ice.
	float groove = 0.0;
	float lip = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= slot_count) {
			break;
		}
		float d = seg_dist(p, slots[i].xy, slots[i].zw);
		groove = max(groove, 1.0 - smoothstep(4.0, 5.5, d));
		lip = max(lip, band(d - 6.5, 2.5));
	}
	col = mix(col, col * 1.08, lip);
	col = mix(col, groove_color, groove);

	// The hole the puck pops up from.
	col = mix(col, groove_color, 1.0 - smoothstep(9.0, 10.5, center_d));
	EMISSION = vec3(1.0, 0.85, 0.35) * pop_glow * (1.0 - smoothstep(10.0, 40.0, center_d)) * 3.0;

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.2, frost) + groove * 0.6;
	SPECULAR = 0.65;
	METALLIC = 0.0;
}
