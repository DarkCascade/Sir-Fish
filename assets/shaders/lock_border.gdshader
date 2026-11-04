shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// [cell locks] The border drawn around a locked Rune Floor cell: a gold frame
// along the tile's edge with a bright sheen travelling round it, so a locked
// cell reads from across the board. Sits on a flat quad just above the tile.

uniform vec4 gold : source_color = vec4(1.0, 0.82, 0.3, 1.0);
// Frame thickness as a fraction of the half-width.
uniform float width : hint_range(0.02, 0.4) = 0.18;
// How fast the sheen laps the frame, in turns per second.
uniform float speed : hint_range(0.0, 3.0) = 0.45;
// 0 hides the frame, 1 is full strength. The board tweens it in and out.
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float edge = max(abs(p.x), abs(p.y));
	float inner = 1.0 - width;
	float band = smoothstep(inner, inner + 0.05, edge) * (1.0 - smoothstep(0.97, 1.0, edge));

	// Two sheens a half-turn apart, so one is always on screen.
	float turn = atan(p.y, p.x) / TAU;
	float a = fract(turn - TIME * speed);
	float b = fract(turn - TIME * speed + 0.5);
	float sheen = max(pow(1.0 - min(a, 1.0 - a) * 2.0, 6.0), pow(1.0 - min(b, 1.0 - b) * 2.0, 6.0));

	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	float strength = band * (0.55 + 0.9 * sheen) * pulse * fade;
	ALBEDO = gold.rgb * (1.0 + sheen);
	ALPHA = clamp(strength, 0.0, 1.0);
}
