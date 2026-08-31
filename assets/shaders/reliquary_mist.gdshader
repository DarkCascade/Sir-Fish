shader_type canvas_item;
// [reliquary] Drifting violet fog for the modal backdrop. Self-contained value-
// noise fbm - no texture, so the modal shell needs no generated art to breathe.
// Rendered on a full-rect ColorRect/TextureRect behind the panel; the scrim
// ColorRect underneath still carries the base darkening.

uniform vec4 fog_color : source_color = vec4(0.545, 0.361, 0.965, 1.0); // C_CRYSTAL
uniform vec4 deep_color : source_color = vec4(0.141, 0.082, 0.239, 1.0); // near C_RELIQUARY_MIST
uniform float density : hint_range(0.0, 1.0) = 0.34;
uniform float drift_speed : hint_range(0.0, 0.4) = 0.045;
uniform float scale : hint_range(0.5, 6.0) = 2.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * scale;
	float t = TIME * drift_speed;
	// Two layers crossing at different rates so the fog never obviously loops.
	float n = fbm(uv + vec2(t, t * 0.6));
	n = fbm(uv + vec2(n * 1.5 - t, n - t * 0.4));
	float body = smoothstep(0.35, 0.9, n);
	// Fade toward the edges so the fog pools behind the panel, not at the corners.
	vec2 c = UV - 0.5;
	float vign = 1.0 - smoothstep(0.35, 0.72, length(c));
	vec3 col = mix(deep_color.rgb, fog_color.rgb, body);
	COLOR = vec4(col, body * density * vign);
}
