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

## Optional: Jev sanity-check gate

[Jev](https://docs.typesafe.ai) (TypeSafe's "System One" model) isn't used anywhere else in this
project yet, and this bug has no place for it in the actual code change — the fix is a
deterministic off-by-one on an array index, not a judgment call, so it doesn't need a
probabilistic model to make it. Noting it here only because it was asked for; treat it as an
optional extra gate before opening the PR, never a substitute for step 2's regression test.

Jev's own guidance is to keep questions atomic (`Choice` / `Score` / `Noul`) and compose them in
application code rather than asking one compound question. The one place that fits is a `Noul`
(yes/no, 0–1) pre-merge check on the diff, run alongside `tools/run_tests.py`:

> **Noul**: "Does this diff keep `_expedition_inventory_mark` equal to the number of inventory
> entries that existed before `start_expedition()` was called, after any `remove_item()` call?"
> — state: the diff to `remove_item()` plus the surrounding `game_state.gd` context.

A low/uncertain score would be a signal to re-read the diff by hand, not a merge blocker — this
project has no Jev API wiring (no SDK, no credentials, no CI step) today, so this is a sketch, not
a ready-to-run script. Standing this up for real means deciding on a client library and where the
call lives (a `tools/` script vs. a CI step), which is a separate decision from this bug fix and
shouldn't block it.
