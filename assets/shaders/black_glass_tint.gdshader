shader_type canvas_item;

// [black-glass] Recolours the warm pixels of art whose gold is baked in (the
// special invokers' Meshy renders) toward the Black Glass palette, so a boss
// fight can reskin it without new art. Warm = hue below ~0.2 with some
// saturation: every invoker render splits cleanly into a warm frame and a cool
// glass dome and glyph, with no hues in between, so the glyphs stay untouched.
// Luminance picks the ramp stop, so shading and the lit/dim modulate survive.
// Works on COLOR, so it tints textured and _draw() canvas items alike.
// The palette is pushed from Tuning's C_* constants by the owning script.

uniform float boss_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep : source_color;
uniform vec3 facet : source_color;
uniform vec3 seam : source_color;
uniform vec3 seam_bright : source_color;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	if (boss_mix > 0.0) {
		vec3 c = COLOR.rgb;
		vec3 hsv = rgb_to_hsv(c);
		float warm = 1.0 - smoothstep(0.17, 0.24, hsv.x);
		float weight = warm * smoothstep(0.10, 0.28, hsv.y) * boss_mix;
		float t = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)) * 1.35, 0.0, 1.0);
		vec3 ramp = mix(deep, facet, clamp(t / 0.35, 0.0, 1.0));
		ramp = mix(ramp, seam, clamp((t - 0.35) / 0.35, 0.0, 1.0));
		ramp = mix(ramp, seam_bright, clamp((t - 0.7) / 0.3, 0.0, 1.0));
		COLOR.rgb = mix(c, ramp, weight);
	}
}
