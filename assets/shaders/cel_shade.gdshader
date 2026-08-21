shader_type spatial;
// depth_draw_always, NOT depth_draw_opaque (spec 6.2 wrote the latter).
//
// This is forced by spec 6.3 / Q16. Adding blend_mix to outline.gdshader moved
// the inverted hull out of the opaque pass and into the transparent pass, where
// next_pass makes it render AFTER the body rather than before it. A transparent
// material with depth_draw_opaque writes no depth, so the body had nothing to
// depth-test the hull against and every character rendered as a solid black
// silhouette. Writing depth from the body lets the hull be rejected everywhere
// except the rim, which is the whole point of an inverted-hull outline.
// Recorded in spec 21.5 and QUESTIONS-v2.md V11.
render_mode blend_mix, cull_back, depth_draw_always, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float band_count : hint_range(2.0, 5.0, 1.0) = 3.0;
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.52, 0.78, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 6.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = alpha;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb * emission_strength;
}

void light() {
	float ndotl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float steps = max(band_count - 1.0, 1.0);
	float banded = round(ndotl * steps) / steps;
	vec3 shaded = mix(ALBEDO * shadow_tint.rgb, ALBEDO, banded);
	DIFFUSE_LIGHT += shaded * LIGHT_COLOR * ATTENUATION / PI;

	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	rim = smoothstep(1.0 - rim_amount, 1.0, rim) * banded;
	SPECULAR_LIGHT += rim_color.rgb * rim * 0.5;
}
