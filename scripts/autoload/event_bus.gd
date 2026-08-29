extends Node
## EventBus — every cross-system message goes through here. No direct node-path
## lookups between the battle and the console (spec 3.4).
##
## Every signal here is emitted from another script, so GDScript's per-file
## UNUSED_SIGNAL check always fires on all of them. Suppressed for the whole
## file rather than per line.
@warning_ignore_start("unused_signal")

# --- Run flow ---
signal run_started()
signal encounter_started(index: int, def: EncounterDef)
signal encounter_resolved(index: int, def: EncounterDef)
signal travel_started()
signal travel_finished()
signal run_completed()
signal game_over()

# --- Combat ---
signal combat_started(heroes: Array, enemies: Array)
signal combat_ended(victory: bool)
signal combatant_spawned(c: Node)
signal combatant_attacked(attacker: Node, target: Node, amount: int)
signal combatant_damaged(target: Node, amount: int, previous_hp: int, new_hp: int)
signal combatant_healed(target: Node, amount: int)
signal combatant_died(c: Node)
signal hero_damage_dealt(amount: int)          # feeds the slot's rolling 3-hit buffer

# --- Economy / items ---
signal gold_changed(new_total: int, delta: int)
signal item_added(item: Item)
signal item_removed(item: Item)
signal party_bonuses_changed(bonuses: Dictionary)   # [v2] spec 13.5

# --- [town] spec 3.3. All five signal names landed in one edit at step 5.
# scrap_changed got its faucet at step 9 (GameState.add_scrap, from combat
# pickups); item_forged is emitted by Itemizer.forge() from step 9 too.
# quest_started / quest_finished are step 8: start_expedition() emits
# quest_started when a QuestDef is passed, and RunController's victory / failure
# flows emit quest_finished, which QuestResult listens for to route home and
# present (spec 8.5). quest_started tightened to QuestDef at step 8.
signal scrap_changed(new_total: int, delta: int)
signal item_equipped(item: Item, hero_class: StringName, slot: int)
signal item_forged(item: Item, new_rarity: int)
signal quest_started(quest: QuestDef)
signal quest_finished(victory: bool)

# --- Console ---
signal slot_spin_started()
signal slot_spin_stopped(symbols: Array)       # Array[int] of 3 Tuning.Sym values
signal slot_payout(kind: String, count: int)   # kind in "lightning"|"gold"|"heal"
signal upgrade_purchased(id: StringName, new_level: int)   # [v2] spec 17.6
