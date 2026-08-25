# Recap: Pause an attack while a target has an incoming hit in flight

## Goal
Prevent a combatant from starting its own action (and, for melee, blinking into the enemy
rank) while a ranged attack (arrow/bolt) already fired at it hasn't landed yet.

## Status
Already implemented in the working tree, uncommitted, on branch `move-elements-to-editor`.
No code changes were needed this session — verified the prior session's work is complete
and functioning.

## What's in place

### `scripts/battle/combatant.gd`
- New field: `incoming_attacks: int = 0` — count of in-flight projectiles/bolts currently
  targeting this combatant. Reset to `0` in `setup()`.
- `is_expecting_attack() -> bool` — `incoming_attacks > 0`.
- `begin_incoming_attack()` — increments the counter.
- `end_incoming_attack()` — decrements, clamped at `0`.

### `scripts/battle/battle_director.gd`
- **Real-time mode** (`request_turn()`): if the requesting combatant `is_expecting_attack()`,
  bail out without acting. The per-frame loop calls `request_turn()` again next frame (cooldown
  stays expired, state stays `IDLE`), so it retries naturally until the incoming hit lands or
  the combatant dies.
- **Turn-based mode** (`_advance_turn_queue()`): when the front-of-queue combatant
  `is_expecting_attack()`, it's held in place (not popped) instead of being dispatched. A dead
  or freed combatant at the front is still popped and discarded as before.

### `scripts/battle/projectile.gd` (ranger's arrow / bomb arrow)
- `launch()` calls `target.begin_incoming_attack()` right after locking in the target.
- `_impact()` calls `target.end_incoming_attack()` before resolving damage/explosion, guarded
  only by `is_instance_valid` (not `is_alive`), so the counter still clears correctly if the
  target died from another source mid-flight.

### `scripts/battle/magic_bolt.gd` (mage's primary)
- Same pattern: `begin_incoming_attack()` on `launch()`, `end_incoming_attack()` at the top of
  `_impact()`.

## Verification performed
- **Diff review**: confirmed every `begin_incoming_attack()` call has a matching
  `end_incoming_attack()` on the same object, including the target-died-mid-flight edge case.
- **`validate_script`**: flagged "Class X hides a global script class" on all four touched
  scripts — this is a known false positive from validating a script that already owns its
  `class_name` globally, not a real compile error.
- **Live playtest**: ran a full playthrough via `play_scene` (turn-based combat is the default,
  `turn_based_combat = true`) through several real encounters — arrows and bolts fired and
  landed, party took real damage (1102 total across the run) — through to a run-ending defeat
  screen. `get_editor_errors` showed no errors from the new code (only a pre-existing, unrelated
  unused-variable warning in `overworld_field.gd`).
- Attempted to catch the "held at front of queue" moment live via `monitor_properties`, but
  polling over MCP round-trips wasn't fast enough to reliably line up with a ~0.5s projectile
  flight. Not pursued further given the clean diff and error-free full-run playtest.

## Outstanding
- Nothing left to implement — the feature is functionally complete.
- Not yet committed to git.
