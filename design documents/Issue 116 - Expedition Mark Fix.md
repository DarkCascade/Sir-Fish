# Issue #116: selling a pre-quest item lets quest loot survive a wipe

Rough implementation steps. See the [issue](https://github.com/DarkCascade/Sir-Fish/issues/116)
for the full repro and impact; this doc is just the fix plan, not a rationale record (that's the
backlog doc, once this ships).

## Root cause

`GameState.start_expedition()` (`scripts/autoload/game_state.gd:1092`) snapshots
`_expedition_inventory_mark = inventory.size()`. Everything at index `>= mark` is treated as
"found this trip" by:

- `discard_expedition_loot()` (`game_state.gd:1191`)
- `_settle_expedition_loot()` (`game_state.gd:1251`)
- `expedition_items_held()` (`game_state.gd:1238`)

`remove_item()` (`game_state.gd:376`) does `inventory.remove_at(index)`, which shifts every
later item down one index — but never touches `_expedition_inventory_mark`. Selling a pre-quest
item (index `< mark`) at the quest's shop (`scripts/modals/shop_modal.gd` `_build_sell`, which
lists the whole inventory, not just this trip's loot) leaves the mark one too high, so one loose
found item ends up on the "pre-quest" side of the line and survives a wipe it should lose.

## Fix

In `remove_item()`, decrement the mark when the removed item was before it:

```gdscript
func remove_item(item: Item) -> void:
	var index := inventory.find(item)
	if index < 0:
		return
	if index < _expedition_inventory_mark:
		_expedition_inventory_mark -= 1
	inventory.remove_at(index)
	EventBus.item_removed.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())
```

This is the one-line fix the issue suggests, and it's correct for every other `remove_item()`
caller too (forge salvage, inventory management, etc.) — none of them are expedition-loot-aware,
so keeping the mark accurate on every removal is strictly safer than only patching the shop path.

The alternative the issue floats — tag expedition items instead of relying on position — is a
bigger change (touches `Item`, save format, every place that currently does the index-range
trick) and isn't needed to close this bug. Worth a backlog note if index-based tracking causes
another bug later, but not part of this fix.

## Steps

1. Apply the one-line guard in `remove_item()` above.
2. Add a regression case to `tests/test_quest_flow.gd`, alongside the existing
   `discard_expedition_loot` coverage (`tests/test_quest_flow.gd:18`):
   - Start an expedition holding N pre-quest items (mark = N).
   - Pick up a loose item (append to `inventory` past the mark, as the existing test already
     does with `found_loose`).
   - Call `GameState.remove_item()` on one of the pre-quest items (simulating the shop sell).
   - Assert `_expedition_inventory_mark == N - 1`.
   - Call `discard_expedition_loot()` and assert the loose item is gone (the bug's actual
     symptom).
3. Sanity-check the two other consumers of the mark aren't hit by any off-by-one from this
   change:
   - `_settle_expedition_loot()` — KEEP_HALF/DOUBLE counts on the Items reel.
   - `expedition_items_held()` — the "brought home" row.
   A manual quest run that sells a pre-quest item mid-quest and checks the Items reel count
   would cover this, but the automated test above should already catch a wrong mark.
4. Run `python tools/run_tests.py quest` (narrows to quest-flow suites) to confirm nothing else
   regresses, then the full `python tools/run_tests.py` before opening the PR.
5. PR description should `Closes #116`; the issue was pulled straight off the GitHub board, not
   the backlog doc, per [CLAUDE.md](../CLAUDE.md)'s "board is the source of truth" rule — no
   backlog doc entry is needed unless this fix changes a documented rule (it doesn't; the
   Town/Forge/Quest spec's "index >= mark = found this trip" invariant is being *restored*, not
   changed).
