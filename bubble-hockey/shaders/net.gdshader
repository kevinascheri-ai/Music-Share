shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Goal netting: a thin white mesh you can see the puck through.

uniform float cells = 14.0;

void fragment() {
	vec2 g = abs(fract(UV * cells) - 0.5);
	float line = 1.0 - smoothstep(0.38, 0.46, max(g.x, g.y));
	ALBEDO = vec3(0.95);
	ALPHA = line * 0.85;
	ROUGHNESS = 0.8;
}
