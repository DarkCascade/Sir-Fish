# Sir Fish — Demo v3.5 Implementation Specification

**Document type:** build prompt for an implementing model
**Project:** `C:\Projects\Godot\Sir Fish` (Godot 4.7-stable, Forward+)
**Relationship to v3:** **v3 stays live.** This document is an *amendment*, not a replacement. `Sir Fish - Demo v3 Implementation Spec.md` remains the whole specification except for the sections §6 of this document lists as superseded. v1 and v2 are dead and stay dead.
**Scope:** one milestone, **M7.6**, sitting between v3's M7.5 (complete and gated) and M8a (not started).
**Source:** a state-of-the-project audit run against the working tree and two full play sessions (§2), plus six owner directives (§3).

---

## 0. How to use this document

M7.5 is complete. Re-verified independently before this document was written: all eight headless tests pass, both `stats.id` guards are gone from `battle_director.gd`, `SlotCounter` is at 908/1072, the `parallax` verb exists, the element chip renders, and two full runs produced zero errors and zero warnings. **You are not re-litigating M7.5 and you are not starting M8.**

Your job is the **twelve items in §2 and §3**. Six are audit findings — things that are correct against v3 and wrong on screen. Six are owner directives — deliberate design changes to v3.

### 0.1 Working rules

Every rule in v3 §0.1 still binds, unchanged. In particular:

1. **Use the Godot MCP Pro tools for all Godot work.** Never hand-edit `project.godot`. Prefer `update_property` over hardcoding visual values in scripts.
2. **All balance and timing numbers live in `res://scripts/autoload/tuning.gd`** (v3 §5). This pass adds nine constants and changes four; every one of them is listed in §4. **No file may hardcode a number this document names.**
3. **Verify a tool exists before depending on it** (v3 §0.1.4). Log any substitution.
4. **When a spec makes a claim about existing code, open the file.** Every `file:line` reference in this document was read before it was written. Hold the next document to the same standard.
5. Explicit type annotations everywhere; `const X := PackedVector2Array([...])` is not a constant expression — use `static var`.

### 0.2 Why this milestone exists at all

v3 §23 gates M8 behind M7.5 passing, and M7.5 passes. The case for spending a session here first is that **M8's gates are visual**: M8b and M8c gate per character on before/after screenshots and `capture_frames` sequences — six characters, eighteen hero animations, each one signed off by looking at it. Findings **F1**, **F2** and **F3** degrade exactly those screenshots.

Specifically: you cannot read a before/after animation gate through three health bars fused into one clump (F1), and the warrior's `special` — one of his six required clips — plays underneath an opaque disc that hides him for its entire duration (F2). Fixing either afterwards means re-running six character gates.

F3 is the one that genuinely *gates* M8's art budget: how much silhouette detail belongs in a low-poly hero depends on how many pixels tall it renders. Deciding that after modelling three heroes is the expensive order.

None of the twelve items touch meshes, rigs, animation names, `required_anims()`, or `model_scale`. **This pass does not change M8's surface area.** That is what makes it safe to take now.

### 0.3 Scope discipline

This is still a demo, and this is still a *tightening* pass. Build exactly the twelve items. Systems marked *Deferred* in v3 §22 stay deferred. Do not retune combat (v3 §22), do not touch `SLOT_STRIP` or the win rule, do not add audio, do not start M8.

---

## 1. Index

| # | Item | Kind | v3 sections affected |
|---|---|---|---|
| **F1** | Hero health bars overlap by 22 px, structurally | finding | §5.3b, §7.2, §11.1 |
| **F2** | Defend / Heal status icons hide the character | finding | §17.5 |
| **F3** | Battle framing wastes the viewport; characters read small | finding | §7.2, §5.3b |
| **F4** | Coin glyphs missing throughout the shop modal | finding | §15.1, §15.2, §15.3 |
| **F5** | `"Reached encounter 7 of 6"` on the victory path | finding | §18.2 |
| **F6** | A `stats.id` combat branch is still live in `ability.gd` | finding | §4.1, §21.4 |
| **D1** | An open shop must pause the game | directive | §14.3, §17.3, §18.2 |
| **D2** | Remove the `OUT OF COMBAT` marquee | directive | §16.6 |
| **D3** | Slot result banner: larger, centred on the payline | directive | §16.4 |
| **D4** | Enemy corpses fade *before* travel; rush the fade at victory | directive | §10.4, §10.5 |
| **D5** | Dead heroes slide out *concurrently* with travel | directive | §12.5 |
| **D6** | Health-chunk fling reduced by 50% | directive | §11.2 |

F1 and F3 share one edit and must be done together — see §2.3.

---

## 2. Findings

### 2.1 F1 — Hero health bars overlap by 22 px, on every adjacent pair, permanently

**Evidence, arithmetic.** The battle camera is orthographic, `size = 6.5`, default `keep_aspect` (KEEP_HEIGHT), rendering into a 1080 × 640 `SubViewport` ([battle_world.tscn:40-46](scenes/battle/battle_world.tscn:40)). That is **98.4 px per world unit**. `HERO_SLOT_X` is `[-4.2, -3.0, -1.8]` ([tuning.gd:31](scripts/autoload/tuning.gd:31)) — **1.2 units apart, or 118 px**. `CombatantBars` is **140 px wide** (v3 §11; `FILL_WIDTH := 136.0` plus 2 px borders, [combatant_bars.gd:5](scripts/overlay/combatant_bars.gd:5)) and is centred on the anchor:

```gdscript
# battle_overlay.gd:52
bars.position = vp - bars.size * 0.5
```

140 − 118 = **22 px of overlap on each adjacent pair, always.**

**Evidence, on screen.** With all three heroes alive the bars fuse into a single unreadable block. This is not intermittent and not a race — it is the geometry.

**Enemies are fine.** `ENEMY_X_MIN`/`MAX` of 1.6/4.8 puts three enemies 1.6 units — 157 px — apart.

**This is a defect in v3's own numbers**, not an implementation slip: §5.3b and §11.1 contradict each other, and §11.1 states the 140 px width as deliberate ("regardless of `max_hp`"). It is not recorded in `QUESTIONS-v3.md`. It fails design pillar 1 (*legibility over spectacle*) on the single most-read element in the battle.

**Rejected fixes, and why.** Narrowing the bars to 112 px changes `FILL_WIDTH`, which invalidates the twenty hardcoded expectations in `test_damage_chunk.gd` (108.8, 136.0, 27.2, …) for no gain. Staggering the bars vertically per slot breaks the 1:1 `unproject_position` → overlay mapping that v3 §3.3 and §11.1 both rely on, and reads as arbitrary.

**The fix is to widen the battlefield spacing.** It keeps `FILL_WIDTH` at 136, leaves every test untouched, and is a `tuning.gd`-only edit — `hero_slot_position()` and `enemy_slot_x()` both read from `Tuning` already ([battle_world.gd:34-42](scripts/battle/battle_world.gd:34)), so the `Slot0`/`Slot1`/`Slot2` markers in `battle_world.tscn` are vestigial and need no change. Numbers in §2.3, because they are solved jointly with F3.

### 2.2 F2 — The Defend and Heal status icons hide the character they belong to

v3 §17.5 specifies `draw_circle(c, 46, #3B6FD4 @ 0.85)` for Defend and `draw_circle(c, 52, #2FBF4F @ 0.55)` for Heal, and [status_icon.gd:30-34](scripts/overlay/status_icon.gd:30) implements that exactly. The icon is centred on `hit_world_position()` — the chest ([battle_overlay.gd:156](scripts/overlay/battle_overlay.gd:156)).

A 92 px disc at 85% opacity over a character that is ~177 px tall and ~75 px wide **covers the torso completely**. Confirmed on screen: the warrior disappears behind his own Defend icon for the full `WARRIOR_DEFEND_DURATION` of 4.0 s.

This matters beyond aesthetics. Defend is the warrior's `special`, one of the six clips M8b must author and gate by watching it play. You cannot verify a swing you cannot see.

**Fix — make both icons read as rings over the character, not discs in front of it.** Keep the position, the glyph, and the ring; drop the fill to a tint and shrink.

| | v3 | v3.5 |
|---|---|---|
| Defend fill radius | 46.0 | **36.0** |
| Defend fill alpha | 0.85 | **0.28** |
| Defend ring radius / width | 46.0 / 5.0 | **36.0** / 5.0 |
| Defend shield glyph box | 60.0 | **46.0** |
| Heal fill radius | 52.0 | **42.0** |
| Heal fill alpha | 0.55 | **0.22** |
| Heal ring radius / width | 52.0 / 5.0 | **42.0** / 5.0 |
| Heal plus glyph box | 62.0 | **50.0** |

Ring colours, glyph colours and the `Control` size of 140 × 140 are unchanged. The glyph stays fully opaque — it is what identifies the effect; the fill was only ever a backdrop for it.

These eight numbers go into `tuning.gd` (§4). They are an art call: if the ring reads too faint at 164 px on a phone, raise the alphas — but never past the point where the character's silhouette stops showing through.

### 2.3 F3 — Battle framing, and the joint geometry fix

**The observation.** Characters render 177 px tall in a 640 px band and cluster in the outer thirds with a dead centre. Visible vertical range is `y ∈ [-1.05, 5.45]` for 1.8-unit characters, so **over half the battle viewport is empty sky.**

**The honest analysis, which changes the fix.** The obvious response — zoom in — is impossible. Camera half-width is `size × 1.6875 / 2 = 0.844 × size`. The battle line currently spans x ∈ [-4.2, 4.8] plus half-widths ≈ 9.8 units, so `size` cannot drop below ~6.2 without pushing the rightmost enemy out of frame. There is essentially no room at the current layout.

More generally: **a 1.6875:1 viewport holding a ~9-unit battle line caps a 1.8-unit character at roughly a third of the frame height, whatever the camera does.** That is geometry, not a bug, and no camera number fixes it. The remaining sky is an art problem — taller hills and tree canopy in layers 1–3 and the M8d environment pass — not a framing problem. **Record that and do not chase it with the camera.**

What *is* available is to narrow the battle line, which buys both a bigger character and the spacing F1 needs. F1 wants heroes further apart; narrowing the enemy spread and the centre gap pays for it.

**The joint solution.** Change three `tuning.gd` values and one camera property:

| Constant | v3 | v3.5 | Why |
|---|---|---|---|
| `HERO_SLOT_X` | `[-4.2, -3.0, -1.8]` | **`[-4.0, -2.5, -1.0]`** | 1.5 units apart — 165 px at the new scale, a 25 px gutter between 140 px bars |
| `ENEMY_X_MIN` | `1.6` | **`1.2`** | pulls the enemy line inward to pay for the hero spread |
| `ENEMY_X_MAX` | `4.8` | **`4.0`** | three enemies land 1.4 units — 154 px — apart, clear of 140 px bars |
| `BattleCamera.size` | `6.5` | **`5.8`** | the narrowed line permits it |

`BattleCamera.position` stays `(0, 2.2, 12)` and `rotation` stays `(0, 0, 0)`. **Change `size` only** — moving the camera as well would shift the horizon against parallax layer geometry authored for the current framing, which is exactly the kind of unforced coupling this pass is meant to avoid.

**Derived, and required to hold — verify these in the gate:**

- Scale: `640 / 5.8` = **110.3 px per world unit** (was 98.4). A 1.0-scale character is **199 px** tall, up 12%.
- Camera half-width: `5.8 × 0.84375` = **±4.89**.
- Hero bar gutter: `1.5 × 110.3 − 140` = **25.5 px**. No overlap. **F1 closed.**
- Enemy bar gutter at three enemies: `1.4 × 110.3 − 140` = **14.4 px**. No overlap.
- Widest right-hand case: a lone `orc_barbarian` sits at `ENEMY_X_MAX` = 4.0 with a ~0.5 half-width → 4.5, inside 4.89. ✔
- Warlord case: `model_scale` 1.70, half-width ~0.7. v3 §7.3's rule — **list `orc_warlord` first in `enemy_stat_ids`** so it takes index 0 — still stands and still puts it at 1.2. A lone warlord lands at `(1.2 + 4.0) / 2` = 2.6 → 3.3. ✔
- Leftmost: priest at −4.0, half-width ~0.35 → −4.35, inside 4.89. ✔
- Visible vertical range becomes `y ∈ [-0.7, 5.1]`.

**What this does not fix, stated plainly:** the sky is still the majority of the frame. See the analysis above — that is M8d's job.

### 2.4 F4 — Coin glyphs are missing throughout the shop modal

`coin_glyph.gd`'s own docstring names its three intended homes:

```gdscript
# coin_glyph.gd:2-3
## The gold coin from spec 16.7, reused wherever a gold amount is shown
## (status panel, shop prices, sell buttons). Drawn, never an image file.
```

It is instanced by exactly one scene — `status_panel.tscn`. v3 requires it in three more places and none of them have it:

| v3 | Requirement | As built |
|---|---|---|
| §15.1 | shop gold readout: "coin glyph + `str(GameState.gold)`" | bare number |
| §15.2 | buy card price: "`str(buy_price)` with a coin glyph" | [shop_buy_card.gd:31](scripts/modals/shop_buy_card.gd:31) — `price_label.text = str(i.buy_price())` |
| §15.3 | sell button: "labelled `Sell for N` with a coin glyph" | [shop_sell_row.gd:22](scripts/modals/shop_sell_row.gd:22) — `"Sell for %d"` |

**Fix.** Add a `CoinGlyph` instance to each of the three, mirroring `status_panel.tscn`'s existing usage. Sizes: **radius 16** in the shop header (beside a font-44 readout), **radius 15** on the buy card price (font 46), **radius 13** on the sell button (its own font). Each sits immediately left of the number with an 8 px gap, vertically centred.

**Trap.** The buy card's price lives in `Row/Layout/PriceBox`, a `VBoxContainer` with `custom_minimum_size = (220, 0)`. Adding the glyph means an `HBoxContainer` inside `PriceBox`, right-aligned. Do **not** widen `PriceBox` — v3 §15.2's warning about `PanelContainer` force-resizing children applies to everything in this card.

**Related, and in scope because it is one line:** the price sits flush against the card's right edge with no padding, and a 3-digit price visibly touches the border. Give `PriceBox` an 18 px right margin.

### 2.5 F5 — `"Reached encounter 7 of 6"` on the victory path

[run_summary.gd:39-42](scripts/modals/run_summary.gd:39) implements v3 §18.2's format string literally:

```gdscript
subtitle.text = "Reached encounter %d of %d" % [
    GameState.current_encounter_index + 1,
    GameState.level.encounters.size(),
]
```

On a win, `_next_encounter()` has already incremented `current_encounter_index` past the last encounter before `_run_complete()` fires ([run_controller.gd:62-65](scripts/run/run_controller.gd:62)), so a cleared six-encounter run reads **"Reached encounter 7 of 6"** under a `LEVEL CLEARED` title. Confirmed on screen.

**Fix.** `present()` already receives `victory: bool`. Branch on it:

- Victory → `"Cleared all %d encounters"` % `GameState.level.encounters.size()`
- Defeat → `"Reached encounter %d of %d"`, unchanged, with the index **clamped** to `[1, encounters.size()]` so the defeat path can never print an out-of-range index either.

### 2.6 F6 — A `stats.id` combat branch is still live

v3 §21.4's standing rule: *"No combat branch may key on `stats.id`. Character-specific behaviour is a `CombatantStats` field."* One branch still does:

```gdscript
# ability.gd:27-34
## Telegraph beat - only the priest uses it.
func charge(source: Combatant) -> void:
    if source.stats.id != &"priest" or is_special:
        return
    if Tuning.PRIEST_DARKEN_ENABLED:
        BattleVfx.darken_pass(source)
    if target != null and target.is_alive():
        BattleVfx.warning_glow(target)
```

`QUESTIONS-v3.md` logged the decision to leave this alone, on the grounds that E1's literal file scope was `combatant_stats.gd`, the two `.tres` files, and `battle_director.gd`. That is a fair reading of E1. It is also precisely the pattern v3 §24's fifth standing habit exists to catch: *"When you fix an instance of a bad pattern, grep for the pattern."* V6 handed over one hardcoded check, there were two, and this is the third.

**Fix.** Add one field to `CombatantStats`:

```gdscript
@export var telegraphs_primary: bool = false   # [v3.5] F6 - priest only
```

Set `true` in `priest.tres`, leave `false` everywhere else (the default, so the other five `.tres` files need no edit). Replace the guard with `if not source.stats.telegraphs_primary or is_special: return`. Behaviour is identical.

**Out of scope, deliberately, and both should stay as they are:**

- `Ability.resolve()`'s `match source.stats.id` ([ability.gd:39](scripts/battle/ability.gd:39)) is structural per-character dispatch to the ability implementations themselves, not a behavioural gate. Same category as `CombatantAnimations`.
- `combatant_rig.gd`'s three id checks build placeholder primitives and are deleted wholesale by M8b/M8c.
- `combatant.gd:190`'s `SPECIAL_FLASH_COLORS.get(stats.id, ...)` is a lookup table, not a branch.
- `debug.gd`'s resolver is explicitly legitimate per v3 §4.1.

After this change, `grep -rn "stats\.id ==" scripts/` should return **only** `debug.gd:81` and `combatant_rig.gd`.

---

## 3. Owner directives

These are **design changes to v3**, not corrections. Each one supersedes the v3 text named in its heading.

### 3.1 D1 — An open shop pauses the game *(supersedes v3 §14.3, §17.3's last bullet, §18.2's Run time row)*

**The problem.** `PARTY_DAMAGE_BUFF_DURATION` is 30.0 s and the buff drains in `_process` ([party_damage_button.gd:18-26](scripts/console/party_damage_button.gd:18)). Nothing pauses while the shop modal is open — `_run_shop()` simply `await`s `shop_modal.closed` ([run_controller.gd:154](scripts/run/run_controller.gd:154)). A player who buys the buff and then browses the shop watches 30 seconds of it evaporate against nothing. v3 §17.3 explicitly blesses this — *"The timer is real time and encounter-agnostic"* — and that decision is now reversed.

**The rule.** An open shop modal pauses the game. `SHOP` is the only state that pauses; `LOOT` and the run summary do not.

**Implementation.**

1. `shop_modal.open()` sets `get_tree().paused = true`. `shop_modal.close()` sets it back to `false` — **before** `queue_free()`, and on every exit path, so a modal that is torn down unexpectedly can never strand the tree paused.
2. `ModalLayer` gets `process_mode = PROCESS_MODE_ALWAYS`. It is inherited, so `ShopModal`, `RunSummary` and every child keep processing: the scrim fade, the panel scale-in, the price pulse, the gold float, the sell-row collapse, and — critically — the **X button** all still work.
3. Nothing else changes its `process_mode`. Everything under `Console` and `BattleView` is left `PROCESS_MODE_INHERIT`, which is what makes the pause do its job.

**Consequences, all intended:**

- `party_damage_button._process` stops, so `_remaining` and `BuffProgress` freeze exactly as asked. The comment at [party_damage_button.gd:22-23](scripts/console/party_damage_button.gd:22) — *"stays correct if the game is paused"* — becomes true rather than aspirational.
- `run_controller._process` stops, so shop time no longer accrues into `run_stats["run_time"]`. **This changes the `Run time` row in v3 §18.2** and is the correct read: run time is time spent playing.
- The slot cabinet freezes mid-drift. Acceptable — the cabinet is behind a full-screen scrim.
- Sir Fish's tank freezes. Acceptable, same reason. Do **not** exempt it; an animating fish behind a scrim is not worth a `process_mode` exception.

**Trap — read this before writing the code.** `SceneTree.create_timer()` takes `process_always` and it **defaults to `true`**. Every `await get_tree().create_timer(...)` in the project therefore keeps counting through a paused tree. Audit the three coroutine sites — `run_controller.gd`, `slot_machine.gd`, `battle_director.gd` — and confirm none of them has a timer in flight when the shop opens. As built none do: `_run_shop` finishes its 0.85 s prop-entry timer before calling `open()`, and `_spin_loop` has already exited because `_should_spin` is false out of combat. **State that you checked it.** If a future change puts a timer in flight across a pause, pass `process_always = false` at that call site rather than restructuring the pause.

### 3.2 D2 — Remove the `OUT OF COMBAT` marquee *(supersedes v3 §16.6's Attract row)*

Delete the `Marquee` label ([slot_machine.tscn:140-149](scenes/console/slot_machine.tscn:140)) and, in `slot_machine.gd`, the `marquee` and `_marquee_tween` members, `_start_marquee_pulse()`, and the two `marquee.visible` assignments in `_enter_attract()` / `_leave_attract()`.

**Everything else about attract mode stays.** The reels keep drifting at `SLOT_ATTRACT_SPEED`, the cabinet still dims to `SLOT_ATTRACT_DIM`, and the payline still goes unlit `#5C5470`. Those three already say "not live" without a label saying it in words, and v3 §16.6's own reasoning — *dead air is a bug* — was about the reels, not the caption.

Amend v3 §16.6's Attract row to end at *"Payline unlit `#5C5470`."*

### 3.3 D3 — Slot result banner: larger, centred on the payline *(supersedes v3 §16.4's banner bullet)*

The banner currently sits in a 1080 × 56 strip at the very top of the cabinet at font 48 ([slot_machine.tscn:119-129](scenes/console/slot_machine.tscn:119)) — above the reels, away from where the player is looking when the reels stop.

**Change `Banner` to fill the whole `SlotMachine` rect and centre on the payline:**

| Property | v3 | v3.5 |
|---|---|---|
| `offset_left` / `offset_top` | 0 / 0 | 0 / 0 |
| `offset_right` / `offset_bottom` | 1080 / 56 | **1080 / 600** |
| `horizontal_alignment` | 1 (centre) | 1 (centre) |
| `vertical_alignment` | 1 (centre) | 1 (centre) |
| `font_size` | 48 | **72** |
| `outline_size` | 8 | **14** |

`SlotMachine` is 1080 × 600 and `Payline` spans y 298–302 ([slot_machine.tscn:88-93](scenes/console/slot_machine.tscn:88)), so a full-rect vertically-centred label puts its text centre at y = 300 — **on the payline**, which is the ask.

**Draw order is already correct** and must stay so: `Banner` is declared after all three `ReelWindow`s, so it composites above the symbols. If you reorder anything in this scene, re-check that.

The outline goes from 8 to 14 because the banner now sits over the symbols rather than over empty cabinet, and `#0F0E14` at 14 px is what keeps `#F2C230` text legible against a gold coin or a blue bolt.

`_celebrate()`'s text (`"%s x%d"`) and timing (0.12 s in, 1.0 s hold, 0.25 s out) are unchanged.

**Verify, do not assume:** the longest string is `"LIGHTNING x3"` (12 characters). At font 72 it must fit inside 1080 px without clipping. Screenshot it. If it clips, drop to 64 and record the change — do not enable `autowrap`, which would break the single-line read.

### 3.4 D4 — Enemy corpses fade before travel, rushed at victory *(supersedes v3 §10.4's enemy bullet and §10.5's last bullet)*

**The problem, timed from the code.** On a victory with no hero deaths:

| t | event |
|---|---|
| 0.0 | last enemy dies; `_finish_victory()` waits `ENCOUNTER_RESOLVE_PAUSE` |
| 0.8 | `combat_ended(true)` → `begin_corpse_cleanup()` → `_encounter_resolved()` waits `ENCOUNTER_RESOLVE_PAUSE` again |
| 1.6 | `_encounter_exit()` → no dead heroes → `_travel()` **starts** |
| 2.3 | corpses *begin* fading (`ENEMY_DEATH_HOLD` = 1.5 from t=0.8) |
| 4.3 | corpses finish (`ENEMY_DEATH_FADE` = 2.0) and free |

The party walks off at t=1.6 with the corpses still fully opaque; they do not start fading until 0.7 s into travel and do not finish until 2.7 s in. v3 §10.5 blesses this — *"they scroll away with the world"* — and that is now reversed.

**A second defect found while timing this, and fixed in the same function.** `begin_corpse_cleanup()` is called from exactly one place — [run_controller.gd:117](scripts/run/run_controller.gd:117), on victory. Nothing calls `_fade_corpse` per death. So in a three-enemy fight, the first enemy to die **lies on the battlefield fully opaque for the rest of the fight**, and v3 §10.4's per-death hold-and-fade is not implemented at all. Both halves are the same function, so both are fixed here.

**The rule.** An enemy corpse fades on a timer that starts when it dies. If the fight ends while it is still holding or fading, the fade is **rushed** so that no corpse is on screen when travel begins.

**Implementation.**

1. `_fade_corpse(c: Combatant, rush: bool)`. Slow path uses `ENEMY_DEATH_HOLD` / `ENEMY_DEATH_FADE` (1.5 / 2.0, unchanged); rush path uses the two new constants in §4 (**0.30 / 0.45**).
2. `BattleDirector` connects `EventBus.combatant_died` and starts the **slow** fade for any enemy that dies while `_active` is true.
3. `begin_corpse_cleanup()` becomes the rush trigger. For every enemy corpse: kill its in-flight slow tween if it has one (store it via `set_meta`), then run the rush path from its current alpha.
4. `BattleDirector` exposes `await_corpse_cleanup() -> void`, which returns once every corpse has been freed.
5. `run_controller._encounter_resolved()` awaits **both** `ENCOUNTER_RESOLVE_PAUSE` and `director.await_corpse_cleanup()` before calling `_encounter_exit()`.

**Why 0.30 / 0.45.** They sum to 0.75, which fits inside the `ENCOUNTER_RESOLVE_PAUSE` of 0.8 that already elapses in parallel. **The rush therefore adds zero net time to the run** while guaranteeing the battlefield is clear before travel. Awaiting the signal rather than relying on two independent 0.8 s timers is what makes the ordering provable instead of coincidental.

The defeat path is untouched: `_game_over()` does not call cleanup, and on a wipe the enemies are alive anyway.

### 3.5 D5 — Dead heroes slide out concurrently with travel *(supersedes v3 §12.5's step 2)*

**The problem.** [run_controller.gd:178-191](scripts/run/run_controller.gd:178) starts the dead-hero slide, then blocks:

```gdscript
await get_tree().create_timer(Tuning.DEAD_HERO_EXIT_TIME).timeout
_next_encounter()
```

So the corpse slides left across a **static** background for 1.6 s, and only then does the world start scrolling. It reads as the dead hero crawling away under its own power, which is the opposite of the intended beat.

**The rule.** The dead-hero slide and the party's departure begin on the same frame, so the world scrolls past while the corpse falls behind — the dead are *left behind*, not sent ahead.

**Implementation.** In `_encounter_exit()`, launch the slide tweens exactly as they are now, then **drop the `await`** and call `_next_encounter()` immediately. The tweens are owned by `RunController` and outlive the state change; each still ends with its `visible = false` callback.

- Living heroes get `set_running(true)` on the first line of `_travel()`, which now happens in the same frame.
- `DEAD_HERO_EXIT_TIME` (1.6) stays, and is comfortably shorter than the shortest `travel_duration` (2.5), so the slide always completes during travel.
- The tween target of `position:x = -7.0` is unchanged and still clears the new camera half-width of 4.89.
- v3 §12.5's rule that a dead hero is **visually** removed and never freed is unchanged — the status panel's index-addressed rows still depend on it.

Amend §12.5 step 2 to read: *"Do not wait for that tween. Travel begins on the same frame, so the world scrolls past the departing corpse."*

### 3.6 D6 — Health-chunk fling reduced by 50% *(supersedes v3 §11.2 step 5)*

The detached chunk currently flies up to 90 px sideways and 130 px up ([floating_health_chunk.gd:8-12](scripts/overlay/floating_health_chunk.gd:8)), which throws it far enough from its parent bar that the eye loses the connection between the hit and the bar it came from. Halve every displacement.

| | v3 | v3.5 |
|---|---|---|
| X displacement | `randf_range(-90, 90)` | **`randf_range(-45, 45)`** |
| Y displacement | `randf_range(-130, -50)` | **`randf_range(-65, -25)`** |
| Rotation | `randf_range(-0.9, 0.9)` | **`randf_range(-0.45, 0.45)`** |
| Flight time | 0.70 | **0.70 — unchanged** |
| Easing | `TRANS_CUBIC/EASE_OUT`, alpha `TRANS_QUAD/EASE_IN` | unchanged |

Rotation is halved with the rest: "explosiveness" is the whole gesture, and a chunk that travels half as far while spinning just as hard reads as tumbling rather than as flung. Flight time is *not* halved — that is pacing, not force, and shortening it would make the effect snappier rather than calmer.

**These five numbers are currently hardcoded in `floating_health_chunk.gd`, which violates v3 §5.** Move them to `tuning.gd` (§4) as part of this change.

`test_damage_chunk.gd` asserts the chunk's **spawn** rect only, not its flight, so it is unaffected. Confirm it still passes rather than assuming.

---

## 4. Tuning changes

All of these live in `res://scripts/autoload/tuning.gd`. **No other file may hardcode any of them.**

### 4.1 Changed

```gdscript
# --- 5.3b Battlefield geometry --------------------------------- [v3.5 F1/F3]
const HERO_SLOT_X := [-4.0, -2.5, -1.0]   # was [-4.2, -3.0, -1.8]; 1.5 apart so
                                          # 140px bars clear each other (F1)
const ENEMY_X_MIN := 1.2                  # was 1.6
const ENEMY_X_MAX := 4.0                  # was 4.8
```

`BattleCamera.size` 6.5 → **5.8** is a scene property, not a constant — set it with `update_property` on `battle_world.tscn`, not in code.

### 4.2 Added

```gdscript
# --- 5.1 Timing ------------------------------------------------ [v3.5 D4]
const ENEMY_DEATH_HOLD_RUSH := 0.30   # corpse hold when the fight is already won
const ENEMY_DEATH_FADE_RUSH := 0.45   # 0.30 + 0.45 = 0.75, inside ENCOUNTER_RESOLVE_PAUSE

# --- 5.9 Health chunk ------------------------------------------ [v3.5 D6]
const CHUNK_FLING_X := 45.0           # was an inline +/-90 in floating_health_chunk.gd
const CHUNK_FLING_Y_MIN := 25.0       # was 50
const CHUNK_FLING_Y_MAX := 65.0       # was 130
const CHUNK_SPIN := 0.45              # was +/-0.9 rad
const CHUNK_FLIGHT_TIME := 0.70       # unchanged, moved here so no number stays inline

# --- 5.10 Status icons ----------------------------------------- [v3.5 F2]
const ICON_DEFEND_RADIUS := 36.0
const ICON_DEFEND_FILL_ALPHA := 0.28
const ICON_DEFEND_GLYPH_BOX := 46.0
const ICON_HEAL_RADIUS := 42.0
const ICON_HEAL_FILL_ALPHA := 0.22
const ICON_HEAL_GLYPH_BOX := 50.0
const ICON_RING_WIDTH := 5.0
```

---

## 5. What this pass does *not* change

Stated explicitly so nothing gets tidied on the way past:

- **Nothing in M8's surface area.** No meshes, no rigs, no armatures, no animation names, no `required_anims()`, no `model_scale`, no `.glb` import settings.
- **`FILL_WIDTH := 136.0`** and every number in `test_damage_chunk.gd`. F1 is solved by geometry precisely so this stays put.
- **`SLOT_STRIP`, the win rule, and the 50.038% win rate.** Untouchable (v3 §16.2).
- **Combat tuning.** `attack_cooldown`, `max_hp`, `base_damage`, the specials. Retuning is post-demo (v3 §22).
- **The five accepted permanent deviations** C1–C5 (v3 §21.3), including `msaa_3d = 2.0` and the autoload order.
- **`res://resources/levels/demo_level.tres`** — E5 remains outstanding and remains inert. It is logged in `QUESTIONS-v3.md` and is not this pass's job.
- **The empty upper half of the battle frame.** See §2.3: it is capped by viewport aspect and is M8d's problem.
- **Per-tile parallax variety, audio, saving, equipping** — all still deferred (v3 §22).

---

## 6. Amendments to v3

| v3 section | Status after v3.5 |
|---|---|
| §5.3b Battlefield geometry | **Superseded** by §4.1 |
| §7.2 `BattleCamera` | **Amended** — `size` 6.5 → 5.8; position and rotation unchanged; the derived figures in that section are all restated in §2.3 |
| §10.4 Death, enemy bullet | **Superseded** by §3.4 — per-death fade now actually implemented, plus a rush path |
| §10.5 Resolution, last bullet | **Superseded** by §3.4 — corpses no longer scroll away mid-fade |
| §11.2 step 5 | **Superseded** by §3.6 |
| §12.5 step 2 | **Superseded** by §3.5 |
| §14.3 Shop encounter | **Amended** by §3.1 — the modal pauses the tree |
| §15.1 / §15.2 / §15.3 | **Unchanged in intent; now actually implemented** — §2.4 |
| §16.4 banner bullet | **Superseded** by §3.3 |
| §16.6 Attract row | **Amended** by §3.2 — marquee removed |
| §17.3 last bullet | **Superseded** by §3.1 — the buff timer is encounter-agnostic but **pause-aware** |
| §17.5 Status icon | **Superseded** by §2.2 |
| §18.2 subtitle | **Superseded** by §2.5 |
| §18.2 `Run time` row | **Amended** by §3.1 — excludes time spent in the shop |
| §4.1 `CombatantStats` | **Extended** by §2.6 — one field, `telegraphs_primary` |
| everything else | **Unchanged and still binding** |

---

## 7. Traps — do not regress these

Carried forward from v3 §21.4 in full, plus these ten:

| Where | Trap |
|---|---|
| `tuning.gd` | `HERO_SLOT_X` spacing and `CombatantBars`' 140 px width are **coupled**. Any future change to either must keep `spacing × (640 / camera.size) > 148`. That inequality is the whole of F1. |
| `battle_world.tscn` | Change `BattleCamera.size` **only**. Moving the camera's `position.y` shifts the horizon against parallax geometry authored for the current framing. |
| `battle_world.tscn` | `Slot0`/`Slot1`/`Slot2` are vestigial — positions come from `Tuning.HERO_SLOT_X` via `battle_world.gd:34`. Do not "sync" them and do not trust them. |
| `shop_modal.gd` | `get_tree().paused = false` must run on **every** exit path, before `queue_free()`. A stranded pause is an unrecoverable soft-lock with no error in the log. |
| `main.tscn` | `ModalLayer` must be `PROCESS_MODE_ALWAYS` or the shop's own X button stops working the instant the tree pauses. |
| everywhere | `SceneTree.create_timer()` defaults to `process_always = true` — it **ignores** pause. Any timer that must respect the shop pause has to pass `false` explicitly. |
| `slot_machine.tscn` | `Banner` must stay declared after all three `ReelWindow`s or it composites behind the symbols. |
| `battle_director.gd` | A corpse can be mid-slow-fade when victory lands. The rush path must **kill the in-flight tween** and resume from the current alpha, not stack a second tween on the same property. |
| `run_controller.gd` | The dead-hero slide tween is owned by `RunController` and must survive the state change to `TRAVEL`. Do not parent it to anything that the next encounter tears down. |
| `floating_health_chunk.gd` | Halve displacement, **not** flight time. Shortening 0.70 makes the effect snappier, which is the opposite of the ask. |

---

## 8. M7.6 — milestone and gate

One session. Order: **F1+F3 first** (they move everything else's pixels), then F2, then D2/D3, then D4/D5, then D1, then F4/F5/F6/D6.

**Gate — zero errors and zero warnings throughout, per v3 §0.1.3:**

1. **All eight headless tests pass**, run directly via `Godot_console.exe --headless`, not through the MCP inspector. `test_damage_chunk` and `test_parallax_seam` are the two to watch — neither should have been touched, and if either moves, something in F1/F3 went further than it should have.
2. **F1:** a screenshot of a live encounter with **all three heroes alive**, showing a visible gutter between all three bar pairs. Measure it, do not eyeball it: ~25 px expected.
3. **F1/F3:** a three-enemy encounter and a warlord encounter, both screenshotted, confirming no combatant or bar is clipped by either viewport edge.
4. **F2:** `Debug` the warrior into Defend and `capture_frames` across the clip — the warrior's body must be readable through the icon for its full 4.0 s. Repeat for the priest's heal.
5. **D1:** buy the party damage buff, open the shop, wait 20 s of wall time, close it, and confirm from `BuffProgress` that the remaining time is unchanged. Confirm the X button still works while paused. Confirm the run summary's `Run time` excludes the shop.
6. **D2:** no `OUT OF COMBAT` text in attract mode; reels still drift, cabinet still dims, payline still unlit.
7. **D3:** screenshot a win. The banner sits centred on the payline at font 72 and `"LIGHTNING x3"` does not clip.
8. **D4:** screenshot the frame travel begins on — **no enemy corpse on screen.** Separately, kill one of three enemies mid-fight and confirm that corpse fades on its own before the fight ends.
9. **D5:** `capture_frames` across the transition after a hero dies — the corpse must slide left **while** the background is already scrolling.
10. **D6:** `capture_frames` a hit and confirm chunks stay near their bar.
11. **F4/F5/F6:** coin glyphs on the shop header, all three buy prices and all sell buttons; a cleared run reads `"Cleared all 6 encounters"`; `grep -rn "stats\.id ==" scripts/` returns only `debug.gd:81` and `combatant_rig.gd`.
12. **A full hands-off run** — closing only the shop modal, which v3 §15.4 requires a real click for — with zero errors and zero warnings in `get_output_log` checked immediately after `clear_output`.

**Only after this gate passes, start M8a** per v3 §20 and §23.

---

## 9. Open questions

Open `QUESTIONS-v3.5.md` rather than appending to `QUESTIONS-v3.md`, which is closed by this document. Same discipline: implement as specified, record every deviation with the file and the reasoning, change nothing silently, and raise a **BLOCKER** rather than guessing.

Two items in this document are art calls rather than engineering ones, and the owner should be asked rather than guessed at if the numbers look wrong on screen:

- **F2's alphas** (0.28 / 0.22). Chosen so the character shows through. If the effect stops reading at phone size, raise them — but the character's silhouette must stay visible, or the finding is unfixed.
- **F3's `size = 5.8`.** Chosen as the tightest framing that fits the narrowed battle line with margin. If a later change widens the line again, this number moves with it, and F1's inequality in §7 is the constraint to re-check.

One item is knowingly left undone and is **not** a blocker: **E5**, the orphaned `res://resources/levels/demo_level.tres`. Nothing references it; `GameState.build_level()` remains the sole source of truth for the level. It stays logged in `QUESTIONS-v3.md`.

---

*End of specification.*
