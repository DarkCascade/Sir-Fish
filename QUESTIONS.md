# Sir Fish — Demo v1: open questions for the design agent

> **CLOSED — 2026-08-13.** Every question below (Q0–Q24) is answered in
> `design documents/Sir Fish - Demo v2 Implementation Spec.md`, which supersedes v1 entirely.
> See §0.2 of that document for the question-to-section index and §21.3 for the resulting
> code changes. **Do not act on this file.** It is kept as the record of how the answers
> were arrived at. Open a fresh questions file for v2.

Generated during implementation of `design documents/Sir Fish - Demo v1 Implementation Spec.md`.
Everything below is either (a) a question the spec does not answer, or (b) a place where the
spec contradicts itself or contradicts the engine, where I implemented one reading and need it
ratified. **Nothing here was silently changed** — every deviation is listed with the exact file
and the reasoning, per spec §21's instruction.

Milestones M0–M5 are implemented in code. **M6 (Blender assets) has not been started** — see
"Where this stands" below.

---

## Q0 — RESOLVED: the Godot MCP Pro toolset is connected

The blocker recorded here in the first session is closed. The toolset was available in the
second session, the project was opened, played and driven through a full run, and everything
below was checked against the running game rather than against the source text.

What that turned up, and what was fixed, is in "Fixed in session 2" at the bottom of this file.
Two consequences of the first session's offline authoring did bite and are worth knowing about:
the hand-written `.tscn` files had one missing script attachment and two container-layout
mistakes that only appear at runtime, and several `var x := <untyped call>` lines failed to
parse. All are fixed.

The three numeric checks the spec calls out by name now have numbers:

| Check | Spec target | Observed |
|---|---|---|
| M3 — `tests/test_slot_odds.gd`, 1,000,000 spins | win rate in [0.490, 0.510] | **0.50001** — PASS |
| M3 — 3-of-a-kind per symbol | [0.014, 0.021] | 0.01742 / 0.01746 / 0.01754 — PASS |
| M3 — exhaustive enumeration | 9,849 / 19,683 = 0.500381 | **identical**, and strip is 7/7/7/6 |
| M5 — 200 items, rarity split | ≈50 / 30 / 15 / 5 | **50.0 / 27.5 / 16.0 / 6.5** — PASS |
| M5 — item value min/median/max | §13.3 predicts 18–465 | 18 / 41 / 388 (buy 27 / 62 / **582**) |

The remaining M2 numeric check (the 100 HP-hit-for-20 chunk case) is still owed, and is blocked
on Q21 rather than on anything in the game.

---

## Q21 — this MCP build has no `execute_editor_script` / `execute_game_script`

**Status: needs a decision, not a design answer.**

Spec §20 writes several gate items as "force this via `execute_game_script`". Those two tools
are **not present** in the connected Godot MCP Pro build. The tools that *are* present cover
most of it — `set_game_node_property`, `batch_get_properties`, `simulate_mouse_click`,
`find_ui_elements`, `wait_for_node`, `capture_frames`, `run_test_scenario` — but they cannot
call an arbitrary function, so the following gate items have no route today:

- M1: forcing each of the six animations on each character in turn.
- M2: forcing the exact 100 HP / 20 damage case, and killing a ranger's target mid-flight.
- M3: forcing each of the six slot payouts.
- M5: reproducing §15.2's exact 200/250/300-vs-350-gold scenario (shop stock is random).

Two of the M3/M5 numeric gates were closed a different way that works well and is worth
keeping: **a headless run of a test scene**, driven from a terminal rather than through MCP —
`godot --headless --path <project> res://tests/test_item_distribution.tscn`. `test_slot_odds.gd`
already ran the same way. Both are reproducible and both are in the repo.

**Question:** for the remaining items, is it acceptable to add a small **temporary debug
harness** to the game — a `RunController` method behind a key binding that forces a named
animation, applies an exact damage amount, forces a slot result, and stocks the shop with
fixed prices — used for the gate and then removed? That is the only route I can see that does
not involve eyeballing it. The alternative is to accept those four items as verified by
inspection of the code plus ordinary-play screenshots.

---

## Q22 — `update_property` cannot assign an existing resource, and a CanvasLayer breaks the theme

Two things, one fix.

Spec §6.5 says to build `res://assets/theme.tres` and "assign it to `Main.theme` so every
descendant inherits it." That was done, but **theme inheritance walks the `Control` tree**, and
spec §3.3 puts the two modals under `ModalLayer`, a `CanvasLayer`. A `CanvasLayer` is not a
`Control`, so it severs the chain: `ShopModal` and `RunSummary` inherited nothing and rendered
in Godot's default theme. The shop was pale grey with unreadable text.

**Implemented:** `theme` is set explicitly on the `ShopModal` and `RunSummary` instances in
`main.tscn`, pointing at the same `theme.tres`. One source of truth, two extra assignments.

The second half: `update_property` parses `Vector2(...)`, `Color(...)` and scalars, but it has
no way to express "load this resource path", so it silently wrote `null`. **`main.tscn` was
therefore hand-edited** for those two lines — the only hand-edit of a scene made this session,
and worth flagging because §0.1.1 asks for `update_property` throughout. There is no
`load_resource_into_property` tool in this build.

**Question:** confirm the two explicit theme assignments, or would you rather `ModalLayer`
become a `Control` with a high `z_index` so §6.5's single-assignment rule holds literally?

---

## Q1 — `msaa_3d` = `2`, or 2× MSAA?

Spec §2 gives `rendering/anti_aliasing/quality/msaa_3d` the value `2`, annotated "(2× MSAA —
outlines need it)". In Godot the property is an enum: `0 = Disabled, 1 = 2×, 2 = 4×, 3 = 8×`.
The literal number and the parenthetical disagree.

**Implemented:** `msaa_3d = 1` (2× MSAA), following the stated intent over the literal.
**Question:** confirm 2×, or did you actually want 4× on the outline pass?

---

## Q2 — the spec's limb rotations are invisible to the spec's camera

This is the largest single deviation and I want it explicitly ratified.

§7.2 fixes `BattleCamera` at rotation `(0, 0, 0)`, a dead-on side view down −Z. Characters face
±X. Every limb key in §9 is written on **`rotation.x`** — e.g. warrior wind-up
`ArmR.rotation.x → -110°`. An X-axis rotation of a limb swings it in the **YZ plane**, i.e.
toward and away from the lens. From a dead-on side camera that motion is almost entirely
foreshortened: the sword wind-up would read as the arm barely moving.

**Implemented:** the same magnitudes, applied on **`rotation.z`**, which swings the limb in the
screen plane. Sign convention: negative = back/up (wind-up), positive = forward/down. This is
documented in the header of `scripts/battle/combatant_animations.gd`.

Two sub-cases where I also flipped the sign, because the spec's sign pointed the limb away from
the opponent under the new axis:

| Spec | Implemented | Why |
|---|---|---|
| Warrior defend `ArmL.rotation.x → -75°` | `rotation.z → +75°` | −75 raises the shield behind the warrior; +75 raises it in front, toward the enemy. |
| Orc melee "arms sweep to −95°" | `rotation.z → +95°` | The swing must travel forward/down into the target. |

**Question:** ratify the Z-axis convention (and re-author §9's keys against it), or was a
slightly angled camera always intended, which would make the X-axis keys read correctly?

---

## Q3 — forward-axis convention for enemies

§7.3 says enemies face −X via `rotation.y = PI` on the node (never negative scale). But §9.4's
shadow-monster lunge is written `Visual.position.x → -0.22 (toward heroes)`, which is only
"toward heroes" for an *unrotated* body. Applied under `rotation.y = PI` it lunges backwards.
§9.5's orc swing has the same issue (`Visual.position.x → -0.20`).

**Implemented:** all clips are authored in a single **"forward = local +X"** space, so one
authored animation reads correctly for both sides. Enemy X translations therefore carry the
opposite sign from the spec text (`+0.22`, `+0.20`).

**Question:** confirm. If you'd rather keep the spec's literal signs, the alternative is
separate hero and enemy clip sets, which doubles the M6 Blender authoring work.

---

## Q4 — `model_scale` on `Visual` collides with the squash/stretch tracks

§8.2 says `model_scale` is applied to `Visual.scale`. But §9.4 and §9.5 key `Visual.scale`
directly (shadow squash to `(1.12, 0.90, 1.12)`, orc stretch to `(0.92, 1.10, 0.92)`). Those
tracks are absolute, so the first frame of an orc's attack would wipe its 1.15× `model_scale`
and the 1.70× warlord would snap to human size mid-swing.

**Implemented:** `model_scale` lives on **`Rig.scale`**; `Visual.scale` is left free for
animation. `BarAnchor` / `HitAnchor` / `HandAnchor` are still positioned at
`spec_position × model_scale` exactly as §8.1 says, so nothing downstream changes.

**Question:** confirm, or would you rather the squash/stretch tracks be authored as multipliers
of `model_scale` (which requires per-character clips and breaks the shared-clip design)?

---

## Q5 — `run` and `special` are not built for every combatant

§8.3 opens with "Every combatant's AnimationPlayer must expose these exact animation names.
Missing ones are a build failure," then the table qualifies `run` as *heroes only* and `special`
as *warrior, ranger, priest*.

**Implemented:** the table's reading — enemies get `idle`, `attack`, `hurt`, `die` only.
`Combatant.play_anim()` no-ops on a missing name, so nothing crashes either way.

**Question:** confirm, or should stub clips exist for all six so an M6 Blender export can be
validated against a single fixed name list?

---

## Q6 — the warlord's "1.15× longer animation time scale"

§9.5 says the warlord plays the orc clips at "a 1.15× longer animation time scale so the bigger
body reads as heavier."

**Implemented:** `AnimationPlayer.speed_scale = 1 / 1.15 ≈ 0.87`, i.e. the clips take 1.15×
longer in wall-clock time. Note this makes the warlord's *impact* land ~63 ms later than its
`impact_delay` constant suggests, which is harmless today (nothing else keys off it) but is a
trap if impact timing ever gets compared across characters.

**Question:** confirm the slower reading (heavier), rather than `speed_scale = 1.15` (faster).

---

## Q7 — `demo_level.tres` vs the runtime-generated level

§3.1's directory tree requires `res://resources/levels/demo_level.tres`. §12.1 says to build the
`LevelDef` at runtime inside `GameState.reset_run()`, "so a future generator can replace that
one function." Those are two sources of truth for the same six encounters.

**Implemented:** both exist. `GameState.build_level()` generates the level in code and is what
actually runs; `demo_level.tres` is an authored snapshot with a header comment saying so.

**Question:** which is canonical? If the `.tres` is meant to be authoritative, `build_level()`
should load it and the seam for a future generator moves elsewhere.

---

## Q8 — cooldown accounting while attacking

§10.2's loop decrements `cooldown_remaining` for every living combatant every frame, including
one that is mid-attack, and then §10.2 step 6 *reassigns* `cooldown_remaining = attack_cooldown`
when the animation finishes. So the decrement during the attack window is discarded. §11.3
separately says the bar reads 0 while `state == ATTACKING`.

**Implemented:** exactly as written — decrement always, overwrite on finish, bar reads 0 during
the attack. The net effect is that a combatant's true cycle is `attack_length + attack_cooldown`,
not `attack_cooldown`. The stat table's cooldown numbers therefore understate real DPS interval
by 0.55–0.95 s depending on character.

**Question:** is that intended? If the cooldown is meant to *include* the animation, the balance
numbers in §5.2 want revisiting — the priest's real cycle is 2.95 s, not 2.0 s.

---

## Q9 — priest skip rule and the `% n` counter

§10.2 step 2 says that when the priest skips its special, decrement `action_count` by 1 so the
special is retained. With `special_every_n_actions = 3`, decrementing means the next action
re-increments to the same multiple of 3 and re-tests the condition — correct. But it also means
the priest's *primary* attacks no longer advance the counter while the party is at full HP, so a
long healthy stretch produces a heal on the very first action after anyone takes damage.

**Implemented:** as written. Flagging it because it makes the priest's heal feel reactive rather
than rhythmic, which may or may not be what you want.

---

## Q10 — simultaneous damage numbers

A bomb arrow (§9.2) or a 3× lightning payout (§16.5) applies damage to up to three enemies at
once. §11.4 spawns a floating number per `combatant_damaged`. Three 42 px numbers with 6 px
outlines land in a 640 px-tall viewport within a couple of frames of each other.

**Implemented:** lightning strikes are staggered 0.06 s apart (spec §16.5 asks for this), which
helps; the bomb arrow's three hits are simultaneous, which does not.

**Question:** should AoE damage aggregate into one number, or stagger the bomb like the
lightning does? Design pillar 1 is legibility.

---

## Q11 — dead heroes are hidden, not freed

§12.5 says a dead hero slides off-screen left and is "hidden and removed from the battlefield."
§10.4 says heroes "are not freed."

**Implemented:** the node is tweened to `x = -7.0`, then `visible = false`, and kept alive. It is
never freed until Retry. This keeps `director.heroes` index-stable, which the status panel's
three rows depend on.

**Question:** confirm that "removed from the battlefield" means visually removed, not freed.

---

## Q12 — the shop building has no home in the directory tree

§14.3 specifies a `shop_building` prop with an exact placeholder mesh, but §3.1's tree only lists
`scenes/battle/props/treasure_chest.tscn`.

**Implemented:** added `scenes/battle/props/shop_building.tscn` +
`scripts/battle/shop_building.gd`.

Other files added beyond §3.1's literal tree, all because the spec's behaviour requires them:
`scripts/battle/cel_materials.gd`, `combatant_rig.gd`, `combatant_animations.gd`,
`battle_vfx.gd`, `battle_world.gd`, `treasure_chest.gd`; `scripts/console/coin_glyph.gd`,
`buff_chip.gd`. §3.1 uses `...` for the console and modal script folders, so I read the tree as
a floor rather than a ceiling. **Question:** confirm.

---

## Q13 — modifier duplicates on one item

§13.1–13.2 say a Rare item rolls 3 modifiers from a 5-entry pool, but never says whether the
same modifier can be rolled twice ("+4 Damage" and "+7 Damage" on one sword).

**Implemented:** modifiers are drawn **without replacement**, so an item never lists the same
modifier id twice.

**Question:** confirm. Allowing duplicates would widen the value spread further.

---

## Q14 — the shop price spread is very wide

§13.3's own arithmetic gives buy prices from **27 to 697 gold**, and the spec says the spread is
deliberate so the graying-out logic gets exercised. With a single shop at encounter 3 and typical
gold on hand of 150–260, a rolled Rare staff is simply never purchasable in this demo.

**Question:** is an unbuyable card acceptable as a teaser, or should the shop's generation be
biased toward the affordable band for the demo?

---

## Q15 — the warrior's defend icon outlives the warrior

§9.1 keeps the shield status icon visible for the full `WARRIOR_DEFEND_DURATION` (4 s). Nothing
in the spec cancels it if the warrior dies during those 4 seconds.

**Implemented:** the icon plays out its full 4 s over a corpse.
**Question:** should the icon be cancelled on death?

---

## Q16 — outline fading

§6.2's inverted-hull outline shader is `unshaded` with no alpha uniform, so it cannot fade with
the body during the enemy fade-in (§10.1) or death fade (§10.4). Fading only the body leaves a
solid ink silhouette floating on the battlefield.

**Implemented:** `CelMaterials.set_alpha()` scales `outline_width` proportionally with alpha, so
the outline shrinks to nothing as the body fades. It is an approximation, not a true fade.

**Question:** acceptable, or should `outline.gdshader` gain a `blend_mix` + alpha uniform?

---

## Q17 — the slot machine dims mid-encounter, then the run continues

§16.6 dims the cabinet to `Color(0.55, 0.55, 0.62)` whenever combat is not active. That means it
sits dimmed through travel, the loot encounter and the entire shop encounter — which is most of
the demo's runtime. Design pillar 2 says "the console is always doing something. Dead air is a
bug."

**Question:** these two rules pull against each other. Is a dimmed, still cabinet during the
shop the intended read, or should the slot keep spinning cosmetically (no payouts) so the
console never goes quiet?

---

## Q18 — still unresolved from §21-D16: there is no fish

The game is called *Sir Fish* and contains no fish, no water, and no aquatic reference anywhere
in the spec. §21-D16 records this as deliberately unresolved and asks the owner to decide rather
than have an implementer invent fish content. I did not invent any.

**Question:** working title, or is a fish supposed to exist somewhere in the demo?

---

## Q19 — the bomb arrow is visually identical to the arrow until impact

§9.2 gives the ranger's special the same draw/release animation and the same flight path as the
primary; the only difference before impact is the powder bag, fuse spark and fuse light on the
projectile itself, at roughly 0.3 world units across in a 640 px-tall viewport.

**Question:** is that enough telegraph? A player watching the top third may not register that a
special is incoming until the explosion. A tinted trail or a brief cast flash on the ranger would
read from across the screen.

---

## Q20 — typography at 1080 × 1920

§6.5 forbids shipping font files, so everything uses Godot's built-in default font at the sizes
in §15/§17. The default font is a small, thin sans that was never designed to carry an 84 px
"DEFEATED" or to sit next to the "bold, flat, primary" art direction of §1.1 pillar 4.

**Question:** the no-third-party-assets rule (§0.1.2) is about *art*. Does it also forbid a font,
or would a generated/permissively-licensed display face be in scope for M6?

---

## Q23 — the shop's affordability spread, with real numbers

Q14 asked whether the 27–697 gold buy-price spread is too wide. There is now data. Over 200
generated items (`res://tests/test_item_distribution.tscn`):

- item value: min **18**, median **41**, max **388** → buy price min **27**, median **62**, max **582**
- gold on hand at the encounter-3 shop, observed across three runs: **50, 50, 100**

So the spread itself is fine — the median card costs 62 gold and is comfortably buyable. The
real problem is the other half of §13.3's assumption: it predicted "typical gold on hand at the
first shop of roughly 150–260", and the observed figure is **50–100**. Gold comes only from the
slot's GOLD payouts, which pay 25 or 50 and land on roughly 1 spin in 6; two combat encounters
give ~14 spins, so ~2 gold payouts, and a run can easily reach the shop having earned nothing.
Two of the three observed runs bought nothing because nothing was affordable.

**Question:** this is a balance call, not a bug. Raise `SLOT_PAY_2_GOLD` / `SLOT_PAY_3_GOLD`,
raise `STARTING_GOLD`, or accept that the first shop is often window-shopping and the player is
meant to sell loot to afford anything? Selling the two chest items covers 20–80 gold, which is
what actually funds the shop today.

---

## Q24 — the run-summary slot-win percentage reads low on short runs

§18.2 says the win % on the summary "doubles as a live sanity check on §16.2 — it should hover
near 50%." An observed defeat run reported **7 wins / 21 spins = 33.3%**.

That is not a defect: 21 spins is a tiny sample (1σ ≈ 11%), and the authoritative
1,000,000-spin test reports 0.50001. But a player reading 33% on the summary will conclude the
slot is rigged against them, which is exactly the opposite of the reassurance §18.2 wants.

**Question:** leave it, or drop the percentage from the summary and keep the raw win count?

---

## Verification status (spec §20)

Checked against the running game in session 2 unless marked otherwise.

| Milestone | Verified | Still owed |
|---|---|---|
| M0 | Region split correct in a screenshot (divider at y 640–648, console below); `get_project_info` reports 1080×1920 viewport / 540×960 window, forward_plus, main scene; **zero editor errors and zero warnings across a full run** | — |
| M1 | Three heroes in priest/ranger/warrior order, enemies right, cel-shaded with visible dark outlines, all idling; parallax scrolls and eases; layer 5 is at z = +3 in front of characters; shadow monsters render with emissive red eyes and smoke | Forced playback of each of the six animations per character, and confirming `die` holds its final pose — blocked on **Q21** |
| M2 | Full hands-off fights run to completion; bars track heads and pop in; damage numbers float; priest bolt, defend shield icon, heal `+N`, slot lightning all fire; heroes die and are marked DEAD; no crashes across ~6 minutes of play | The exact 100 HP / 20 damage chunk case, and killing a ranger target mid-flight — blocked on **Q21** |
| M3 | **1,000,000-spin test PASS at 0.50001**; exhaustive enumeration reproduces 9,849 / 19,683; cabinet shows three symbols per reel and one centre payline; symbols read correctly; win banner and pulse fire; slot dims outside combat and undims on `combat_started` | Forcing each of the six payouts individually — blocked on **Q21**. Lightning-excluded-from-buffer is correct by inspection (`take_damage(rolled, null)`) but unforced |
| M4 | Encounters 0–5 play hands-off; background eases to a stop; heroes switch run↔idle; chest pops, opens and grants **exactly 2** items; dead hero slides off and does not reappear; shop building pops in | — |
| M5 | **200-item split 50.0 / 27.5 / 16.0 / 6.5**; shop cards gray out when unaffordable and re-evaluate live on every gold change; purchase writes `SOLD!` and grays the card; Sell tab lists `sellable_items()` with working sell buttons; party damage button drains 720 → 0 px over 30 s and is disabled throughout, then re-enables; game over summary shows all ten stats; **Retry fully resets** HP, gold, inventory and encounter index | §15.2's exact 200/250/300-vs-350 scenario (blocked on **Q21**); the `equipped` filter with an item actually flagged equipped; three *consecutive* retries — only one was run |
| M6 | Only §19.1's scaffold: the default `Cube` is deleted and the `Heroes` / `Enemies` / `Props` / `Environment` collections exist in `blender/Sir Fish.blend` | All modelling, all rigging, all six animation actions per character, glTF export, the Godot-side rig swaps, and the §19.4 environment tiles |

---

## Fixed in session 2

Recorded here because they were all latent in the first session's code and none of them are
design questions.

| Where | Problem | Fix |
|---|---|---|
| `scenes/modals/shop_modal.tscn` | The script was declared as an `ext_resource` but **never assigned to the root node**, so `shop_modal.open()` threw "Nonexistent function 'open' in base 'Control'" and the shop encounter hung forever — the run could not get past encounter 3 | Attached via `attach_script` |
| `shop_buy_card.tscn`, `shop_sell_row.tscn` | The 12 px rarity `Edge` was a direct child of a `PanelContainer`, which force-resizes every child to fill it — the edge covered the whole card | Edge and Layout moved into an `HBoxContainer`; edge given `custom_minimum_size = (12, 0)` |
| `main.tscn` | Modals under `ModalLayer` inherited no theme (see **Q22**) | `theme` assigned on both modal instances |
| `scripts/console/inventory_strip.gd` | Chips were tweened on `position:x` while inside an `HBoxContainer`, so every chip ended parked at x = 0, stacked on top of the others | Animated node moved inside a container-managed slot |
| `scripts/console/inventory_strip.gd` | `reset_run()` clears the inventory array without emitting `item_removed`, so chips survived a Retry | Strip now rebuilds on `EventBus.run_started` |
| `scripts/battle/cel_materials.gd` | `flash()` read the live albedo as the "original" colour. Two overlapping flashes latched white in permanently, so after a couple of fights every character was a white silhouette | Base colour remembered once via `set_meta("base_albedo")` |
| `slot_symbol.gd`, `status_icon.gd`, `buff_chip.gd` | `const X := PackedVector2Array([...])` is not a constant expression in GDScript 4.7 — these scripts failed to parse, which cascaded into `SlotSymbol` not registering as a global class | Changed to `static var` |
| `ability.gd`, `battle_overlay.gd`, `battle_director.gd`, `slot_machine.gd`, `run_controller.gd`, `run_summary.gd`, `inventory_strip.gd` | `var x := <call on an untyped variable>` cannot infer a type and is a hard parse error | Explicit type annotations |
| `game_state.gd` | `run_stats[key] = 0.0 if key == "run_time" else 0` — incompatible ternary | Explicit branch |
| `event_bus.gd` | Every signal tripped UNUSED_SIGNAL, since they are all emitted from other files | `@warning_ignore_start("unused_signal")` for the file |
| `parallax_background.gd` | A parameter named `scale` shadowed `Node3D.scale`; `_build_ground`'s `variant` was unused | Renamed |
| `run_summary.gd` | Integer division warning in `_format_time` | Annotated and split |

Added: `res://tests/test_item_distribution.tscn` + `.gd`, the M5 rarity/value gate, runnable
headless the same way `test_slot_odds.gd` is.

**Not a defect, checked and cleared:** the `ERROR: Class name cannot be empty.` lines that
appear in the output log are emitted by the Godot MCP addon's own runtime inspector while it
reflects over script-based nodes. They never appear during play that is not being queried over
MCP. Do not go hunting for them in game code.
