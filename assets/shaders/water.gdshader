shader_type spatial;
render_mode blend_mix, cull_back, unshaded, depth_draw_never;

// Sir Fish's tank glass (spec 17.7). Glass, not a water simulation: a fresnel
// term with a slow sine ripple, and nothing else.
uniform vec4 glass_color : source_color = vec4(0.494, 0.784, 0.890, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float fresnel_alpha : hint_range(0.0, 1.0) = 0.10;
uniform float ripple_speed = 0.8;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float ripple = 0.85 + 0.15 * sin(TIME * ripple_speed + VERTEX.y * 6.0);
	ALBEDO = glass_color.rgb;
	ALPHA = (base_alpha + fresnel_alpha * fres) * ripple * alpha;
}
