shader_type canvas_item;
// [ui-project-longshot] Darkens the edges of the battle view.
//
// The concept board's world panel is framed by heavy shadow - the forest goes
// nearly black at the left, right and top corners, and only the path down the
// centre and the archway at its end are fully lit. Without it the render's
// treeline stays at full brightness right up to the frame edge, so the eye has
// nothing pulling it toward the middle and the whole panel reads flat.
//
// Tinted rather than black: `tint` is the deep night blue the sky already
// uses, so the corners fall into the same darkness the scene is lit by
// instead of turning grey. Multiplying toward black would desaturate the
// forest's teal as it darkened it.
//
// Elliptical rather than circular. The panel is much wider than it is tall, so
// a circular falloff either leaves the short axis untouched or eats the middle
// of the long one; `aspect` stretches the field to the rect's own proportions.

uniform vec4 tint : source_color = vec4(0.02, 0.05, 0.11, 1.0);
// Where the darkening starts, as a fraction of the half-diagonal. Below this
// the image is untouched.
uniform float inner : hint_range(0.0, 1.5) = 0.42;
// Where it reaches full strength.
uniform float outer : hint_range(0.0, 2.0) = 1.05;
uniform float strength : hint_range(0.0, 1.0) = 0.82;
// Extra darkening on the TOP edge only. The board's canopy is the darkest
// thing in the frame and its ground the lightest, so a symmetrical vignette
// leaves the bottom corners too heavy and the top too light.
uniform float top_bias : hint_range(0.0, 1.0) = 0.30;
uniform vec2 aspect = vec2(1.0, 0.55);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * aspect;
	float d = length(p);
	float v = smoothstep(inner, outer, d) * strength;
	// UV.y is 0 at the top, so (1.0 - UV.y) weights the canopy end.
	v += smoothstep(0.55, 0.0, UV.y) * top_bias;
	COLOR = vec4(tint.rgb, clamp(v, 0.0, 1.0));
}
