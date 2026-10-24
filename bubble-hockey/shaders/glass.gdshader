shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// The bubble: nearly clear at the middle, catching light toward the rim.

uniform vec3 tint : source_color = vec3(0.82, 0.92, 1.0);
uniform float base_alpha = 0.03;
uniform float rim_alpha = 0.42;
uniform float rim_power = 3.2;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	ALBEDO = tint;
	ALPHA = base_alpha + rim * rim_alpha;
	ROUGHNESS = 0.02;
	SPECULAR = 1.0;
	EMISSION = tint * rim * 0.12;
}
