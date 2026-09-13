extends Node
## Content Phase 0 Step 1: the content lint test (content-phase-0 spec §3).
##
## Walks every CombatantStats on disk and asserts the §1 touch-point ledger's
## silent/dead failure modes are actually covered for that character, plus one
## check on QuestDef unrelated to characters (decision D2). This is a pure
## test addition - no production code changes ride along with it.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_content_registry.tscn

const TestSupport := preload("res://tests/test_support.gd")
const STATS_DIR := "res://resources/stats/"
const QUESTS_DIR := "res://resources/quests/"

var _t := TestSupport.new()

func _ready() -> void:
	_check_all_stats()
	_check_quests()
	_t.finish(get_tree(), "test_content_registry")

# --- CombatantStats (checks 1-7) --------------------------------------------

func _check_all_stats() -> void:
	var dir := DirAccess.open(STATS_DIR)
	if not _t.check(dir != null, "can open %s" % STATS_DIR):
		return
	var any := false
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		any = true
		var stats := load(STATS_DIR + clean) as CombatantStats
		if not _t.check(stats != null, "%s loads as CombatantStats" % clean):
			continue
		_check_stats(stats)
	_t.check(any, "at least one CombatantStats found in %s" % STATS_DIR)

func _check_stats(stats: CombatantStats) -> void:
	var id := String(stats.id)

	# 1. scene_path is non-empty, the scene exists, and it instantiates as a
	# Combatant.
	if not _t.check(not stats.scene_path.is_empty(), "%s: scene_path is set" % id):
		return
	if not _t.check(ResourceLoader.exists(stats.scene_path),
			"%s: scene_path '%s' exists" % [id, stats.scene_path]):
		return
	var packed: PackedScene = load(stats.scene_path)
	var node: Node = packed.instantiate()
	var c := node as Combatant
	if not _t.check(c != null, "%s: scene_path instantiates as a Combatant" % id):
		node.free()
		return

	add_child(c)
	# 2. CombatantAnimations.build() completes without assertion. setup() ->
	# _build() runs it; an assertion failure here would abort the test run
	# rather than report a FAIL line, which is itself the loud signal spec 1's
	# ledger promises for this row.
	c.setup(stats, -1)

	# 3. Every name in required_anims() is present on the resulting player.
	for n: StringName in stats.required_anims():
		_t.check(c.anim.has_animation(n), "%s: has required animation '%s'" % [id, n])

	# 4. Every clip that should resolve damage carries an _anim_impact call
	# track, timed inside the clip's length. "attack" always applies; "special"
	# only when the character actually has one.
	var clips_to_check: Array[StringName] = [&"attack"]
	if stats.special_every_n_actions > 0:
		clips_to_check.append(&"special")
	for clip_name: StringName in clips_to_check:
		if not c.anim.has_animation(clip_name):
			continue      # already flagged as missing by check 3
		_check_impact_track(id, clip_name, c.anim.get_animation(clip_name))

	# 5. An ability resolves for the character - after Step 2 (AbilityDef
	# resources replaced the id-keyed match in ability.gd), that means
	# stats.primary is non-null for EVERY character, hero or enemy: an enemy
	# with no dedicated ability now authors its own explicit
	# melee_strike_generic.tres reference rather than falling through an
	# unauthored match arm.
	_t.check(stats.primary != null, "%s: stats.primary is set" % id)
	if stats.special_every_n_actions > 0:
		_t.check(stats.special != null,
			"%s: stats.special is set (special_every_n_actions > 0)" % id)

	if stats.is_hero:
		# 6. Itemizer.weapon_types_for(id) is non-empty, so the class can
		# receive drops.
		_t.check(not Itemizer.weapon_types_for(stats.id).is_empty(),
			"%s: Itemizer.weapon_types_for() is non-empty (class can receive drops)" % id)
		# 7. [content phase 1] class_def is set and its innate_icon resolves to
		# a real board icon kind - replaces the old SlotIcon.innate_for() check
		# now that the mage/damage ternary moved onto ClassDef (spec §3 Step 2).
		if _t.check(stats.class_def != null, "%s: class_def is set" % id):
			_t.check(SlotIcon.kind_of(stats.class_def.innate_icon) != SlotIcon.Kind.BLANK,
				"%s: class_def.innate_icon resolves to a real icon kind" % id)
			_t.check(not stats.class_def.executes.is_empty(),
				"%s: class_def.executes owns at least one icon kind" % id)

	c.queue_free()

func _check_impact_track(id: String, clip_name: StringName, anim: Animation) -> void:
	var found := false
	var time := -1.0
	for t: int in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_METHOD:
			continue
		if anim.track_get_path(t) != NodePath(".."):
			continue
		for k: int in anim.track_get_key_count(t):
			var key: Dictionary = anim.track_get_key_value(t, k)
			if StringName(key.get("method", &"")) == &"_anim_impact":
				found = true
				time = anim.track_get_key_time(t, k)
	_t.check(found, "%s: '%s' carries an _anim_impact call track" % [id, clip_name])
	if found:
		_t.check(time >= 0.0 and time <= anim.length,
			"%s: '%s' impact time %.3f is inside the clip length %.3f"
				% [id, clip_name, time, anim.length])

# --- QuestDef (check 8) ------------------------------------------------------

func _check_quests() -> void:
	var dir := DirAccess.open(QUESTS_DIR)
	if not _t.check(dir != null, "can open %s" % QUESTS_DIR):
		return
	var any := false
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		any = true
		var q := load(QUESTS_DIR + clean) as QuestDef
		if not _t.check(q != null, "%s loads as QuestDef" % clean):
			continue
		# 8. Every QuestDef on disk has gold_reward > 0 (decision D2).
		_t.check(q.gold_reward > 0, "%s: gold_reward > 0 (decision D2)" % clean)
		# 9. [content phase 1] Every QuestDef carries at least one objective -
		# an empty list is never a win (GameState.quest_objectives_complete()).
		_t.check(not q.objectives.is_empty(),
			"%s: objectives is non-empty (spec §3 Step 1a)" % clean)
	_t.check(any, "at least one QuestDef found in %s" % QUESTS_DIR)
