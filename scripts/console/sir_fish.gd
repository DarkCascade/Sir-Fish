extends Node3D
## Sir Fish (spec 17.7 / Q18). The title stops being a lie.
##
## He is THE PLAYER: an armoured fish in a tank bolted to the console, right
## beside the button you press. He is the one running the war room; the heroes are
## his employees.
##
## He has ZERO gameplay effect, and that is deliberate. He is the emotional read
## on state that the numbers cannot give - he cheers when the slot pays, darts
## when a hero is hit, sinks to the gravel when one dies, and lies on his side
## when the run ends.

const RIG := preload("res://scripts/console/sir_fish_rig.gd")

## Highest first. A higher-priority state interrupts a lower one; a lower one is
## dropped while a higher one is playing (spec 17.7).
const PRIORITY := {
	&"slump": 6,
	&"triumph": 6,
	&"grieve": 5,
	&"alarm": 4,
	&"smug": 3,
	&"cheer": 2,
	&"idle": 1,
}

## slump and triumph hold until the next run starts; everything else returns to
## idle when it finishes.
const HOLDING := [&"slump", &"triumph"]

## During a three-enemy fight an un-limited alarm would fire constantly and read
## as a seizure rather than as a reaction (spec 17.7).
const ALARM_COOLDOWN := 0.6

var state: StringName = &"idle"

var _anim: AnimationPlayer
var _alarm_ready_at: float = 0.0
var _bubbles: GPUParticles3D

## [M8a] The modelled, rigged fish - res://assets/meshes/sir_fish.glb, swapped
## in as a child of this node (sir_fish_tank.tscn). Its AnimationPlayer
## carries the seven clips authored in Blender (spec 23.5); this script only
## reassigns materials and adds the bubble burst, neither of which survives
## the glTF round-trip.
const MODEL_PATH := "Model"

func _ready() -> void:
	var model: Node3D = get_node(MODEL_PATH) as Node3D
	RIG.reassign_materials(model)
	_anim = model.get_node("AnimationPlayer") as AnimationPlayer
	_anim.animation_finished.connect(_on_animation_finished)
	_bubbles = RIG.build_bubbles()
	add_child(_bubbles)

	EventBus.slot_payout.connect(_on_slot_payout)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.combatant_damaged.connect(_on_combatant_damaged)
	EventBus.combatant_died.connect(_on_combatant_died)
	EventBus.game_over.connect(_on_game_over)
	EventBus.run_completed.connect(_on_run_completed)
	EventBus.run_started.connect(_on_run_started)

	play(&"idle")

# --- state machine ----------------------------------------------------------

func play(next: StringName, force: bool = false) -> void:
	if not _anim.has_animation(next):
		return
	if not force and _anim.is_playing():
		var current_priority: int = int(PRIORITY.get(state, 0))
		var next_priority: int = int(PRIORITY.get(next, 0))
		if next_priority < current_priority:
			return                    # drop it; something louder is playing
	state = next
	_anim.play(next)
	if next == &"cheer" or next == &"triumph":
		_burst_bubbles()

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name in HOLDING:
		return                        # slump and triumph hold until run_started
	play(&"idle", true)

func _burst_bubbles() -> void:
	if _bubbles == null:
		return
	_bubbles.restart()
	_bubbles.emitting = true

# --- reactions --------------------------------------------------------------

func _on_slot_payout(_kind: String, count: int) -> void:
	# A pair makes him cheer; a triple makes him smug.
	play(&"smug" if count >= 3 else &"cheer")

func _on_upgrade_purchased(_id: StringName, _level: int) -> void:
	play(&"smug")

func _on_combatant_damaged(target: Node, _amount: int, _previous_hp: int,
		_new_hp: int) -> void:
	var c := target as Combatant
	if c == null or not c.is_hero:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now < _alarm_ready_at:
		return
	_alarm_ready_at = now + ALARM_COOLDOWN
	play(&"alarm")

func _on_combatant_died(c: Node) -> void:
	var combatant := c as Combatant
	if combatant == null or not combatant.is_hero:
		return
	play(&"grieve")

func _on_game_over() -> void:
	# Fired before the scrim, so the player sees him give up (spec 18.1).
	play(&"slump", true)

func _on_run_completed() -> void:
	play(&"triumph", true)

func _on_run_started() -> void:
	play(&"idle", true)
