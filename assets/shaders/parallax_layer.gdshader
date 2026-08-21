// Flat, unshaded colour for parallax silhouette tiles.
// Kept as a separate shader (per spec 3.1) so background layers never pick up
// the cel shader's banding, which would break the flat-colour read.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_opaque;

uniform vec4 layer_color : source_color = vec4(0.29, 0.62, 0.44, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = layer_color.rgb;
	ALPHA = layer_color.a * alpha;
}
