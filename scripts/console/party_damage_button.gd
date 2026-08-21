extends Button
## "Increase Party Damage" (spec 17.3). The buff timer is real time and
## encounter-agnostic: it keeps draining through travel, loot and shop.

var director = null               # BattleDirector (untyped: custom API)

var _remaining: float = 0.0
var _buffed: Array[Combatant] = []

@onready var buff_progress: ColorRect = $BuffProgress
@onready var idle_glow_target: Button = self

func _ready() -> void:
	buff_progress.visible = false
	pressed.connect(_on_pressed)
	_start_idle_pulse()

func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	# Driven from the remaining time rather than a Tween, so it stays correct
	# if the game is paused (spec 17.3).
	buff_progress.size.x = size.x * (_remaining / Tuning.PARTY_DAMAGE_BUFF_DURATION)
	if _remaining <= 0.0:
		_end_buff()

func _on_pressed() -> void:
	if _remaining > 0.0 or director == null:
		return
	_buffed.clear()
	for hero: Combatant in director.living_heroes():
		hero.damage_multiplier *= Tuning.PARTY_DAMAGE_BUFF_MULT
		_buffed.append(hero)
	_remaining = Tuning.PARTY_DAMAGE_BUFF_DURATION
	disabled = true
	buff_progress.visible = true
	buff_progress.size.x = size.x
	EventBus.party_damage_buff_started.emit(Tuning.PARTY_DAMAGE_BUFF_DURATION)

func _end_buff() -> void:
	for hero: Combatant in _buffed:
		# Divide back out rather than resetting to 1.0, so future stacking
		# buffs stay correct (spec 21-D13). Dead heroes are simply skipped.
		if is_instance_valid(hero) and hero.is_alive():
			hero.damage_multiplier /= Tuning.PARTY_DAMAGE_BUFF_MULT
	_buffed.clear()
	disabled = false
	buff_progress.visible = false
	EventBus.party_damage_buff_ended.emit()
	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.06, 1.06), 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", Vector2.ONE, 0.1)

func is_buff_active() -> bool:
	return _remaining > 0.0

## Cancels the buff with no scale punch - used by the retry path (spec 18.3).
func cancel_buff() -> void:
	if _remaining <= 0.0:
		return
	_remaining = 0.0
	for hero: Combatant in _buffed:
		if is_instance_valid(hero) and hero.is_alive():
			hero.damage_multiplier /= Tuning.PARTY_DAMAGE_BUFF_MULT
	_buffed.clear()
	disabled = false
	buff_progress.visible = false

func _start_idle_pulse() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween().set_loops()
	tw.tween_property(self, "self_modulate", Color(1.08, 1.06, 0.95), 0.9) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
