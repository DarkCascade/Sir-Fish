extends PanelContainer
## The console's resource strip (spec 17.2): Sir Fish, the gold, and the party
## roster (party_bars.gd) filling the room to their right.
##
## Per-hero health is stated exactly once, here. It used to be drawn twice - three
## 70 px rows in this panel AND a bar over every hero's head - which is what this
## strip exists to fix.
##
## The item chips and the slot wins/spins counter were here too, and are gone:
## items still work and their effects still land, and the run summary still
## reports the slot's record at the end (spec 18.2) - neither needed a live
## readout competing with the cabinet.
##
## [presentation redesign S6] Gold and depth are now OrnateFrame-backed plates
## (GoldPlate/DepthPlate) rather than bare labels sitting directly in
## ResourceRow, and depth is two labels (caption + numeral) instead of one
## string, so the two can carry different font sizes.
##
## [slot phase 2] The bonus row is gone. Item effects are slot icons now, and
## each hero's reel-icon contribution is shown in the party modal
## (party_modal.gd), under that hero's health bar.

## [town] spec 5.3: the pop-and-float treatment lives in one shared place now,
## lifted out of this file so CurrencyPlate (and step 9's forge) reuse it rather
## than carrying a second and third copy.
const CurrencyFeedback := preload("res://scripts/ui/currency_feedback.gd")
const CurrencyPlate := preload("res://scripts/hud/currency_plate.gd")

## [slot ui phase 3] The plate carries gold AND scrap now. The HUD's own
## CurrencyPlate hides for the whole quest (hud.gd), so this is the expedition's
## only readout of either.
@onready var gold_label: Label = $Layout/ResourceRow/GoldPlate/Rows/GoldRow/GoldLabel
@onready var scrap_label: Label = $Layout/ResourceRow/GoldPlate/Rows/ScrapRow/ScrapLabel
## [black-glass] The gold plate's own face, tweened alongside the strip's own
## "panel" stylebox by apply_boss_theme()/clear_boss_theme().
@onready var _plate_face: Panel = $Layout/ResourceRow/GoldPlate/Face
@onready var _plate_vines: NinePatchRect = $Layout/ResourceRow/GoldPlate/Vines

const BiomeTheme := preload("res://scripts/ui/biome_theme.gd")
const BOSS_THEME_TIME := 0.3

## Muted while the shop is open (EventBus.shop_visibility_changed): the panel
## sits behind the shop scrim, where a run of buy/sell deltas just stacks into
## an unreadable smear over the number.
var _shop_open: bool = false

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.scrap_changed.connect(_on_scrap_changed)
	EventBus.shop_visibility_changed.connect(func(is_open: bool) -> void: _shop_open = is_open)
	#EventBus.run_started.connect(_update_depth)
	#EventBus.encounter_started.connect(func(_index: int, _def: EncounterDef) -> void: _update_depth())
	_update_gold()
	scrap_label.text = str(GameState.scrap)
	#_update_depth()

func _update_gold() -> void:
	gold_label.text = str(GameState.gold)

func _on_scrap_changed(new_total: int, delta: int) -> void:
	scrap_label.text = str(new_total)
	if _shop_open:
		return
	CurrencyFeedback.pop(scrap_label)
	CurrencyFeedback.float_delta(self, scrap_label, delta, CurrencyPlate.SCRAP_COLOR)

func _on_gold_changed(_new_total: int, delta: int) -> void:
	_update_gold()
	if _shop_open:
		return
	CurrencyFeedback.pop(gold_label)
	# The number pops as a child of StatusPanel itself, not of GoldPlate, so the
	# helper converts through global_position (S6's GoldPlate nesting moved
	# GoldLabel a level deeper than when this read gold_label.position directly).
	CurrencyFeedback.float_delta(self, gold_label, delta, Tuning.C_GOLD)

# --- black-glass boss theme --------------------------------------------------

## Called by Console.apply_boss_theme() - see slot_machine.gd's own copy of
## this pair for the full contract (when apply/clear fire).
func apply_boss_theme() -> void:
	_tween_theme(Tuning.C_OBSIDIAN_DEEP, Tuning.C_OBSIDIAN, Tuning.C_SEAM)
	_plate_vines.texture = BiomeTheme.card_frame(BiomeTheme.for_boss())

func clear_boss_theme() -> void:
	_tween_theme(Tuning.C_ROOTWOOD_VOID, Tuning.C_ROOTWOOD, Tuning.C_GOLD_DARK)
	_plate_vines.texture = BiomeTheme.card_frame()

## `self` is the StatusPanel PanelContainer, whose own "panel" stylebox is the
## strip background + top border; `_plate_face`'s is the gold plate's face.
## Both StyleBoxFlats are duplicated once (if not already) so this can mutate
## bg_color/border_color in place - the live-stylebox trick biome_theme.gd's
## apply_panel_backdrop() already uses for the same reason.
func _tween_theme(strip_bg: Color, plate_bg: Color, strip_border: Color) -> void:
	var strip_style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	add_theme_stylebox_override("panel", strip_style)
	var plate_style: StyleBoxFlat = _plate_face.get_theme_stylebox("panel").duplicate()
	_plate_face.add_theme_stylebox_override("panel", plate_style)

	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(c: Color) -> void:
		strip_style.bg_color = c
		queue_redraw(), strip_style.bg_color, strip_bg, BOSS_THEME_TIME)
	tw.tween_method(func(c: Color) -> void:
		strip_style.border_color = c
		queue_redraw(), strip_style.border_color, strip_border, BOSS_THEME_TIME)
	tw.tween_method(func(c: Color) -> void:
		plate_style.bg_color = c
		_plate_face.queue_redraw(), plate_style.bg_color, plate_bg, BOSS_THEME_TIME)
