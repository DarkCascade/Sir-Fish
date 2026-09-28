extends Button
class_name HeroPlate
## [rune floor dock] One hero's plate in the Rune Floor dock (design A of the
## dock mockups, chosen 2026-09-26): health bar on top, portrait in a segmented
## charge ring, the special's name in a pill. The whole plate is the special's
## button. It replaces the Meshy invoker art and the thin bars under it, whose
## text came out at 7-9 pt on a phone.
##
## Pressing asks the director to fire the hero's special, and the director
## refuses if it cannot happen (BattleDirector.invoke_hero_special), exactly as
## SpecialInvoker does - no rule lives twice.
##
## [expedition phase II] A hero not in the party yet keeps their plate as a
## "recruit to fill" teaser (#220, decided 2026-09-27): no health, the portrait
## in silhouette, `empty_text` in the pill, and nothing to press. The dock keeps
## one shape whatever the party's size, and the empty slot says it can grow.

## Authored per instance: whose plate this is, what their special is called,
## and their portrait and rune colour.
@export var hero_class: StringName = &""
@export var special_name: String = ""
@export var portrait: Texture2D
@export var owner_color: Color = Color.WHITE

## The plate's face while the special is not ready, and once a press would fire.
@export var idle_style: StyleBox
@export var lit_style: StyleBox
## What an empty slot's pill says.
@export var empty_text: String = "Recruit"
## How far a downed hero's plate dims.
const DOWN_DIM := Color(0.55, 0.55, 0.6)

@onready var _hp: PlateHpBar = $Column/HpBar
@onready var _ring: PlateChargeRing = $Column/Ring
@onready var _pill: PanelContainer = $Column/NamePill
@onready var _name: Label = $Column/NamePill/Name

## Set by the presentation. Null out of combat, when every plate reads from the
## profile.
var director = null

var _lit := false
var _empty := false
var _pill_style: StyleBoxFlat

func _ready() -> void:
	pressed.connect(_on_pressed)
	_name.text = special_name
	_ring.portrait = portrait
	_ring.color = owner_color
	# The pill's rim is the owner's colour, so each plate owns a copy of it.
	_pill_style = (_pill.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_pill.add_theme_stylebox_override("panel", _pill_style)
	_apply_lit(false, true)
	_apply_empty(not GameState.active_party.has(hero_class), true)

## Polled, like SpecialInvoker: whether a press would fire depends on HP and
## state no single signal covers.
func _process(_delta: float) -> void:
	_apply_empty(not GameState.active_party.has(hero_class))
	if _empty:
		return
	var hero := _hero()
	if hero != null:
		_hp.set_values(hero.current_hp, hero.max_hp, hero.is_alive())
	else:
		var hp := int(GameState.hero_entry(hero_class).get("current_hp", 0))
		_hp.set_values(hp, GameState.hero_max_hp(hero_class), hp > 0)
	var lit := _is_lit(hero)
	_ring.set_state(GameState.special_charge(hero_class), lit)
	_apply_lit(lit)
	modulate = DOWN_DIM if not _hp.alive else Color.WHITE

func _apply_empty(empty: bool, force: bool = false) -> void:
	if empty == _empty and not force:
		return
	_empty = empty
	disabled = empty
	_hp.modulate.a = 0.0 if empty else 1.0
	_ring.silhouette = empty
	_name.text = empty_text if empty else special_name
	if empty:
		_apply_lit(false, true)
		_ring.set_state(0, false)
		_pill_style.border_color = Tuning.C_GLASS_FACET
		_name.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		modulate = Color.WHITE
	else:
		_apply_lit(_lit, true)

func _apply_lit(lit: bool, force: bool = false) -> void:
	if lit == _lit and not force:
		return
	_lit = lit
	var face: StyleBox = lit_style if lit else idle_style
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, face)
	_pill_style.border_color = Tuning.C_GOLD_BRIGHT if lit else owner_color
	_name.add_theme_color_override("font_color", Tuning.C_GOLD_BRIGHT if lit else Tuning.C_TEXT)

## The same guard chain SpecialInvoker lights on: the director's own, ignoring a
## mid-action hero so the plate does not blink dark on every press.
func _is_lit(hero: Combatant) -> bool:
	if director != null and hero != null and director.has_method("can_invoke_hero_special"):
		return director.can_invoke_hero_special(hero, true)
	return false

func _on_pressed() -> void:
	var hero := _hero()
	if director == null or hero == null:
		return
	director.invoke_hero_special(hero)

func _hero() -> Combatant:
	if director == null or hero_class == &"":
		return null
	for h: Combatant in director.heroes:
		if is_instance_valid(h) and h.stats != null and h.stats.id == hero_class:
			return h
	return null
