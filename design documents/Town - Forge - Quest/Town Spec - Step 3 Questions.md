# Town Spec — Step 3 Implementation Questions

Raised while implementing §14 step 3 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("**§10 — the `ENHANCED` rarity**, all five arrays, weight
0. Run the full suite; nothing should move.").

Step 3 is the smallest step in the document by design — its acceptance bar is
literally "nothing should move." That framing is doing more work than it looks
like, and **Q1 is the whole question**: does "§10" mean all of §10, including the
forge function, or just §10.1's five arrays? Everything else is a consequence of
that answer.

**All six are answered below, and every answer has been folded back into the
spec.** Five were resolved as implemented. **Q3 was extended** — the ruling
covers one more call site than was changed, and that is the only code change
these answers produced, alongside one test addition that came out of Q1's
reasoning rather than its verdict.

---

## Q1. "§10" in the build order — the arrays only, or the forge too?

§14 step 3 says "**§10** — the `ENHANCED` rarity, all five arrays, weight 0.
**Run the full suite; nothing should move.**" But §10 has five subsections, and
only §10.1 is "five arrays, weight 0". §10.2 is `Itemizer.forge()`; §10.3 is
`_roll_modifier()` and the `enhanced` flag; §10.5 is the value rule inside
`forge()`. §13.1 lists `test_forge.gd` as a new test with no step attached.

So: does step 3 land `forge()` and `test_forge.gd`, or just the arrays?

### Answer — **§10.1 only, confirmed.** `forge()` and `test_forge.gd` defer to step 9

The verdict is right and the dependency analysis is correct — verified: none of
`add_scrap`, `spend_scrap`, `scrap_changed`, `items_forged`, `item_forged`,
`FORGE_COSTS` or `FORGE_ENHANCED_MULT` exists anywhere in `scripts/`. `forge()`
as §10.2 writes it cannot compile today, and the two ways to make it compile are
both bad: front-load the entire §5 currency API four steps early, or deduct
scrap inline with `GameState.scrap -= n`, bypassing the `scrap_changed` contract
§2.2 gives it, to be rewritten at step 9. Reason 3 is the strongest of the three
and should have led.

**But the strongest objection to deferring went unexamined, and it is worth
recording because answering it changed the test.** §0.4 lists the forge ladder as
one of four resolved forks: four steps rather than three, chosen *specifically*
to preserve `modifiers.size() == RARITY_MOD_COUNT[rarity]`. §10.2 calls that
"the point of four steps rather than three". Deferring `test_forge.gd` to step 9
appears to leave the pass's central rarity claim unverified for six steps — and
if it turned out to be wrong, it would be discovered underneath a finished
blacksmith screen.

That objection dissolves on inspection, and the reason is useful: **the claim
does not need `forge()` to test.** Each rung raises rarity by one and adds one
modifier, so the invariant holds exactly when every adjacent pair of
`RARITY_MOD_COUNT` differs by one. That is arithmetic on an array literal,
testable at step 3 with nothing else in existence. `test_enhanced_rarity.gd` now
asserts it:

```gdscript
for r: int in range(Item.Rarity.ENHANCED):
    if int(Itemizer.RARITY_MOD_COUNT[r + 1]) != int(Itemizer.RARITY_MOD_COUNT[r]) + 1:
        ladder_ok = false
```

So the design claim is pinned now, at the moment its fix is a one-line array
edit, and only the parts that genuinely require spending — the arbitrage gate,
"insufficient scrap spends neither", the refund path — wait for step 9. Folded
into §10.2 and §13.1.

The original three reasons, all sound:

**1. "Nothing should move" is the acceptance bar, and it is exact for §10.1.**
Adding a fifth enum value, a fifth entry to three arrays and a fifth colour,
plus tightening one `clampi` literal into the enum name it already meant — that
is purely additive. No behaviour changes, no test changes, the whole suite
passes untouched. That is what step 3 is described as being. `forge()` is not
that: it adds a `run_stats` key, an `EventBus` emission, and a spend path.

**2. `forge()` has hard dependencies on three later sections.** Its body, as
written in §10.2:

| line | needs | introduced by | build step |
|---|---|---|---|
| `GameState.spend_scrap(int(cost[0]))` | `GameState.spend_scrap` / `add_scrap` | §2.2 / §5 | **step 9** — §14 step 1 explicitly shipped "no `add_scrap`/`spend_scrap`" |
| `EventBus.item_forged.emit(...)` | the signal | §3.3 | **step 5** |
| `run_stats["items_forged"] = ...` | the stat key | §5.4 | **step 9** |
| `Tuning.FORGE_COSTS[...]`, `FORGE_ENHANCED_MULT` | the constants | §11 | (added when first needed) |

Landing `forge()` at step 3 means front-loading `add_scrap`/`spend_scrap` (the
entire §5 currency API), the `item_forged` signal, and the `items_forged` stat
key — three sections' worth of surface, out of order, so that one function three
steps early can compile.

**3. The alternative — a bootleg scrap deduction — is exactly what the build
order forbids.** Without `spend_scrap`, `forge()` would have to write
`GameState.scrap -= cost[0]` inline, bypassing §2.2's `scrap_changed` contract,
to be rewritten at step 9. `test_forge.gd`'s "insufficient scrap returns false
and spends neither" and its arbitrage gate both need real scrap spending to
mean anything. A throwaway deduction now, replaced in a later step, is the
churn §14's "do not start the next until the previous is green" exists to
prevent.

**Where they land instead.** `forge()`, `_roll_modifier()`,
`_modifier_pool_excluding()`, `FORGE_COSTS`, `FORGE_ENHANCED_MULT`, the
`run_stats["items_forged"]` key, and `test_forge.gd` all move to **step 9**
(§5 — scrap), where `spend_scrap` is born and `EventBus.item_forged` (from step
5) already exists. §7.3's blacksmith screen at step 10 then just *calls* a
`forge()` that already exists and is already tested. §10.3's display rule (every
modifier line drawn in the ENHANCED colour) is UI and follows the screens that
render it — steps 6, 10.

**Spec amendments — made:**

- §14 step 3: "§10" → "**§10.1**", with the reason the bare reference misled;
- §14 step 9: absorbs §10.2, §10.3, `test_forge.gd` and §11's forge constants,
  with the within-step ordering spelled out (currency API → `forge()` → test);
- §10.2: a paragraph on why the ladder claim is testable at step 3 and what
  actually has to wait;
- §13.1: `test_forge.gd` marked as step 9; `test_enhanced_rarity.gd` added.

---

## Q2. §13.1 names no test for §10.1, but step 3 ships `test_enhanced_rarity.gd`

`test_forge.gd` is §13.1's only §10 test, and per Q1 it defers to step 9. That
would leave step 3 with no assertion of its own — only "the suite still passes".

### Answer — new pinning test, same tradition as steps 1 and 2

Step-1 Q5 settled this shape: *"a step that buys isolation and then ships no
assertion of its own has spent the isolation and not collected."* Step 1 added
`test_profile_expedition.gd`; step 2 added `test_profile_save.gd`; step 3 adds
**`tests/test_enhanced_rarity.gd`** (17 checks):

- `Item.Rarity.ENHANCED == 4`, `RARE` still `3` (appended, not inserted);
- all five rarity-indexed arrays are length 5;
- `RARITY_WEIGHTS[ENHANCED] == 0`, `RARITY_MOD_COUNT[ENHANCED] == 4`;
- `rarity_name()` / `rarity_color()` cover ENHANCED; its colour is distinct from
  the four rolled rarities;
- **the mechanism, asserted directly**: `RNG.weighted_index([50,30,15,5,0])`
  never returns index 4, over 20 000 draws — so a future rewrite of
  `weighted_index()` that breaks the trailing-zero property fails *here*, loudly,
  instead of by leaking ENHANCED gear into a chest;
- `generate_item()` never rolls ENHANCED over 4 000 samples, and its mod-count
  still matches rarity with the widened `RARITY_MOD_COUNT` (the
  `test_item_distribution.gd:68` invariant, pre-checked against the change);
- `generate_item_with_rarity(ENHANCED)` and `(999)` both clamp to RARE;
- `generate_drop(c, 99)` clamps its floor below ENHANCED.

### Confirmed, and it gained the assertion Q1's reasoning produced

Added to §13.1 with its checks listed. Two of them are worth more than the rest
and the section now says why:

- **the `weighted_index()` mechanism check.** §10.1's entire forge-only
  guarantee rests on a property of a function in a *different file* — that
  `weighted_index()` never returns a trailing zero-weight index. Asserting the
  mechanism rather than only the outcome means a future rewrite of `rng.gd`
  fails in this test, loudly, instead of by quietly leaking Enhanced gear into a
  chest where it would read as a lucky drop.
- **the ladder-arithmetic check** added per Q1 above.

The rest — enum indices, array lengths, the clamps — are the "nothing moved"
bookkeeping, and they are cheap.

---

## Q3. §10.1 names only `generate_item_with_rarity()` for the clamp; I changed `generate_drop()` too

§10.1: *"clamp `generate_item_with_rarity()`'s input to `Item.Rarity.RARE`
rather than the literal `3` it uses today, so the guard says what it means."*

`itemizer.gd` has the identical guard in a second place —
`generate_drop()`'s `maxi(RNG.weighted_index(RARITY_WEIGHTS), clampi(rarity_floor, 0, 3))`
— and a third, in `debug.gd`'s `_parse_rarity()`.

### Answer — **extended.** `generate_drop()` was right; `debug.gd` should change too

`generate_drop()` is in-bounds and correct, for exactly the reason given: same
file, same meaning, and it sits directly under a `weighted_index(RARITY_WEIGHTS)`
call whose array just grew a fifth entry. A reader hitting a bare `3` there has
to stop and work out whether index 4 is reachable; the enum name answers it
inline. That is §10.1's own rationale applied to the guard §10.1 happened not to
name.

**`debug.gd:_parse_rarity()` should change as well**, and the argument for
leaving it inverts on a closer look. The reasoning offered was that its clamp is
a generic "any integer a tester typed, capped" rather than a rarity guard. But
look at what that cap actually *does*: it is the thing that stops
`item 4` spawning an Enhanced item. That is not incidental capping — it is the
sole enforcement point of Q5's rule, that no debug verb may mint an Enhanced
item directly. A rule enforced by a bare `3` is a rule that is invisible at the
line enforcing it, and the next person to add a rarity to the harness will not
know it is there.

Changed, with the rule named in a doc comment, including the detail that the
absence of an `"enhanced"` case is deliberate rather than an omission
(`int("enhanced")` is 0, so the token yields Common).

All three guards were already safe with the literal — nothing *moved* in any of
them. §10.1 now lists all three rather than one, so this does not have to be
rediscovered as a judgement call.

---

## Q4. `RARITY_VALUE_MULT`'s ENHANCED row is dead code the spec asked for

§10.1: *"`[6.5, 8.0]` … never actually used — forging does not recompute value
from this table (§10.5) — but the array must be the same length as the others or
an index is wrong."*

Added as written, with an inline `# ENHANCED - never read, present for length
parity` comment so it does not read as an oversight later. `_generate_typed()`
indexes `RARITY_VALUE_MULT[rarity_index]` with `rarity_index` clamped to RARE,
so the row is genuinely unreachable today; §10.5 keeps it unreachable after the
forge lands (forging does `item.value += gold_cost`, never a table lookup).
Recorded, not flagged.

---

## Q5. `debug.gd` gets no `item enhanced` case

### Answer — correct, and it is now written down where it is enforced

Deliberate and right. §10.1 makes Enhanced forge-only; a debug verb that mints
one directly would contradict the one rule the whole rarity exists to enforce.
The intended harness route is §13.4's `forge <weapon|armor|trinket>` verb, which
lands with `forge()` at step 9.

The gap was that this rule lived only in a questions document. Per Q3 it is now
a doc comment on `_parse_rarity()` itself and a paragraph in §10.1 — including
the part that reads like a bug otherwise: `item enhanced` yields **Common**, not
Rare, because the token falls through to `int("enhanced")` = 0. Someone will
type that command, see a Common, and file it. Now the answer is at the function.

---

## Q6. `test_item_distribution.gd` has a 4-wide `by_rarity` array that an ENHANCED item would overflow

`var by_rarity := [0, 0, 0, 0]` … `by_rarity[item.rarity] += 1`. A rarity-4 item
would be an out-of-bounds write. The file is on §13.2's "Edited in step 4" list
but runs **unedited** at step 3.

### Answer — safe at step 3, and step 4 must widen it; now in §13.2

Correct that it is safe: weight 0 means `generate_items()` never yields a
rarity-4 item, and `test_enhanced_rarity.gd` pins exactly that.

Worth being precise about *why* it still needs fixing rather than filing as a
non-issue. This is a four-wide array indexed by a five-value enum, and the only
thing between it and an out-of-bounds write is a single weight — a weight this
pass deliberately makes editable, in a table a future balance tweak will
absolutely revisit. "Safe because a number in another file is currently zero" is
a fine reason not to panic at step 3 and a bad reason to leave standing.

Moved out of this document and into **§13.2**, as a required part of step 4's
already-scheduled edit to that file, so it is an instruction rather than a note
someone has to remember to reread.

---

## What step 3 ships

- **`scripts/data/item.gd`** — `Rarity` enum gains `ENHANCED` (index 4);
  `rarity_name()` gains `"Enhanced"`.
- **`scripts/autoload/tuning.gd`** — `RARITY_COLORS` gains `Color("FF6B4A")`
  (forge-hot red-orange, index 4).
- **`scripts/autoload/itemizer.gd`** — `RARITY_WEIGHTS` → `[50,30,15,5,0]`,
  `RARITY_MOD_COUNT` → `[0,1,2,3,4]`, `RARITY_VALUE_MULT` gains `[6.5,8.0]`
  (Q4); `generate_item_with_rarity()` and `generate_drop()` clamp to
  `Item.Rarity.RARE` instead of the literal `3` (Q3).
- **`scripts/autoload/debug.gd`** — `_parse_rarity()`'s clamp becomes
  `Item.Rarity.RARE`, with the forge-only rule and the `item enhanced` → Common
  behaviour documented at the function (Q3, Q5).
- **`tests/test_enhanced_rarity.gd` + `.tscn`** — new, 18 checks (Q2), including
  the ladder-arithmetic assertion Q1's reasoning produced.
- **`scripts/autoload/game_state.gd`** — one stale doc-comment line fixed
  (`new_profile()`'s header still said "then writes the save", contradicting the
  step-2 Q4 no-persist rule directly below it). No behaviour change.

**Not shipped, deferred to step 9 (Q1):** `Itemizer.forge()`,
`_roll_modifier()`, `_modifier_pool_excluding()`, `Tuning.FORGE_COSTS`,
`FORGE_ENHANCED_MULT`, `run_stats["items_forged"]`, `EventBus.item_forged`,
`tests/test_forge.gd`.

**Verified** (headless, `Godot_console.exe --headless --path . res://tests/<name>.tscn`):
all thirteen suites `RESULT PASS` — `test_enhanced_rarity` (18),
`test_item_distribution` (5), `test_economy` (13), `test_drops` (19),
`test_profile_save` (17), `test_profile_expedition` (28), `test_autoload_safety`
(9), `test_slot_odds` (11), `test_upgrades` (53), `test_endless_level_gen` (60),
`test_retarget` (8), `test_parallax_seam` (11), `test_damage_chunk` (26).
**278 checks, 0 failures.** Zero edits to any test on §13.2's or §13.3's lists —
"nothing moved".

**Spec amended**: §10.1, §10.2, §13.1, §13.2, §14 steps 3 and 9.

**Step 3 is complete. No further work.**

---

## Next: step 4 — §4, three slots

Unblocked. §4 depends on nothing from §3, §5 or §7, and it is the last step
before the player-visible work starts. Two hazards, both already recorded and
both easy to miss:

- **The value flip is the edit that matters** (step-1 Q6). §4.5 lists three call
  sites that switch from `PARTY_ORDER` to `active_party`. Doing all three
  changes *nothing* — they would all be reading a variable that still equals
  `PARTY_ORDER`. The edit that actually makes the party solo is `active_party`'s
  initialiser **and** `new_profile()`'s matching assignment going to
  `[&"warrior"]`. One of the three call sites (`_reset_hero_runtime`) is already
  done, from step 1.
- **`grep -rn "equipped_item" scripts/`** before declaring §4.3 finished — the
  signature grows a `slot` argument, so every caller is a compile error waiting
  to happen, and `compare_flyout.show_for()` is the one §1.8 says is already
  wrong today.

Test surface, the largest of the pass: `test_drops.gd:23` flips to
`GameState.active_party`; `test_item_distribution.gd` gets re-derived type-mix
expectations **plus** the four-to-five array widening (§13.2, Q6 above); and
`test_profile_expedition.gd` takes its second scheduled edit, the
`active_party` check.
