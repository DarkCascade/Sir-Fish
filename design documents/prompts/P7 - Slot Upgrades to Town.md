# Prompt — Move the three slot upgrades into town

**Context:** backlog P7 (`design documents/Sir Fish - Backlog.md` §7), decision 7.5.
**Branch at time of writing:** `backlog-p3`, head `5449e21`.

The console's bottom band (the upgrade tray) is to become the three **special invoker**
buttons. The three slot upgrades that live there now move into town. This task is the
move; the invoker tray is a separate task that depends on it.

---

## Why they are moving rather than being deleted

Keeping them preserves two things the game would otherwise lose:

- **The only run-scoped gold sink.** Expedition gold currently has nowhere else to go
  mid-run.
- **`polish`, a balance lever the harness reads.** It removes blanks from the slot bag
  (`SLOT_BLANK_PAD_START` 9 → floor 3, 2 per level), which changes board density and
  therefore party DPS. `tests/test_level_curves.gd` models the bag.

---

## What exists

### `scripts/autoload/upgrades.gd` (the autoload)

```
DEFS   = { quick_reels, overcharge, polish }   # name + blurb + base cost
ORDER  = [&"quick_reels", &"overcharge", &"polish"]   # display order
levels = { quick_reels: 0, overcharge: 0, polish: 0 }
level(id) / is_maxed(id) / cost(id) / buy(id) / reset()
quick_reels_mult() / overcharge_mult() / polish_blanks_removed() / next_effect_percent(id)
```

Four levels each (`Tuning.UPGRADE_MAX_LEVEL`). `buy()` spends gold, bumps the level,
increments `run_stats["upgrades_bought"]` and emits `EventBus.upgrade_purchased(id, level)`.
Its header states the design stance explicitly: **run-scoped, no meta-progression, "spec
5.4 is explicit that these are NOT the forge."** Preserve that stance — moving the
purchase point to town must not quietly turn them into permanent upgrades.

`levels` is **not saved** (`save_game.gd` has no key for it), the same stance
`GameState.special_charges` takes.

### Consumers

| Reader | What it uses |
|---|---|
| `scripts/console/slot_machine.gd:289` | `polish_blanks_removed()` → `_blank_pad()` |
| `scripts/console/slot_machine.gd:325` | `quick_reels_mult()` → spin cycle |
| `scripts/console/slot_machine.gd:391` | `overcharge_mult()` → damage icons |
| `scripts/autoload/debug.gd:305,309,516` | a debug command that sets levels, and a state dump |
| `scripts/console/upgrade_button.gd` | the card UI |

### UI being moved

- `scenes/console/upgrade_tray.tscn` + `scripts/console/upgrade_tray.gd` — three
  authored card instances, paired with `Upgrades.ORDER` in child order, re-heighted by
  the console.
- `scenes/console/upgrade_button.tscn` + `scripts/console/upgrade_button.gd` — one card:
  parchment face, medallion, blurb, **a procedurally drawn pip row** (`_draw_pips`,
  driven by `UPGRADE_MAX_LEVEL`), a price plate, and a gold-vine rim that swaps for the
  boss theme.
- `scripts/console/console.gd` positions the tray (`upgrade_tray.position` /
  `apply_height`) and fans the boss theme to it (`apply_boss_theme` / `clear_boss_theme`).

---

## THE TRAP — read this before anything else

`GameState.start_expedition()` calls **`Upgrades.reset()`** (currently
`scripts/autoload/game_state.gd:1106`, immediately above the `special_charges.clear()`
added for P7).

So with purchases moved to town, the sequence becomes: *player buys in town → departs →
`start_expedition()` wipes everything they bought.* The purchase must survive departure.

Move the reset to the **end** of a run instead of the start. Candidates, pick after
reading each: `RunController._run_complete()` and its wipe counterpart, or
`GameState.reset_run()`, or a `quest_finished` listener. Requirements:

- Buying in town then departing keeps the levels.
- Levels are cleared once, at the end of that expedition, whether it is won or lost —
  a wipe must not let a player keep four levels of Polish for free.
- `new_profile()` clears them (verify — it may currently rely on `start_expedition`).
- The stance holds: **nothing persists across expeditions.**

Write a test for exactly this sequence before you change the call site. It is the whole
risk in this task and nothing currently covers it — `tests/test_upgrades.gd` asserts
`reset()` clears, but never that a purchase survives a departure.

---

## Where in town

`SceneRouter.Place` = `TOWN, INN, BLACKSMITH, MAYOR, QUEST, ITEM_FORGE`, with
`PATHS` in `scripts/autoload/scene_router.gd`. `tests/test_scene_router.gd` asserts
every `Place` has a path (totality), so a new Place needs a scene and an entry.

Three options, in rough order of effort:

1. **Fold into an existing screen.** The blacksmith is the natural home (it already
   sells and forges, has tab structure, currency listeners and card rows). Cheapest, and
   no `Place` churn. Risk: the blacksmith is already busy — Forge / Buy / Scrap / Sell.
2. **A new `Place`.** A dedicated screen ("the cabinet mechanic"?), a town button, a
   path entry, a back button. Cleanest conceptually, most work, and needs art direction
   for another town location.
3. **The inn.** Thematically odd but it is the quiet pre-departure screen, which is when
   these are bought.

**Recommendation: option 1**, as a fourth blacksmith tab, because the card UI is already
built and the blacksmith already owns "spend currency between runs". Confirm with the
user if you disagree — this is a design placement question, not purely mechanical.

Whatever you choose, the cards should reach town **largely unchanged**. `upgrade_button.gd`
carries a note that its layout was measured off a concept board; re-fitting it to a
different container is the visible-work part of this task. It also has boss-theme
methods (`apply_boss_theme` / `clear_boss_theme`) that are meaningless in town — leave
them callable but unused, or strip the call sites in `console.gd` only.

---

## Acceptance

1. **The three upgrades are purchasable in town** and no longer on the console.
2. **`Upgrades.reset()` moved off `start_expedition()`**, with a test proving buy →
   depart → still bought, and end-of-run → cleared, for both victory and wipe.
3. **The console's bottom band is freed** — `console.gd` no longer positions the tray.
   Leave the band empty or collapsed; the invoker tray is a separate task, so do not
   build it here. Note what you did to `STRIP_HEIGHT` / `slot_h` / `tray_h` maths in
   `console.gd:_layout()` so the next task can reuse the space.
4. **`tests/test_upgrades.gd` still passes** (57 checks: the cost curve against spec
   17.6's table, `is_maxed`, every derived multiplier, `reset()`).
5. **`tests/test_scene_router.gd` passes** — totality, if you added a `Place`.
6. **`tests/test_level_curves.gd` passes** — it reads `SLOT_BLANK_PAD_START`; if
   `polish` becomes reachable at a different point in the run, nothing about the bag
   maths changes, but re-run it to be sure.
7. **Full suite green:** `python tools/run_tests.py`.
8. **Looked at in the running game**, not just headless: the town screen with the three
   cards, and the console with its band freed.

---

## Traps

- **The reset trap above is the whole task.** Everything else is a UI move.
- `debug.gd` has an upgrade command (`Upgrades.levels[id] = level`) and a state dump —
  both keep working, but check the command's help text if it says "slot upgrades".
- The upgrade cards are authored as **instances in `upgrade_tray.tscn`**, not spawned in
  code ("move-elements-to-editor"). Moving them means moving authored nodes, not
  rewriting a spawn loop.
- **Do not save `.tscn` through the editor** — edit on disk, then reload. The editor
  reformats and strips `;` comments.
- **`godot --headless --path . --import` strips the three MCP addon autoloads from
  `project.godot`.** If you reimport, `git checkout project.godot` straight after.
- `Upgrades` is an autoload; adding or removing one requires `set_project_setting` or
  the MCP tool, never a hand edit of `project.godot`. This task should need neither.
- Gold is earned mid-expedition but would now be spent in town — check that the loop
  still makes sense, i.e. that the player returns to town with gold and a reason to
  spend it before departing again. Flag it if the pacing reads wrong; it is a design
  consequence of decision 7.5 worth reporting back rather than silently absorbing.
