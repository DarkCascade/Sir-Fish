shader_type canvas_item;
// Rounds a ColorRect's corners without touching its color/size logic (spec
// reskin: party bars). box_size must track the rect's actual size - the
// script keeps it in sync via the `resized` signal - and corner_radius is
// clamped to half the shorter side, so a large radius reads as a full pill.

uniform vec2 box_size = vec2(32.0, 32.0);
uniform float corner_radius = 8.0;

float rounded_box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * box_size;
	float r = min(corner_radius, min(box_size.x, box_size.y) * 0.5);
	float d = rounded_box_sdf(p, box_size * 0.5, r);
	COLOR.a *= 1.0 - smoothstep(0.0, 1.5, d);
}
