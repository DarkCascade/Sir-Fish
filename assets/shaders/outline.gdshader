shader_type spatial;
render_mode cull_front, depth_draw_opaque, unshaded, blend_mix;

// blend_mix + a real alpha uniform (spec 6.3 / Q16). v1 faked a fade by
// shrinking outline_width, which read as the model shrinking inside its own ink
// while a solid silhouette hung in the air. outline_width is now never touched
// at runtime.
uniform vec4 outline_color : source_color = vec4(0.059, 0.055, 0.078, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.018;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * alpha;
}
