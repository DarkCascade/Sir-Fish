extends PanelContainer
## Resources row + three hero rows (spec 17.2).

const ROW_SCENE := preload("res://scenes/console/hero_status_row.tscn")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

var director = null               # BattleDirector (untyped: custom API)

@onready var gold_label: Label = $Layout/ResourceRow/GoldLabel
@onready var inventory_strip = $Layout/ResourceRow/InventoryStrip
@onready var rows_box: VBoxContainer = $Layout/HeroRows

var _rows: Array = []
var _party_buff_active: bool = false

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.party_damage_buff_started.connect(func(_d: float) -> void:
		_party_buff_active = true)
	EventBus.party_damage_buff_ended.connect(func() -> void:
		_party_buff_active = false)
	_update_gold()
	build_rows()

func build_rows() -> void:
	for child: Node in rows_box.get_children():
		child.queue_free()
	_rows.clear()
	for entry: Dictionary in GameState.hero_runtime:
		var stats := GameState.get_stats(entry["stats_id"])
		if stats == null:
			continue
		var row = ROW_SCENE.instantiate()
		rows_box.add_child(row)
		row.setup(stats)
		_rows.append(row)

func _process(_delta: float) -> void:
	if director == null:
		return
	for i: int in range(mini(_rows.size(), director.heroes.size())):
		_rows[i].refresh(director.heroes[i], _party_buff_active)

func _update_gold() -> void:
	gold_label.text = str(GameState.gold)

func _on_gold_changed(_new_total: int, delta: int) -> void:
	_update_gold()
	gold_label.pivot_offset = gold_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(gold_label, "scale", Vector2(1.22, 1.22), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.13)
	if delta != 0:
		_float_delta(delta)

func _float_delta(delta: int) -> void:
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	label.position = gold_label.position + Vector2(gold_label.size.x + 20.0, 10.0)
	var color := Tuning.C_GOLD if delta > 0 else Tuning.C_DANGER
	label.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 38, 60.0, 0.8)
