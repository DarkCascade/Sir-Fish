shader_type spatial;
render_mode blend_mix, cull_back, unshaded, depth_draw_never;

uniform vec4 smoke_color : source_color = vec4(0.078, 0.071, 0.102, 1.0);
uniform float speed = 0.35;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.55;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }

void fragment() {
	float f = fract(hash(floor(NORMAL * 9.0)) + TIME * speed);
	float wobble = 0.75 + 0.25 * sin(TIME * 2.1 + f * 6.28);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	ALBEDO = smoke_color.rgb;
	ALPHA = clamp(wobble * (1.0 - fres * edge_softness), 0.15, 0.95) * alpha;
}
