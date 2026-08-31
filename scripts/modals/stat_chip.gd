@tool
extends VBoxContainer
## [reliquary] One item modifier rendered as a chip tile for the compare flyout:
## a rarity-tinted rounded-square plate carrying a stat icon, a "+N" / "+N%"
## badge pinned to its top-right corner, and a short caption beneath. Instanced
## by compare_flyout._fill_mods() in place of the old Label-per-line list, and
## laid out in an HFlowContainer so the chips wrap into rows like the reference.
##
## The plate is a procedural rounded StyleBoxFlat tinted per rarity at runtime -
## the simple-primitive, recolour-per-state case CLAUDE.md deliberately keeps
## out of Meshy. Only the stat ICON is generated art, and a not-yet-generated
## icon degrades to a bare plate rather than erroring (load(), not preload()).

@onready var _bg: PanelContainer = $Plate/IconClip/Bg
@onready var _icon: TextureRect = $Plate/IconClip/Icon
@onready var _badge_label: Label = $Plate/Badge/Label
@onready var _caption: Label = $Caption

const _ICON_DIR := "res://assets/ui/reliquary/"

## `mod` is one entry of Item.modifiers (see Itemizer.MODIFIERS). `tint` is the
## item's rarity colour, already resolved by the caller. An Enhanced modifier
## should pass the ENHANCED rarity colour as `tint`, matching the old
## _fill_mods() special-case.
func setup(mod: Dictionary, tint: Color) -> void:
	var label_s := String(mod.get("label", ""))
	var roll := int(mod.get("roll", 0))
	# `pct` is authored on the modifier now; the fallback is only for a modifier
	# dict loaded from a save that predates the key.
	var pct := bool(mod.get("pct", label_s.contains("% ")))
	_badge_label.text = ("+%d%%" % roll) if pct else ("+%d" % roll)
	_caption.text = String(mod.get("caption", _caption_from_label(label_s)))
	tooltip_text = label_s

	var tex := _load_icon(StringName(mod.get("id", &"")))
	_icon.texture = tex
	_icon.visible = tex != null

	var plate := (_bg.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	plate.bg_color = Tuning.C_RELIQUARY_STONE_DARK
	plate.border_color = tint
	plate.shadow_color = Color(tint.r, tint.g, tint.b, 0.38)
	plate.shadow_size = 7
	_bg.add_theme_stylebox_override("panel", plate)

func _load_icon(id: StringName) -> Texture2D:
	if id == &"":
		return null
	var path := "%schip_%s.png" % [_ICON_DIR, id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## "+12% Damage" -> "Damage". Only reached for a pre-`caption` save modifier.
func _caption_from_label(label: String) -> String:
	var parts := label.split(" ", false)
	return " ".join(parts.slice(1)) if parts.size() >= 2 else label
