class_name StatModifiers
extends RefCounted
## [backlog P3, issue #75] The behaviour of decision 3.11's twelve off-board stat
## modifiers. Like `bleed` and `crit`, none of them is a board icon: each reads
## its summed roll off the wearer's gear (GameState.hero_stat) and changes a
## swing, a hit taken, a Block grant, max HP or a fight's starting charge.
##
## Everything here takes its participants as arguments rather than reaching for
## the director, so tests/test_stat_modifiers can drive each rule on bare
## Combatants. The callers are SlotMachine._swing_for (the weapon stats),
## Combatant.take_damage / add_temp_armor / apply_party_bonuses (the armor stats)
## and BattleDirector's combat start (resolve). vitality needs no hook: it is
## part of GameState.hero_max_hp.
##
## None of these roll on an item until #73 wires the per-type sets, so the
## magnitudes in Itemizer.MODIFIERS and Tuning are a first cut #73 measures.

# --- the weapon stats, on a hero's swing --------------------------------------

## `execute`: the bonus a swing at `target` gets, added before it is dealt. The
## target's HP is read at the swing, not at the animation's impact.
static func execute_bonus(hero: Combatant, target: Combatant) -> int:
	if not _is_live(hero) or not _is_live(target):
		return 0
	var bonus := GameState.hero_stat(hero.stats.id, &"execute")
	if bonus <= 0 or target.hp_fraction() >= Tuning.EXECUTE_HP_FRACTION:
		return 0
	return bonus

## Everything else a swing can set off, after it has been dealt `dealt` damage:
## stagger, mark and arc proc at Tuning.STAT_PROC_CHANCE; twin_strike and siphon
## roll their own percent. `enemies` is every living enemy, for arc's jump.
static func on_hero_swing(hero: Combatant, target: Combatant, dealt: int,
		enemies: Array[Combatant]) -> void:
	if not _is_live(hero) or not _is_live(target):
		return
	var id := hero.stats.id

	var stagger := GameState.hero_stat(id, &"stagger")
	if stagger > 0 and RNG.randf() < Tuning.STAT_PROC_CHANCE:
		# Pushes the target's next action back by a share of its own cooldown.
		# In turn-based mode a target already queued keeps its place.
		target.cooldown_remaining += target.stats.attack_cooldown * float(stagger) / 100.0

	var mark := GameState.hero_stat(id, &"mark")
	if mark > 0 and RNG.randf() < Tuning.STAT_PROC_CHANCE:
		target.apply_mark(mark)

	var twin := GameState.hero_stat(id, &"twin_strike")
	if twin > 0 and RNG.randf() < float(twin) / 100.0:
		_delayed_hit(hero, target, dealt, Tuning.TWIN_STRIKE_DELAY)

	var arc := GameState.hero_stat(id, &"arc")
	if arc > 0 and RNG.randf() < Tuning.STAT_PROC_CHANCE:
		var others: Array[Combatant] = []
		for e: Combatant in enemies:
			if _is_live(e) and e != target:
				others.append(e)
		if not others.is_empty():
			_delayed_hit(hero, others[RNG.randi_range(0, others.size() - 1)], arc, Tuning.ARC_DELAY)

	var siphon := GameState.hero_stat(id, &"siphon")
	if siphon > 0 and RNG.randf() < float(siphon) / 100.0:
		GameState.add_special_charge(id, 1)

## A follow-up hit that lands `delay` seconds later, if both sides still stand.
static func _delayed_hit(hero: Combatant, target: Combatant, amount: int, delay: float) -> void:
	await hero.get_tree().create_timer(delay).timeout
	if _is_live(hero) and _is_live(target):
		target.take_damage(amount, hero)

# --- the armor stats, on a hero taking a hit ---------------------------------

## Reads the armor stats off a hero's gear onto the Combatant, so a hit does not
## rescan the inventory. Called from Combatant.apply_party_bonuses, which runs
## on every equipment change.
static func cache_on(hero: Combatant) -> void:
	var id := hero.stats.id
	hero.deflect_chance = minf(float(GameState.hero_stat(id, &"deflect")) / 100.0, Tuning.DEFLECT_CHANCE_CAP)
	hero.cover_fraction = minf(float(GameState.hero_stat(id, &"cover")) / 100.0, Tuning.COVER_FRACTION_CAP)
	hero.bulwark_pct = GameState.hero_stat(id, &"bulwark")
	hero.thorns = GameState.hero_stat(id, &"thorns")

## What actually reaches `victim` from a hit of `amount` by `source`, before
## armor. Returns -1 for a hit that never lands (deflect).
## - mark: an enemy carrying one takes its percent more from any hero.
## - deflect: a hero may ignore an enemy's hit outright.
## - cover: the ally with the most cover takes that share of an enemy's hit on
##   another hero, and `victim` keeps the rest. `redirected` is true on the
##   covered share itself, so a covered hit is never covered again.
static func incoming(victim: Combatant, amount: int, source: Combatant,
		redirected: bool, allies: Array[Combatant]) -> int:
	var from_hero := source != null and is_instance_valid(source) and source.is_hero
	var from_enemy := source != null and is_instance_valid(source) and not source.is_hero
	if not victim.is_hero:
		if from_hero and victim.mark_pct() > 0:
			return int(round(float(amount) * (1.0 + float(victim.mark_pct()) / 100.0)))
		return amount
	if not from_enemy:
		return amount
	if victim.deflect_chance > 0.0 and RNG.randf() < victim.deflect_chance:
		return -1
	if redirected:
		return amount
	var coverer: Combatant = null
	for a: Combatant in allies:
		if _is_live(a) and a != victim and a.cover_fraction > 0.0 \
				and (coverer == null or a.cover_fraction > coverer.cover_fraction):
			coverer = a
	if coverer == null:
		return amount
	var share := int(round(float(amount) * coverer.cover_fraction))
	if share <= 0:
		return amount
	coverer.take_damage(share, source, true)
	return amount - share

## `thorns`: a hero hit by an enemy hits back for its thorns. Sourceless, like a
## bleed tick, so it never crits and never feeds the slot's damage buffer.
static func after_hit(victim: Combatant, source: Combatant) -> void:
	if not victim.is_hero or victim.thorns <= 0:
		return
	if _is_live(source) and not source.is_hero:
		source.take_damage(victim.thorns, null)

## `bulwark`: a Block grant to `hero`, raised by its percent.
static func block_grant(hero: Combatant, amount: int) -> int:
	if not hero.is_hero or hero.bulwark_pct <= 0:
		return amount
	return int(round(float(amount) * (1.0 + float(hero.bulwark_pct) / 100.0)))

# --- resolve, at the start of a fight ----------------------------------------

## `resolve`: each hero starts a fight with its summed roll of special charge,
## capped like any charge (GameState.add_special_charge).
static func grant_resolve(heroes: Array) -> void:
	for h: Variant in heroes:
		var c := h as Combatant
		if _is_live(c):
			var charge := GameState.hero_stat(c.stats.id, &"resolve")
			if charge > 0:
				GameState.add_special_charge(c.stats.id, charge)

static func _is_live(c: Combatant) -> bool:
	return c != null and is_instance_valid(c) and c.is_alive()
