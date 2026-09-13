extends Control
## [biome-frames] Swaps the four corner TextureRects to the current biome's
## skin (BiomeTheme.frame_corner()) on entry. The scene's own ExtResource stays
## the gold-vine/expedition default, so a modal opened mid-quest (no town skin
## yet drawn) needs no override and looks exactly as it did before this file
## existed.
##
## `flip_h`/`flip_v` are already set per-corner in the .tscn and untouched here
## - only the texture resource changes, so a skin only has to draw ONE corner
## (top-left) the way frame_corner.png always has.
const BiomeTheme := preload("res://scripts/ui/biome_theme.gd")

func _ready() -> void:
	var tex := BiomeTheme.frame_corner()
	for child: TextureRect in [$TL, $TR, $BL, $BR]:
		child.texture = tex
