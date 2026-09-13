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

## [brass-and-velvet] Empty (the default) reads the live SceneRouter place, as
## before - inventory/party status's own Frame instances leave this unset. A
## modal with a FIXED identity instead of a place-following one - the shop, via
## BiomeTheme.for_shop() - sets this in its own .tscn so this instance never
## has to be told again on every open() the way apply_panel_backdrop() does.
@export var biome_override: StringName = &""

func _ready() -> void:
	apply(biome_override)

## Re-applies the corner texture for `override` (biome_override by default).
## Public and separate from _ready() so a host that sets biome_override
## imperatively rather than declaratively - compare_flyout.gd, which forwards
## its OWN export to this Frame's - can re-assert it: Godot readies children
## before their parent, so the parent's _ready() would otherwise always be one
## beat too late to catch this node's own default-empty _ready() pass.
func apply(override: StringName = biome_override) -> void:
	biome_override = override
	var tex := BiomeTheme.frame_corner(biome_override)
	for child: TextureRect in [$TL, $TR, $BL, $BR]:
		child.texture = tex
