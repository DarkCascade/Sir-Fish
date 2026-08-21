class_name ParallaxProfiles
extends RefCounted
## Periodic silhouette profiles for parallax layers 1-3 (spec 7.5).
##
## Every harmonic's wavenumber k is an integer, so y(-W/2) == y(+W/2) by
## construction, and three copies of one tile join seamlessly. That is the
## whole guarantee. Do NOT add a per-tile phase or a per-tile seed - spec
## 7.5.1 records the 81px horizon step that did.

## harmonics: Array of [k: int, amplitude: float, phase: float]
static func sample(x: float, tile_width: float, base: float,
		harmonics: Array) -> float:
	var y: float = base
	for h: Array in harmonics:
		y += float(h[1]) * sin(TAU * float(h[0]) * x / tile_width + float(h[2]))
	return y

## Wavenumbers are quoted against Tuning.PARALLAX_TILE_WIDTH_PROC (36.0), so
## k = 3 is one full wave every 12 world units - the wavelength the 12-unit
## build shipped with. Amplitudes are v1's, unchanged; only the period differs.
const HILLS := [[3, 0.75, 0.0], [9, 0.35, 1.10], [21, 0.12, 2.40]]
const HILLS_BASE := 1.50
const HILLS_FLOOR := -1.50
