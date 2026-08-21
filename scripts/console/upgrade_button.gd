extends Button
## One purchasable slot upgrade (spec 17.6). 340 x 178.
##
## Re-evaluates on gold_changed and upgrade_purchased, exactly as the shop cards
## do - purchases, sales, slot payouts and other upgrades all move gold.

const PIP := 18.0
const PIP_GAP := 8.0

var id: StringName = &""

var _title: Label
var _blurb: Label
var _pips: Control
var _cost: Label
var _coin: Control
var _pulse: Tween = null

func setup(upgrade_id: StringName) -> void:
	id = upgrade_id
	_build()
	refresh()

func _ready() -> void:
	custom_minimum_size = Vector2(340, 178)
	pressed.connect(_on_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.run_started.connect(refresh)

func _build() -> void:
	if _title != null:
		return
	var def: Dictionary = Upgrades.DEFS[id]

	_title = Label.new()
	_title.theme_type_variation = &"DisplayLabel"     # font 30 is under 40, but the
	_title.position = Vector2(16, 12)                 # button titles are named in 6.5
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Tuning.C_TEXT)
	_title.text = String(def["name"])
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_blurb = Label.new()
	_blurb.position = Vector2(16, 50)
	_blurb.custom_minimum_size = Vector2(308, 0)
	_blurb.add_theme_font_size_override("font_size", 22)
	_blurb.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	_blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blurb)

	_pips = Control.new()
	_pips.position = Vector2(16, 92)
	_pips.custom_minimum_size = Vector2(
		PIP * Tuning.UPGRADE_MAX_LEVEL + PIP_GAP * (Tuning.UPGRADE_MAX_LEVEL - 1), PIP)
	_pips.size = _pips.custom_minimum_size
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	add_child(_pips)

	_coin = Control.new()
	_coin.position = Vector2(16, 128)
	_coin.size = Vector2(28, 28)
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.draw.connect(_draw_coin)
	add_child(_coin)

	_cost = Label.new()
	_cost.theme_type_variation = &"DisplayLabel"
	_cost.position = Vector2(52, 122)
	_cost.add_theme_font_size_override("font_size", 32)
	_cost.add_theme_color_override("font_color", Tuning.C_GOLD)
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost)

func _draw_pips() -> void:
	var level := Upgrades.level(id)
	for i: int in range(Tuning.UPGRADE_MAX_LEVEL):
		var r := Rect2(Vector2(float(i) * (PIP + PIP_GAP), 0.0), Vector2(PIP, PIP))
		if i < level:
			_pips.draw_rect(r, Tuning.C_GOLD)
		else:
			_pips.draw_rect(r, Color("5C5470"), false, 2.0)

func _draw_coin() -> void:
	var c := Vector2(14, 14)
	_coin.draw_circle(c, 12.0, Tuning.C_GOLD)
	_coin.draw_arc(c, 12.0, 0.0, TAU, 20, Tuning.C_INK, 2.0)

# --- state ------------------------------------------------------------------

func refresh() -> void:
	if _title == null:
		return
	var def: Dictionary = Upgrades.DEFS[id]
	_pips.queue_redraw()

	if Upgrades.is_maxed(id):
		_blurb.text = String(def["blurb"]) % Upgrades.next_effect_percent(id)
		_cost.text = "MAX"
		_cost.add_theme_color_override("font_color", Color("4CC38A"))
		_coin.visible = false
		disabled = true
		modulate = Color.WHITE
		_kill_pulse()
		return

	# The blurb shows the NEXT level's cumulative effect, so the player is reading
	# what they are about to buy rather than what they already have.
	_blurb.text = String(def["blurb"]) % Upgrades.next_effect_percent(id)
	var price := Upgrades.cost(id)
	_cost.text = str(price)
	_cost.add_theme_color_override("font_color", Tuning.C_GOLD)
	_coin.visible = true

	var affordable := GameState.gold >= price
	disabled = not affordable
	modulate = Color.WHITE if affordable else Color(0.45, 0.45, 0.5, 1.0)
	if affordable:
		_start_pulse()
	else:
		_kill_pulse()

func _start_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "self_modulate", Color(1.10, 1.06, 0.92), 0.8) \
		.set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "self_modulate", Color.WHITE, 0.8) \
		.set_trans(Tween.TRANS_SINE)

func _kill_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	self_modulate = Color.WHITE

# --- purchase ---------------------------------------------------------------

func _on_pressed() -> void:
	if not Upgrades.buy(id):
		return
	pivot_offset = size * 0.5
	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.06, 1.06), 0.125) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", Vector2.ONE, 0.125)
	# The newly-earned pip pops in.
	_pips.pivot_offset = _pips.size * 0.5
	_pips.scale = Vector2(0.6, 0.6)
	var pip_tw := create_tween()
	pip_tw.tween_property(_pips, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_gold_changed(_total: int, _delta: int) -> void:
	refresh()

func _on_upgrade_purchased(_id: StringName, _level: int) -> void:
	refresh()
