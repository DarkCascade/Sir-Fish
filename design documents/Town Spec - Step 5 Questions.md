# Town Spec — Step 5 Implementation Questions

Raised while preparing §14 step 5 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("**§3 — `SceneRouter` and `Hud`**, `boot.tscn`,
`RunSummary` → `QuestResult` moved into the HUD. The forest still starts, now
via the router. **Read §3.1's `RunController._start_run()` warning before
starting this step.**").

Step 5 is the **first player-visible step** — a new main scene, a persistent
overlay, a scene router — but §14 still requires it to leave the game runnable,
and the game it has to leave runnable is a half-built one: the town buttons are
dead until step 7 and the mayor's quest hand-off does not exist until step 8.
Most of the questions below are about that gap — what "the forest still starts"
actually means six sections before §7.5 exists to start it.

**One is a place the spec is wrong, not merely silent.** §3.1 says
`_start_run()` "**drops the `reset_run()` call**". Taken literally that deletes
endless mode's only reset and null-derefs `GameState.level` on every path that
reaches `_start_run()` without a prior `start_expedition()` — which at step 5 is
*every* path, and after step 8 is still the endless/dev path and
`test_endless_level_gen.gd`. The call must be **guarded**, not dropped (Q1).

**Answers pending.** Each question below carries a recommendation; nothing here
is a design fork (§0.4 settled the router, the HUD and the profile split). These
are implementation gaps: names §3 uses without defining, wiring §3.2 removes
without saying what replaces it at this step, and ordering hazards between two
new autoloads and a save file that now loads on boot.

| Q | gap | recommendation | spec |
|---|---|---|---|
| Q1 | §3.1 "drops the `reset_run()` call" null-derefs `level` | guard it: `if GameState.quest == null: reset_run()` — a no-op at step 5, correct for endless retry, correct at step 8 | §3.1, §14 step 5 |
| Q2 | §3.2 "RunController no longer wires" QuestResult — but nothing else does until step 8 | RunController keeps the two `present()` calls and repoints `_on_retry` to `dismissed`; "no longer owns/wires" is the step-8 end state | §3.2, §8.5 |
| Q3 | rename scope of `RunSummary` → `QuestResult` | `git mv` script + scene, rename node + signal, fix `console.gd:8`; `present()` API unchanged this step | §3.2 |
| Q4 | autoload names, order, and the safety lint | `SceneRouter` (script) then `Hud` (scene) after `SaveGame`; keep both `_ready`/`_init` free of sibling-autoload identifiers | §3.1, §13.3 |
| Q5 | `CurrencyPlate` never sees the loaded profile | `boot.gd` emits `gold_changed` / `scrap_changed` after load / `new_profile()` | §3.1, §3.3 |
| Q6 | add which `EventBus` signals now | all five §3.3 signals in one edit | §3.3 |
| Q7 | `SceneRouter.go()` swap mechanism | `change_scene_to_file()` + `await tree_changed`, re-entrancy-guarded; boot's first hop un-faded | §3.1 |
| Q8 | `SceneRouter.place` stale on direct-scene launches | every routed scene sets `place` in its own `_ready` | §3.1, §3.2 |
| Q9 | what `InventoryButton` does with no modal yet | ship it, `disabled = true`, wire the COMBAT rule now; step 6 adds the open call | §3.2 |
| Q10 | `Transition` `ColorRect` input + z-order + headless render tests | invisible + `mouse_filter = IGNORE` at rest, topmost child of `Hud` | §3.2, §13.3 |
| Q11 | `boot.tscn` as `main_scene` — the fallout | `set_project_setting`; `play_scene`/F5 now land in TOWN; test `.tscn`s unaffected | §3.1, §14 step 5 |
| Q12 | debug verbs to reach the forest by hand | add `route` and `wipe` now; `quest` / `scrap` / `forge` stay with their sections | §13.4 |
| Q13 | does step 5 ship a pinning test, per steps 1–4 | small `test_scene_router.gd`: PATHS totality, path existence, boot-fallback saves once | §13, step-1 Q5 |

---

## Q1. §3.1 says `_start_run()` "drops the `reset_run()` call" — it must be guarded, not dropped

§3.1, the blocking warning §14 step 5 tells the implementer to read first:

> `_start_run()` drops the `reset_run()` call and assumes `GameState.level` is
> already built — which it is, because §7.5 calls `start_expedition(quest)`
> *before* routing to `Place.QUEST`.

`§7.5` is **step 8**. At step 5 there is no mayor's office and nothing calls
`start_expedition()` on the way into the forest. Every route that reaches
`RunController._ready()` → `_start_run()` — a direct `main.tscn` launch, a debug
`route quest` (Q12), `boot` → `Place.QUEST` if anyone wires it — arrives with
`GameState.level` still `null`, and `_start_run()`'s very next line after the
dropped reset is `director.spawn_party()` then `_next_encounter()`, whose first
read is `GameState.level.encounters.size()` (`run_controller.gd:67`). Null
deref, hard crash, on the step whose bar is "leaves the game runnable".

And it does **not** become safe at step 8 either. Endless mode is still
`default-true` on `GameState` (§13.3), still reached by launching `main.tscn`
directly and by `test_endless_level_gen.gd` calling `reset_run()`. Those paths
have no `start_expedition()` in front of them, ever. "Drops the call" is only
sound for the *routed quest* path, which is one of three.

There is also a second bug in the literal reading: `_on_retry()`
(`run_controller.gd:289`) calls `_start_run()` again after a wipe, and endless
retry needs a **full** `reset_run()` — `GameState.level` is still non-null from
the dead run, so a `level == null` guard would skip the reset and respawn onto
stale state.

### Recommendation — guard on `quest`, not on `level`

**SUPERSEDED by §3.1 / I2 — the shipped guard is `level == null`.** The
diagnosis below (guard the call, do not drop it) stands; this specific
predicate does not, because `route quest` leaves `quest` null and `level` set.

```gdscript
func _start_run() -> void:
    if GameState.quest == null:
        GameState.reset_run()          # endless / dev entry point (§3.1)
    director.spawn_party()
    ...
```

- **At step 5** `GameState.quest` is always `null` (nothing assigns it until
  §7.5 at step 8), so this is byte-for-byte today's behaviour — `main.tscn`
  still launches straight into an endless forest, and a debug `route quest`
  (Q12) lands there too. "The forest still starts" is satisfied without a
  mayor.
- **On endless retry** `quest` is `null` → full `reset_run()`, unchanged.
- **At step 8** the mayor sets `GameState.quest` before routing, so `_start_run`
  skips the reset and the profile `boot.tscn` loaded survives — which is
  §3.1's / step-2 Q4's whole point, achieved by a guard rather than by a
  deletion that step 8 would have to partially walk back.

This is the same predicate `build_level()` already dispatches on (§8.3:
`if quest != null: return _build_quest_level(quest)`), so it introduces no new
concept. §3.1 and §14 step 5 should say "**guards** the `reset_run()` call
behind `GameState.quest == null`", and the "assumes `GameState.level` is already
built" sentence should be scoped to the routed path explicitly.

---

## Q2. §3.2 removes RunController's QuestResult wiring — what shows the ending screen between step 5 and step 8?

§3.2:

> **`RunSummary` moves out of `main.tscn` into `Hud/ModalLayer`** and is renamed
> `QuestResult` (§8.5). Its `retry_pressed` signal becomes `dismissed`;
> `RunController` no longer owns it or wires it.

But `RunController` is the only thing that presents it. Today:

| line | call |
|---|---|
| `run_controller.gd:33` | `run_summary = main.get_node("ModalLayer/RunSummary")` |
| `run_controller.gd:46` | `run_summary.retry_pressed.connect(_on_retry)` |
| `run_controller.gd:276` | `run_summary.present(true)` — `_run_complete()` (dead code until step 8, §8.3) |
| `run_controller.gd:285` | `run_summary.present(false)` — `_game_over()` |

§8.5 (step 8) is where the new flow lands: `_run_complete()` /
`_game_over()` call `SaveGame.save_profile()`, `await SceneRouter.go(...)`, then
`Hud.quest_result.present(...)` and route on `dismissed`. Nothing between step 5
and step 8 fills that gap. If step 5 takes "no longer wires it" literally, a
party wipe in endless mode (`_game_over()`) fades nothing, connects nothing, and
the run just stops — arguably still "runnable", but a visible regression for
six commits.

### Recommendation — keep the two `present()` calls; repoint retry to `dismissed`

Step 5's edit to `RunController` is purely a **reference swap plus a signal
rename**, not a flow change:

- delete `run_controller.gd:33` (`main.get_node("ModalLayer/RunSummary")`);
  reach the node as `Hud.quest_result` at the two call sites (§8.5's own
  accessor, available early);
- `run_controller.gd:46` becomes
  `Hud.quest_result.dismissed.connect(_on_retry)` — endless retry survives as
  the dev path until §8.5 replaces `_on_retry` with the route-home flow;
- `_run_complete()` / `_game_over()` keep calling `present(true/false)`
  unchanged. The **Quest Reward** row, the expedition-gold/scrap rows and the
  "Retire for the evening" / two-recovery-button variants are all §8.5 — step 5
  ships `present()` exactly as `run_summary.gd:26` has it today.

Read "`RunController` no longer owns it or wires it" as the **step-8 end
state**: once §8.5 lands, the ending flow lives in `_run_complete()` /
`_game_over()` driving `SceneRouter` + `Hud`, and the `_on_retry` connection is
gone. Step 5 is the relocation; step 8 is the rewiring. §3.2 should say so, the
way §3.1 already scopes its warning to "the step where a leftover `reset_run()`
… stops being harmless".

---

## Q3. `RunSummary` → `QuestResult`: the full rename surface

`grep -rn "RunSummary\|run_summary\|retry_pressed" scripts/ scenes/ tests/`:

| ref | change |
|---|---|
| `scenes/modals/run_summary.tscn` (file) | → `scenes/modals/quest_result.tscn` (`git mv`) |
| `scripts/modals/run_summary.gd` (file) | → `scripts/modals/quest_result.gd` (`git mv`) |
| `run_summary.tscn` root node `RunSummary` | → `QuestResult` |
| `run_summary.gd:11` `signal retry_pressed()` | → `signal dismissed()` |
| `run_summary.gd:22-23` `retry_pressed.emit()` | → `dismissed.emit()` |
| `run_summary.gd:4` header comment | reword |
| `scenes/main.tscn:8,90` — `ext_resource` + `RunSummary` node under `ModalLayer` | **removed** from `main.tscn`; instanced under `Hud/ModalLayer` instead |
| `scripts/console/console.gd:8` — comment "the run summary still shows him (`run_summary.gd`)" | update path/name |
| `run_controller.gd:21,33,46,276,285,289` | Q2 |

No test references it (grep is clean). No `class_name`. The `.gd`'s `@onready`
node paths (`$Scrim`, `$Panel/Layout/...`) are internal and unaffected by the
reparent.

### Recommendation — do the whole rename in step 5, `git mv` both files

It is bounded (one scene, one script, one `main.tscn` node, one stale comment,
the `RunController` refs from Q2) and the compiler plus the clean test grep
catch every miss. Deferring the file rename to step 8 "when the API changes
anyway" just means step 8 touches `main.tscn` *and* renames files *and* rewrites
the flow in one commit. `present(victory: bool)` keeps its exact current
signature — everything §8.5 adds to it is step 8.

---

## Q4. Two new autoloads: names, registration order, and the safety lint

§3.1 registers `SceneRouter`; §3.2 registers `Hud` pointing at
`scenes/hud/hud.tscn`. §2.4's rule ("registered **after** `GameState` … via
`set_project_setting`, never edit `project.godot` by hand") applies to both.
Current list ends `… Upgrades, Debug, SaveGame` (`project.godot:19-29`).

Two hazards:

**Order.** `SceneRouter.go()` fades "through Hud's transition rect" — a runtime
call through `/root/Hud`, so registration order does not gate correctness, but
freeing order is LIFO: whichever is registered *last* is freed *first*. `Hud`
holds nodes `SceneRouter` never needs during teardown; `SceneRouter` holds only
an enum and a `place` int. Register **`SceneRouter` then `Hud`**, both after
`SaveGame`, so `Hud` (the heavier one, and the one `SceneRouter` calls into)
outlives `SceneRouter`.

**`test_autoload_safety.gd` (§13.3, no edits).** It is a source lint: for every
non-`MCP*` autoload it reads the script at `autoload/<Name>`, isolates
`_ready()` / `_init()` bodies, and fails if another autoload's identifier
appears there.

- `SceneRouter` is a `.gd` autoload → **scanned**. Keep its `_ready`/`_init`
  empty or free of `EventBus` / `GameState` / `Hud` / … identifiers. `go()` is
  not a lifecycle method, so its `Hud` reference is fine.
- `Hud` is a **scene** autoload → the lint opens `hud.tscn` as text, finds no
  top-level `func _ready(`, and scans an empty body. So `hud.gd`'s actual
  `_ready()` is **not covered by this lint at all.** That is a real gap, not a
  free pass: the "inert when instantiated headless" guarantee (§3.1) for `Hud`
  rests entirely on the full `--headless --quit-after` boot check, so run it.
- `t.check(autoloads.size() >= 6 …)` — still true at 13. No edit.

### Recommendation

Names `SceneRouter` / `Hud` as written. Registration order:
`… SaveGame, SceneRouter, Hud`. `hud.gd`'s root `_ready()` does **no**
sibling-autoload work — `CurrencyPlate` binds `EventBus.gold_changed` /
`scrap_changed` in *its own* script (a child node, not scanned, and the right
home for it anyway). If `hud.gd` genuinely needs a sibling at boot, `call_deferred`
it. Note the scene-autoload lint gap in §13.3 or step-5 ship notes so it is not
mistaken for coverage later.

---

## Q5. `CurrencyPlate` binds `gold_changed` / `scrap_changed` but never sees the loaded profile

Autoloads `_ready()` before the first scene. So `Hud._ready()` — and
`CurrencyPlate._ready()` under it — runs **before** `boot.gd` calls
`SaveGame.load_profile()`. `load_profile()` (§2.4) assigns `GameState.gold` /
`scrap` silently; the only thing that emits `gold_changed` is
`start_expedition()` (`game_state.gd:544`), which the boot → TOWN path never
calls. Result: the HUD plate reads the *default* 150 / 0 on `_ready`, the real
save loads a moment later, and nothing tells the plate to repaint. The player
sees the wrong balance in town until the first thing that happens to emit a
currency signal.

`status_panel.gd`'s `GoldPlate` has the same shape but is masked — it only
exists in `Place.QUEST`, where `start_expedition()` fires `gold_changed` on the
way in.

### Recommendation — `boot.gd` emits after the profile is settled

Mirror `start_expedition()`'s tail: once `boot.gd` has either loaded a profile
or fallen back to `new_profile()` (+ saved, §3.1), before routing:

```gdscript
EventBus.gold_changed.emit(GameState.gold, 0)
EventBus.scrap_changed.emit(GameState.scrap, 0)
```

`CurrencyPlate` reads `GameState.gold` / `scrap` directly in its own `_ready()`
as the first paint, then trusts the signals. A dedicated
`EventBus.profile_loaded` would work too but is a new concept for one caller;
the two zero-delta emits are the established pattern (`game_state.gd:544`) and
`_float_delta`-style feedback correctly shows nothing for a `delta` of 0.

---

## Q6. Which of §3.3's `EventBus` signals land at step 5?

§3.3 adds five:

```gdscript
signal scrap_changed(new_total: int, delta: int)
signal item_equipped(item: Item, hero_class: StringName, slot: int)
signal item_forged(item: Item, new_rarity: int)
signal quest_started(quest: QuestDef)
signal quest_finished(victory: bool)
```

Only `scrap_changed` has a step-5 consumer (`CurrencyPlate`, Q5).
`item_equipped` is step 6, `quest_started` / `quest_finished` are step 8,
`item_forged` is step 9 — though step-3 Q1's dependency table already records
`item_forged` as "arrived at step 5", so `forge()` at step 9 can assume it.

`event_bus.gd:8` is `@warning_ignore_start("unused_signal")` for the whole file,
so a declared-but-unemitted signal is already silent.

### Recommendation — all five, one edit

§3.3 is written as a unit and the file is already set up to carry unused
signals. Adding them one-per-consuming-step is five separate one-line diffs to
`event_bus.gd` across steps 5/6/8/9 with no benefit. `QuestDef` does not exist
until step 8, so `quest_started(quest: QuestDef)` must be typed
`quest_started(quest)` (untyped) or `quest_started(quest: Resource)` until then
— recommend untyped now, tighten to `QuestDef` in step 8 alongside the class.

---

## Q7. `SceneRouter.go()` — the actual scene-swap

§3.1 gives only the signature and intent:

> Fades through Hud's transition rect, swaps the scene, fades back. `await`able
> so a caller can present a modal only once the destination is actually up
> (§8.5's failure flow depends on that ordering).

Unspecified: how the swap happens, and what "the destination is actually up"
means concretely.

### Recommendation — `change_scene_to_file()`, awaited on `tree_changed`

**Amended by I1** — `boot.gd`'s direct hop needs `await
get_tree().process_frame` in front of it; it cannot swap the scene from inside
that scene's own `_ready()`.

```gdscript
var _routing := false

func go(to: Place) -> void:
    if _routing or to == place:
        return
    _routing = true
    var rect := Hud.transition          # the ColorRect (Q10)
    rect.mouse_filter = Control.MOUSE_FILTER_STOP
    var fade_in := create_tween()
    fade_in.tween_property(rect, "modulate:a", 1.0, 0.18)
    await fade_in.finished
    get_tree().change_scene_to_file(PATHS[to])
    await get_tree().tree_changed        # the swap is deferred to frame end
    await get_tree().process_frame       # let the new scene _ready() settle
    place = to
    var fade_out := create_tween()
    fade_out.tween_property(rect, "modulate:a", 0.0, 0.18)
    await fade_out.finished
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _routing = false
```

- `change_scene_to_file()` keeps autoloads (`Hud`, and the `Transition` rect
  under it) alive and frees the old `current_scene` for us — the hand-rolled
  add/remove alternative gains nothing here.
- The re-entrancy guard matters: `SceneRouter.go()` is `await`able and called
  from `await`ing flows (§8.5), so a second `go()` mid-transition must be
  ignored, not queued.
- `boot.gd`'s first hop (boot → TOWN) can call `go()` too, but with the rect
  already opaque (boot is a black screen) — or `boot.gd` can
  `change_scene_to_file` directly and just set `SceneRouter.place = Place.TOWN`.
  Either is fine; recommend the direct call so `go()` never runs with a
  half-initialised `Hud`.

Confirm the ~0.18 s fade timing (no `Tuning` constant is specified for it) and
whether `place` should update before or after the fade-out (before, so
`_ready()` in the new scene reads the correct `place` — see Q8).

---

## Q8. `SceneRouter.place` is wrong whenever a scene is launched directly

`place` defaults to `Place.TOWN`. A dev pressing F5 on `main.tscn`, or the MCP
`play_scene` on it, is in `Place.QUEST` with `place` still saying `TOWN`. §3.2's
rule — "During `Place.QUEST` the button is … disabled while
`RunController.state == COMBAT`" — reads `SceneRouter.place`, so on a direct
launch the InventoryButton's disable logic is driven off a lie.

### Recommendation — each routed scene asserts its own `place` in `_ready()`

`town.gd`, `inn.gd`, … set `SceneRouter.place = Place.<self>`; `RunController`
(or `main_layout.gd`) sets `SceneRouter.place = Place.QUEST`. Idempotent with
`go()` setting it, costs one line per scene, and makes every entry path —
routed, F5, `play_scene`, a future deep-link — self-consistent. At step 5 only
`town.gd` (step 7) and `RunController` exist to carry it; add the `RunController`
line now, since QUEST is the only place directly launched today.

---

## Q9. What does `InventoryButton` do at step 5?

§3.2 puts `InventoryButton` and `CurrencyPlate` on the HUD "visible in every
`Place`" from this step. But `InventoryModal` is §6 — step 6. At step 5 the
button has nothing to open.

### Recommendation — ship it visible and `disabled = true`, wire the COMBAT rule now

- The button exists in `hud.tscn` with the backpack-icon placeholder (real icon
  is §12, step 11 — it renders as a missing-texture or a temporary label until
  then), `disabled = true`, with an inline
  `# step 6 (§6): pressed -> Hud.inventory_modal.open()`.
- Implement §3.2's visibility policy now: `disabled` also driven by
  `SceneRouter.place == Place.QUEST and RunController.state == COMBAT`. Step 6
  then only has to add the `pressed` handler — the "when is it usable" logic is
  already correct and tested by hand at step 5.

Hiding it entirely until step 6 is the alternative, but §3.2 explicitly wants
the HUD chrome on screen from step 5 ("the inventory button needing to exist in
both town and forest scenes" is one of the three problems the HUD node is
introduced to solve).

---

## Q10. `Transition` `ColorRect`: input, draw order, and the headless render tests

§3.2: "`Transition` — a full-screen `ColorRect` for `SceneRouter.go()`." A
full-screen `ColorRect` on a `CanvasLayer` at layer 10 that defaults to
`visible = true` / opaque / `MOUSE_FILTER_STOP` would:

- eat every click in town and forest (it is above everything);
- cover the frame in `test_parallax_seam.gd` / `test_damage_chunk.gd` — both on
  §13.3's **no-edit** list — if either inspects rendered output while the `Hud`
  autoload is loaded.

### Recommendation

`Transition` ships `modulate:a = 0.0` (or `visible = false`, toggled on in
`go()`), `mouse_filter = MOUSE_FILTER_IGNORE` at rest, `STOP` only for the
duration of a transition (Q7). It is the **last** child of `Hud` so a fade
covers an open modal too (routing while a modal is open should not happen, but
the fade should win if it does). Confirm colour — black is the safe default;
§8.5's "fade back once the destination is up" reads as a plain dip to black, not
a themed wipe.

---

## Q11. `boot.tscn` becomes `application/run/main_scene` — the fallout

§3.1: "`res://scenes/main.tscn` stops being the project's main scene. A new
`res://scenes/boot.tscn` becomes it."

Consequences worth stating in the ship notes, none blocking:

- **Set it with `set_project_setting`**, not by editing `project.godot:14` by
  hand (CLAUDE.md).
- **`play_scene` / F5 with no argument now boot into `Place.TOWN`** — a town
  with dead buttons until step 7. Every "run the game" reflex (dev, MCP agent)
  lands there instead of the forest. This is why Q1's guard and Q12's `route`
  verb matter: without them the forest is unreachable by the default run
  action for three commits.
- **Test `.tscn`s are unaffected** — they set themselves as the scene under
  `--path … res://tests/<name>.tscn`. `test_endless_level_gen.gd` calls
  `reset_run()` directly with no scene load, so it is untouched.
- **`boot.gd` is a scene script, not an autoload** — it is free to call
  `SaveGame`, `GameState` and `SceneRouter` directly in `_ready()` (the
  `test_autoload_safety` lint only scans autoloads).

### Recommendation

`set_project_setting("application/run/main_scene", "res://scenes/boot.tscn")`,
and record the `play_scene`-lands-in-town change in "What step 5 ships" the way
step 3 recorded its "nothing should move" notes — it is a surprise otherwise.

---

## Q12. Debug verbs to reach the forest (and wipe the save) by hand

§13.4 lists `scrap <n>`, `forge <slot>`, `quest <easy|medium|hard>`, `town`,
`wipe` with **no step assigned**, and step 4 added none. Two of them are
step-5-shaped:

- **`town`** (route to town) needs only `SceneRouter` — available at step 5.
- **`wipe`** (delete the save, start a new profile) becomes *meaningful* at step
  5: this is the first step where `boot.tscn` reads `user://profile.save`, so a
  stale dev save now actually affects a launch. §3.1 calls `reset_run()` "a dev
  path that wipes the profile … precisely what §13.4's `wipe` verb wants."

`quest` needs `QuestDef` + `_build_quest_level()` (step 8); `scrap` / `forge`
need the currency API (step 9). Those stay with their sections.

### Recommendation — add `route` and `wipe` at step 5

```
route <town|inn|blacksmith|mayor|quest>   SceneRouter.go(Place.<x>)
wipe                                       DirAccess delete user://profile.save; GameState.reset_run()
```

`route quest` + Q1's guard is how a tester reaches the (endless) forest via the
router before the mayor exists — it exercises exactly the step-5 code path.
`route` supersedes the bare `town` verb in §13.4 (one verb, all destinations);
update §13.4 to match, or keep `town` as a documented alias. New verbs go in
`debug.gd`'s `match verb` block (`debug.gd:38`) in the existing one-line style;
`_cmd_route` / `_cmd_wipe` alongside `_cmd_gold` et al.

---

## Q13. Does step 5 ship a pinning test?

Steps 1–4 each added one (`test_profile_expedition`, `test_profile_save`,
`test_enhanced_rarity`, and step 4's `test_drops` re-derivation), on step-1 Q5's
principle: "a step that buys isolation and then ships no assertion of its own
has spent the isolation and not collected." §13 lists **no** router or HUD test.

Step 5 is the first step whose acceptance is partly a *runtime* check (does the
game boot, route, and render the HUD), which the earlier headless-only steps
could not lean on. But several step-5 invariants are cheap to pin headless:

### Recommendation — a small `tests/test_scene_router.gd`

- `SceneRouter.PATHS` has an entry for **every** `Place` enum value
  (`Place.size()` vs `PATHS.size()`, and each key present) — the failure mode is
  adding `Place.FOO` and forgetting the path, which crashes only when someone
  routes there;
- every path in `PATHS` resolves (`ResourceLoader.exists(p)`);
- `SceneRouter` and `Hud` instantiate under a headless tree with no error
  pushed, and `SceneRouter`'s `_ready`/`_init` reference no sibling autoload
  (belt-and-braces over the lint's scene-autoload blind spot, Q4);
- **the §3.1 boot rule**: after `load_profile()` returns `false`, exactly one
  `SaveGame.save_profile()` follows — the guard against the step-5 warning
  ("every launch overwrites the player's file") regressing silently.

Keep it to ~10 checks. Confirm whether this is in step 5's scope or whether the
runtime boot check is considered sufficient.

---

## What step 5 ships (as built)

- **`scenes/boot.tscn` + `scripts/boot.gd`** — new. `load_profile()`, else
  `new_profile()` + `save_profile()` (§3.1); emit zero-delta `gold_changed` /
  `scrap_changed` (Q5); `await` one frame (I1); `change_scene_to_file` to
  `Place.TOWN` and set `SceneRouter.place` directly (Q7).
- **`scripts/autoload/scene_router.gd`** — new. `Place` enum, `PATHS`, `place`,
  `await`able `go()` with re-entrancy guard **and** the missing-path bail (Q7).
- **`scenes/hud/hud.tscn` + `scripts/hud/hud.gd`** — new autoload. `CanvasLayer`
  layer 10: `InventoryButton` (`disabled`, COMBAT lock live via `_process`, Q9 /
  I6), `CurrencyPlate` (gold + scrap, Q5), `ModalLayer` (`process_mode = ALWAYS`)
  hosting `QuestResult`, `Transition` `ColorRect` last, invisible + `IGNORE` at
  rest (Q10). `quest_result` accessor.
- **`scripts/hud/currency_plate.gd`** — new. Binds `gold_changed` /
  `scrap_changed`, reads `GameState` for first paint.
- **`scripts/ui/currency_feedback.gd`** — new. Static pop-and-float helper
  lifted from `status_panel._float_delta` (§5.3); `status_panel.gd` refactored
  onto it (I5).
- **`scenes/modals/run_summary.{tscn,gd,gd.uid}` → `quest_result.*`** — `git
  mv`, node + signal (`retry_pressed` → `dismissed`) rename, reparented under
  `Hud/ModalLayer` (Q3 / I4).
- **`scenes/main.tscn`** — `RunSummary` node + its `ext_resource` removed;
  `ModalLayer/ShopModal` stays.
- **`scripts/run/run_controller.gd`** — `_start_run()` guarded on
  `GameState.level == null` (§3.1 / I2, **not** Q1's `quest == null`); explicit
  `reset_run()` moved into `_on_retry()`; `run_summary` refs → `Hud.quest_result`,
  `_on_retry` on `dismissed` (Q2); `SceneRouter.place = Place.QUEST` first in
  `_ready` (Q8 / I3).
- **`scripts/autoload/event_bus.gd`** — five §3.3 signals, `quest_started`
  untyped (Q6).
- **`scripts/console/console.gd`** — one stale comment (Q3).
- **`scripts/console/status_panel.gd`** — refactored onto `currency_feedback.gd`
  (I5).
- **`scripts/autoload/debug.gd`** — `route`, `wipe` verbs; `route quest` calls
  `start_expedition()` unconditionally (Q12 / I9).
- **`project.godot`** (via `set_project_setting` / `add_autoload`) — `main_scene`
  → `boot.tscn`; `SceneRouter` then `Hud` autoloads after `SaveGame` (Q4, Q11).
- **`tests/test_scene_router.gd` + `.tscn`** — new, 12 checks (Q13 / I7).
- **spec** — reflects the resolved answers (§3.1 "guards … behind
  `GameState.level == null`", §3.2 step-8 vs step-5 wiring, §13.3 scene-autoload
  lint gap, §13.4 `route`/`wipe` at step 5, §14 step 5 changeset). The
  implementation notes below were **since** folded back into it: §3.1 (the boot
  yield, `place` trailing the incoming `_ready()`, the `to == place` no-op),
  §3.2 (three files in the `git mv`, the `or true` disable expression), §5.3
  (`currency_feedback.gd` at step 5), §13.1 (12 checks, the comment-strip),
  §13.4 (`route quest` unconditional) and §14 step 5 marked **Done.**

**Green bar:** §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_endless_level_gen`,
`test_retarget`, `test_parallax_seam`, `test_damage_chunk`) plus
`test_enhanced_rarity`, `test_profile_save`, `test_profile_expedition`,
`test_drops`, `test_item_distribution` — all still passing, and a
`--headless --quit-after` boot of `boot.tscn` reaching `Place.TOWN` clean.

---

## Implementation notes — issues found while building step 5

Step 5 is **implemented and green**: the full no-edit list above plus the four
edited-earlier tests all pass, `tests/test_scene_router.gd` (12 checks) is new
and green, a `--headless` boot of `boot.tscn` reaches `Place.TOWN` with no error,
and a headless smoke driving `debug route quest` confirms `SceneRouter.place`
goes `TOWN → QUEST`, `main.tscn` becomes `current_scene`, `GameState.level` is
built, and the loaded profile is **not** re-wiped on the way in.

The items below are things the questions above did not fully anticipate, or
places the answers had to be adjusted against what the engine actually does.

### I1. `change_scene_to_file()` from `boot.gd`'s `_ready()` needs a one-frame yield

Q7's recommendation — "`boot.gd` can `change_scene_to_file` directly" — crashes
as written:

```
ERROR: Parent node is busy adding/removing children, `remove_child()` can't be
       called at this time.
   at: _ready (res://scripts/boot.gd)
```

`change_scene_to_file()` frees the outgoing `current_scene`, and the tree is
still mid-build of `boot.tscn` during its own root `_ready()`. The fix is one
line — `await get_tree().process_frame` before the swap — which also gives the
`Hud` autoload a frame to settle, matching Q7's own "so `go()` never runs with a
half-initialised `Hud`" intent. `boot.gd` is therefore an `async` `_ready()`.
Q7 should note the yield.

### I2. The `_start_run()` guard is on `GameState.level`, not `GameState.quest` — Q1's recommendation was superseded

Q1 recommends `if GameState.quest == null: reset_run()`. The spec body (§3.1,
§14 step 5) was updated to **`if GameState.level == null`**, with the endless
**retry** reset moved out to an explicit call in `_on_retry()`. Implementation
follows the spec body, not Q1, because:

- `route quest` (Q12/§13.4) calls `GameState.start_expedition()` itself before
  routing. That leaves `quest == null` (no `QuestDef` yet at step 5) but
  `level != null`. A `quest == null` guard would still fire `reset_run()` and
  wipe the profile `route quest` was trying to preserve; a `level == null` guard
  correctly skips it. This is the exact step-5 path the guard exists for, and it
  is the case Q1 did not have in view.
- On endless retry `level` is non-null from the dead run, so the guard skips —
  hence the reset is now explicit in `_on_retry()` (`GameState.reset_run()` right
  before `_start_run()`), which is strictly clearer than relying on a predicate
  that happens to be true.

Net: Q1's diagnosis (don't *drop* the call) stands; its specific predicate does
not. The doc's Q1 recommendation box should be marked superseded by §3.1.

### I3. `RunController` sets `SceneRouter.place = Place.QUEST` first thing in `_ready()`

Per Q8, but worth pinning the ordering: it is set **before** the
`main.get_node(...)` lookups, so even if one of those ever fails the `place`
value is already correct. `run_summary` is repointed to `Hud.quest_result` (an
autoload `@onready`, resolved before the first scene — Q2's "available early"
holds in practice).

### I4. The `RunSummary → QuestResult` rename also moves `run_summary.gd.uid`

Q3's table is otherwise accurate. `git mv` needs three files, not two:
`run_summary.gd`, `run_summary.gd.uid`, `run_summary.tscn`. The `.tscn` has **no**
`uid=` on its `gd_scene` line, so `main.tscn` (removed) and the new `hud.tscn`
both reference `quest_result.tscn` by `path=` — no uid churn. `RunController`
keeps its `var run_summary` (assigned `Hud.quest_result`); renaming the field too
was avoided as pure noise for step 5.

### I5. The shared pop-and-float helper landed as `scripts/ui/currency_feedback.gd`

Resolving the "confirm" in "What step 5 ships": the helper is **not** deferred to
step 9. It is a static `RefCounted` (`pop(label)` + `float_delta(host, label,
delta, positive_color)`), lifted verbatim from `status_panel._float_delta`, and
`status_panel.gd` is refactored onto it in the same step (behaviour-preserving;
no test loads that scene). `CurrencyPlate` is the second caller, step 9's forge
the third — which is the "don't copy it a third time" §5.3 asked for. Location is
`scripts/ui/` rather than `scripts/hud/` because `status_panel` (a console node)
also depends on it.

### I6. `InventoryButton` disable expression

Q9's "wire the COMBAT rule now" is implemented as a per-frame
`inventory_button.disabled = _combat_locked() or true` in `hud.gd._process()`,
where `_combat_locked()` reads `SceneRouter.place == Place.QUEST and
RunController.state == COMBAT`. The `or true` is the placeholder step 6 deletes
when it adds the `pressed → Hud.inventory_modal.open()` handler; `_combat_locked()`
is genuinely evaluated every frame now, so step 6 inherits a tested lock.

### I7. `test_scene_router.gd` — two things Q13 did not spell out

- **`SceneRouter.Place.size()` and `.values()` work directly** — a named
  GDScript enum is a `Dictionary` constant, so the totality check is
  `SceneRouter.Place.size() == SceneRouter.PATHS.size()` plus a per-value key
  check, no `.values().size()` dance.
- **The boot-fallback source check must strip comments.** A naive
  `boot_src.count("save_profile()") == 1` is fine, but
  `boot_src.count("new_profile()") == 1` is **not** — `boot.gd`'s own header
  comment says "`new_profile()` itself never saves" etc. The test scans a
  comment-stripped copy of `boot.gd` and asserts exactly one `new_profile()` and
  one `save_profile()` call in code. The runtime half of the same guard
  (`new_profile()` alone writes no file; `save_profile()` after it writes a
  loadable one) is also asserted and is the stronger check.

Final count: 12 checks (totality ×2, existence ×2, autoload liveness ×2, router
lifecycle-lint ×1, boot rule ×5). `guard_user_file(SaveGame.PATH)` wraps it, per
§13.1.

### I8. New autoloads require a full editor restart, not a filesystem rescan

After `set_project_setting` + `add_autoload`, the **running editor** still
reports `Compile Error: Identifier not found: SceneRouter` / `Hud` for every
file that names them, and `reload_project` (filesystem rescan) does **not**
clear it — the editor only re-reads the autoload table on start. Every
`--headless` run is a fresh process and is unaffected (which is why the whole
suite is green). Anyone opening the project in the editor mid-review should
restart it once before trusting the Errors panel. Not a code issue; a workflow
footgun worth a line in the ship notes.

### I9. `debug route quest` is unconditional

§13.4 says the `quest` branch "calls `GameState.start_expedition()` before
routing". Implemented literally — no `if level == null` guard on the debug side.
Calling `route quest` twice just re-runs `start_expedition()` (a clean
expedition reset), which is acceptable for a debug verb and keeps it a
one-liner. `route inn|blacksmith|mayor` hit `go()`'s missing-path bail and log a
`push_warning`, as intended.

---

## Next: step 6 — §6, the inventory modal

Unblocked by step 5's `Hud/ModalLayer` and `SceneRouter`. Hazards already
visible from here:

- **`InventoryButton`'s `pressed` handler** is the one line step 5 deliberately
  left out (Q9); step 6 adds `Hud.inventory_modal.open()` and nothing else about
  the button changes.
- **`inventory_row.tscn` is a new scene, not a modified `shop_sell_row`** (§6.2)
  — and the shared `item_card_style.gd` helper §6.2 asks for has to be lifted
  from *two* existing copies (`shop_sell_row.gd`, `shop_buy_card.gd`), not one.
- **`CompareFlyout` moving into `Hud/ModalLayer`** (§3.2's end-state list)
  collides with the shop's own `compare_flyout` instance — step 6 has to decide
  whether that is one shared node or two, and §6.3's slot fix (`equipped_item(hero,
  item.slot())`) lands on whichever it is.
