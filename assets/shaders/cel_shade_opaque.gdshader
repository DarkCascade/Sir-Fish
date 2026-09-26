shader_type spatial;
// The cel shader's opaque twin, for scenery that never fades.
//
// cel_shade.gdshader is blend_mix so a character can fade (corpses, the wipe
// cinematic), which puts every surface using it in the transparent pass. Big
// scenery there is sorted against the shadow monsters' smoke, which is
// translucent and writes no depth, so a floor or slab sorted after a monster
// paints straight over it and leaves only the eyes. In the opaque pass the
// scenery is always drawn first and the smoke blends over it. Same banding,
// shadow tint and rim; no alpha.
render_mode cull_back, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float band_count : hint_range(2.0, 5.0, 1.0) = 3.0;
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.52, 0.78, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
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
