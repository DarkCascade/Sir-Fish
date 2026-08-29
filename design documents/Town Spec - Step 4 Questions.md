# Town Spec — Step 4 Implementation Questions

Raised while implementing §14 step 4 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("**§4 — three slots**: `Item.slot()`, `ITEM_TYPES`, the
slot-aware `equipped_item()`, the `compare_flyout` fix, slot-first generation.
Update `test_drops.gd` and `test_item_distribution.gd`").

Step 4 is the last invisible step — no player-facing UI, everything gated by
tests — but it has the **largest test surface of the pass** (step-3 Q "Next"
note) and the spec's own pseudocode disagrees with itself in one place (Q4).
Nothing here is a design fork; §0.4 settled solo-warrior and three slots. These
are implementation gaps: names the spec uses without defining, call sites §4.3
tells me to grep for, and test edits §13.2 gestures at without spelling out.

Three of the eleven turned out to be places where the spec was **wrong** rather
than merely silent — §4.4's two contradictory slot rolls (Q4), §13.2's two edits
wearing one sentence (Q3), and the four `test_drops.gd` checks nobody had counted
(Q11) — which is the argument for the questions pass existing at all.

**All answered — every recommendation accepted, and folded into the spec.** One
question was added during the answering pass: **Q11**, `test_drops.gd` D4 and D9,
which the original Q10.4 got wrong. Each answer below names the spec section it
landed in.

| Q | answer | spec |
|---|---|---|
| Q1 | clean cut, no alias | §4.2 |
| Q2 | yes, in step 4's scope; D7 re-derived as slot-share + within-slot uniform + zero bow/dagger/staff | §13.2 |
| Q3 | confirmed; §0.3 and §13.2 now name the two files separately | §0.3, §13.2 |
| Q4 | yes, collapse both formulations onto `_equippable_slots_for()`; guard kept, retargeted | §4.4 |
| Q5 | names adopted verbatim, plus `_roll_typed()` | §4.4 |
| Q6 | `equipped_set()` in the `state` line, not WEAPON-only | §4.3 |
| Q7 | yes, `kind = WEAPON` for every generated item, recorded as a wart | §4.1 |
| Q8 | wording accepted as written | §13.2 |
| Q9 | yes, and added to §13.2's edited-tests list | §13.1, §13.2 |
| Q10 | 1–3 accepted; 3 also recorded in §15; **4 corrected — see Q11** | §14, §15 |
| Q11 | D4/D9 save-override-restore `active_party`, not re-point | §4.5, §13.2 |

---

## Q1. `WEAPON_TYPES` → `ITEM_TYPES`: keep the deprecated alias, or clean cut?

§4.2: *"`WEAPON_TYPES` may be kept as a deprecated alias for exactly one commit
if that eases the migration; it must not survive the branch."*

The live references are few and all get touched this step anyway:

| site | use |
|---|---|
| `itemizer.gd` | the `const` itself, plus 6 internal reads (`.keys()`, `[wtype]["nouns"]`, `["base_value"]`, `weapon_types_for()`'s loop) |
| `item.gd:91` | `usable_by()` reads `Itemizer.WEAPON_TYPES.get(weapon_type, {})` |
| `test_drops.gd:80,85` | D7 iterates `Itemizer.WEAPON_TYPES.keys()` — and D7 is being rewritten regardless (Q2) |

That is one production file, one helper on `item.gd`, and a test block already
on the edit list. No third-party or scene-file references.

### Recommendation — **clean cut, no alias.**

Rename `WEAPON_TYPES` → `ITEM_TYPES` in the same commit, update all six internal
reads plus `item.gd:91`, and fold D7's loop into its rewrite. An alias that
"must not survive the branch" is a second cleanup commit to remember on a
rename this small; the grep is bounded and the compiler finds every miss.

### Answer — accepted. Clean cut.

The reference count was verified against the tree: `itemizer.gd` (the `const`
plus six reads at lines 71, 84, 112, 123, 124), `item.gd:91`, and
`test_drops.gd:80,85`. Nothing in `scenes/`, no `.tres`. Folded into **§4.2**,
replacing the "deprecated alias for exactly one commit" sentence.

---

## Q2. `test_drops.gd` D7 asserts a 20% per-type share — what does it become?

§13.2 names only `test_drops.gd:23` (the `droppable_classes()` assertion). But
D7 (`test_drops.gd:77-88`) is a hard `check_between(pct, 16.0, 24.0)` on **every
type's** share of `generate_item()` output, and slot-first generation with a
solo warrior blows straight through it:

- `_random_equippable_slot()` picks WEAPON / ARMOR / TRINKET at 1/3 each;
- within-slot, the warrior can wield **axe, sword** (WEAPON), **helm, mail,
  shield** (ARMOR), **ring, amulet, idol** (TRINKET);
- so: axe, sword ≈ **16.7%** each; the six armor/trinket types ≈ **11.1%** each;
- bow, dagger, staff ≈ **0%** — no active-party member can wield them (§4.4,
  the §1.6 fix).

Every one of those is outside D7's 16–24 band, and D7 also iterates the
renamed constant (Q1).

### Recommendation — re-derive D7 as a **slot-share + within-slot-uniform** check

Replace the per-type band with:

- **slot share**: WEAPON / ARMOR / TRINKET each 33.3% ± 3pp over ~6000 samples
  (`item.slot()` on each generated item);
- **within-slot uniformity**: among the types actually rolled, each is
  `1 / n_types_in_slot` ± 3pp;
- **the §1.6 guarantee, asserted directly**: bow, dagger and staff appear
  **exactly zero** times — this is the regression guard D7 was always meant to
  be, now pointed at the thing slot-first generation is *for*.

This keeps D7's spirit (generation is evenly spread, no type is starved or
flooded) while matching what §4.4 actually produces. **Is a slot-first D7 in
step 4's scope, or do you want it pulled into its own follow-up?** I read
§13.2's "update `test_drops.gd`" as covering it.

### Answer — accepted, in step 4's scope, all three parts.

Not a follow-up: D7 does not merely go stale under §4.4, it goes **red**, and
§14 says each step leaves the game green before the next begins. A step that
lands slot-first generation and leaves five failing checks behind has not left
the game runnable in the sense §14 means.

The zero-count assertion on bow / dagger / staff is the part worth keeping
longest: it is the only place §1.6's guarantee is stated as a test rather than as
prose, and it survives the mage's return unchanged in *meaning* (it becomes
"types no active-party member can wield never generate") even though the literal
type list would then need editing — which is the right kind of test to have to
edit.

Sample sizing checks out at 6000: the tightest band is the 11.1% within-slot
share, where σ ≈ 0.41pp, so ±3pp is a ~7σ gate and will not flake.

Folded into **§13.2**.

---

## Q3. §13.2 bullet 2: which file gets "re-derived type-mix expectations"?

§13.2: *"`test_item_distribution.gd` — type-mix expectations re-derived for
§4.4's slot-first roll. The mod-count assertion at line 68 does not change …
widen its `by_rarity`, `names` and `expected` arrays from four entries to five."*

But `test_item_distribution.gd` **asserts no type mix at all** — it reports the
rarity split (informational `print`, not `check`), checks dup-modifier /
missing-roll / pool-size / mod-count / element-tie. The only *type*-distribution
assertion in the whole suite is D7 in `test_drops.gd` (Q2). So bullet 2 appears
to be two edits wearing one sentence.

### Recommendation — read §13.2 bullet 2 as:

- **`test_drops.gd`** gets the type-mix re-derivation (D7, per Q2) **and** the
  line-23 flip;
- **`test_item_distribution.gd`**'s *only* step-4 change is the four-to-five
  widening of `by_rarity` / `names` / `expected` (the §13.2 / step-3 Q6 array
  trap) — `[0,0,0,0]` → `[0,0,0,0,0]`, `names` gains `"Enhanced"`, `expected`
  gains `0.0`, and the `range(4)` report loop becomes `range(5)`.

No new type-distribution *test* is added to `test_item_distribution.gd` unless
you want one. **Confirm this split**, and I'll reword §13.2 so the two files are
named separately.

### Answer — confirmed. The reading is right and the spec was wrong.

Verified: `test_item_distribution.gd` has no `check` on type at all — its rarity
split is an informational `print` (lines 26–32) and every `check` in the file is
about duplicate modifier ids, missing rolls, pool size, mod count, or the
fire/ice element tie. So bullet 2 was indeed two edits wearing one sentence.

No new type-distribution test is added there; D7 is the suite's one home for it.
**§13.2** now lists `test_drops.gd` and `test_item_distribution.gd` as separate
bullets with separate edits, and **§0.3**'s "two tests do need edits" — which
carried the same conflation — is corrected to four, all landing at step 4.

---

## Q4. Slot roll: filter to fillable slots, or uniform-3 with a WEAPON fallback?

§4.4's pseudocode does it **two different ways** in two adjacent paragraphs:

```gdscript
# generate_item_with_rarity(): uniform over 3, then fall back if empty
var slot: Item.Slot = _random_equippable_slot()
var types := types_for_slot(slot, GameState.active_party)
if types.is_empty():
    types = types_for_slot(Item.Slot.WEAPON, GameState.active_party)
```

vs. prose for `generate_drop()`: *"keeps picking the class first and now picks
the slot second, then the type … a drop is always something the target class
can wield."*

For a **solo warrior** the two are identical — every slot has ≥2 warrior types,
the fallback is dead code. They diverge for **mage / ranger**, and
`test_drops.gd` D1 still exercises those: it loops `GameState.PARTY_ORDER`
(unchanged, 3 classes) calling `generate_drop(&"mage")` / `(&"ranger")` 1000×
each and asserts `.usable_by().has(c)`. Mage has only `staff` (WEAPON); ranger
has `bow`, `dagger` (WEAPON). A uniform-3 slot roll for `generate_drop(&"mage")`
lands on ARMOR/TRINKET 2/3 of the time — and there is no per-class armor to fall
back to, only the party-wide WEAPON fallback, which for a single-class call is
just "give up on slots".

### Recommendation — **one shared helper, filter to non-empty slots**

`_equippable_slots_for(classes: Array[StringName]) -> Array[Item.Slot]` returns
the slots that have ≥1 type wieldable by *some* class in `classes`; roll
uniformly over **that**. Then:

- `generate_item_with_rarity()` passes `GameState.active_party` → `[WEAPON,
  ARMOR, TRINKET]` for the solo warrior, so nothing changes for the visible
  case;
- `generate_drop(hero_class, …)` passes `[hero_class]` → `[WEAPON]` for mage and
  ranger, so D1 stays green with no fallback branch and no `usable_by()` misses;
- the `if types.is_empty()` fallback in §4.4's snippet becomes unreachable
  (keep it as a guard, or drop it — your call).

This unifies the two paths on the stricter of the two behaviours and makes
"drops are always wieldable" true by construction rather than by a fallback.
**OK to collapse §4.4's two formulations into this one?**

### Answer — yes, collapse. Keep the guard, retargeted.

The two formulations are a genuine contradiction in the spec and only one of them
keeps D1 green, so there is nothing to trade off. §4.4 is rewritten around
`_equippable_slots_for()`, with both generators calling a shared
`_roll_typed(classes, rarity)` — which also removes the last place the two paths
could drift apart again.

On the fallback: **keep it, but move it and re-aim it.** The
`types_for_slot(...).is_empty()` check does become unreachable, but the
*outer* `_equippable_slots_for(...).is_empty()` case — "no class here can wield
anything at all" — is exactly the case `generate_drop()`'s existing guard at
`itemizer.gd:147` already covers today, with a comment saying why ("a drop is
better than a crash if a future class joins `PARTY_ORDER` before it has a
weapon"). Deleting that guard while collapsing the two functions would quietly
drop a protection the codebase already chose to carry. It now falls back to a
uniform draw over all of `ITEM_TYPES` rather than to WEAPON, since at that point
there is no party-derived answer left to give.

---

## Q5. Confirm the helper names and signatures §4.4 uses as if canonical

§4.4 references `_random_equippable_slot()`, `types_for_slot(slot, party)`,
`_generate_typed()` (exists), and §4.1 references `Item.slot()`. Proposed final
shape, for the spec to adopt verbatim:

| name | file | signature | notes |
|---|---|---|---|
| `Item.slot()` | `item.gd` | `-> Slot` | §4.1 as written; reads `Itemizer.ITEM_TYPES[weapon_type]["slot"]`, default `WEAPON` |
| `Item.Slot` | `item.gd` | `enum { WEAPON, ARMOR, TRINKET }` | §4.1 |
| `Itemizer.types_for_slot(slot, classes)` | `itemizer.gd` | `(Item.Slot, Array[StringName]) -> Array[StringName]` | types in `slot` wieldable by some class in `classes` |
| `Itemizer._equippable_slots_for(classes)` | `itemizer.gd` | `(Array[StringName]) -> Array[Item.Slot]` | Q4; replaces the bare `_random_equippable_slot()` |
| `GameState.equipped_item(hero, slot)` | `game_state.gd` | `(StringName, Item.Slot) -> Item` | §4.3 |
| `GameState.equipped_set(hero)` | `game_state.gd` | `(StringName) -> Array[Item]` | §4.3; items in `Slot` order, gaps omitted |

`weapon_types_for(hero_class)` (drops §2.2) stays as the "all types for a class,
any slot" accessor `types_for_slot` is built on. **Any name you'd rather use?**
`equippable_slot` vs `equip_slot` vs keeping `slot()` — I went with §4.1's
`slot()`.

### Answer — adopted verbatim, plus one addition.

`slot()` is right: it is already what §4.1 writes, and `Item.slot()` reads
correctly at every call site the grep in Q6 found (`item.slot()` beside
`item.rarity` and `item.value`). `equippable_slot()` would be longer for no
disambiguation — an `Item` has only one kind of slot.

One name added to the table: **`_roll_typed(classes, rarity_index) -> Item`**,
the shared slot-then-type body both generators call (Q4). Without it, the
collapse is two near-identical five-line bodies, which is how §4.4's two
formulations diverged in the first place.

`_random_equippable_slot()` is struck from the spec entirely rather than left as
an alias — it never existed in code, and §4.4 now says so explicitly so a reader
of an older draft does not go looking for it.

---

## Q6. Every one-arg `equipped_item()` caller — the grep §4.3 demands

`grep -rn "equipped_item" scripts/` gives four call sites for the old one-arg
form:

| site | fix |
|---|---|
| `compare_flyout.gd:58` | §6.3 gives it verbatim: `GameState.equipped_item(hero_class, item.slot())` |
| `game_state.gd:191` (`equip_item`) | `previous := equipped_item(hero_class, item.slot())` — replace only that slot's occupant (§4.3) |
| `game_state.gd:209` (`_maybe_auto_equip`) | `if equipped_item(hero_class, item.slot()) == null:` — fill that slot only when empty (§4.3) |
| `debug.gd:392` (`state` command) | prints *one* equipped item per hero in the `state` line — **needs a call it can't just retarget** |

The first three are mechanical. `debug.gd:392` is the open one: with three
slots, "the hero's equipped item" is no longer a thing.

### Recommendation — `debug.gd` `state` line iterates `equipped_set(c)`

`equip_bits.append("%s=[%s]" % [c, ", ".join(equipped_set(c).map(...display_name))])`,
so a warrior wearing all three reads `warrior=[Rusty Axe, Fat Helm, Lucky Ring]`
and an empty-handed hero reads `warrior=[]`. Keeps the `state` verb honest
without a new formatting scheme. **Or would you rather it show only the WEAPON
slot** to keep the line short? The `state` line is already long.

### Answer — `equipped_set()`. Not WEAPON-only.

The line is long, but §13.4 puts `forge <weapon|armor|trinket>` in the debug
harness two steps later, and the first thing a forge tester does is run `state` to
see whether the armor slot actually changed. A `state` verb that cannot show the
slot the adjacent verb just forged is a harness that has to be edited again at
step 10 — and with a solo warrior the line is *shorter* than today's three-hero
version regardless, since it prints one hero rather than three.

One adjustment made while folding it in: the `equip_bits` loop (and the `drops`
loop above it at `debug.gd:388`) reads `GameState.active_party` rather than
`Itemizer.droppable_classes()`. The two are equal under a solo warrior, so this
changes no output — but `state` is a report about who is on the field, and
`droppable_classes()` is a loot-targeting concept that only coincidentally
matches. The four call sites in the table were confirmed complete against
`grep -rn "equipped_item" scripts/ tests/ scenes/`. Folded into **§4.3**.

---

## Q7. Do generated armor and trinkets keep `kind = Kind.WEAPON`?

§4.1: *"`Item.Kind` is left alone."* But `_generate_typed()` unconditionally
sets `item.kind = Item.Kind.WEAPON`, and several things depend on that staying
true for a helm:

- `item.gd:usable_by()` early-returns empty unless `kind == Kind.WEAPON` — an
  armor item with `kind = RELIC` would report "Anyone", never auto-equip, and
  never be targeted by `generate_drop()`;
- `type_name()` returns `weapon_type.capitalize()` ("Helm") only on the
  `kind == WEAPON` branch;
- `shop_sell_row.gd:55` / `shop_buy_card.gd:58` pass `i.kind` to the glyph.

### Recommendation — **yes, keep `kind = Kind.WEAPON` for every generated item**

this pass, and record it as a known wart: `kind` and `slot` are orthogonal axes
(§4.1 says so), but until `POTION`/`RELIC` generation exists, `kind` is
effectively "was generated" and `slot()` carries all the real classification.
§15 already defers per-slot behaviour; this is the same seam. I'll add a
sentence to §4.1 so the next reader doesn't "fix" it.

### Answer — yes. `kind = Kind.WEAPON` on every generated item, recorded in §4.1.

The first two dependencies are the load-bearing ones and both were verified:
`item.gd:89` (`if kind != Kind.WEAPON or weapon_type == &"": return out`) and
`item.gd:114` (`type_name()`'s `kind == Kind.WEAPON` branch). A helm marked
`RELIC` would read "Anyone", never auto-equip, never drop, and render as "Rare
Relic" instead of "Rare Helm" — four regressions for a purity that buys nothing
this pass.

One correction to the third bullet, noted for accuracy rather than because it
changes the answer: `shop_sell_row.gd` / `shop_buy_card.gd` do pass `i.kind` to
the glyph, but `item_glyph.gd`'s `_draw()` **never reads it** — it stores `kind`
in an `@export` setter and then branches entirely on `weapon_type`, falling
through to `_draw_gem()`. So §4.1's existing line about "the glyph's kind-based
fallback drawing" describes an intent, not current code. The wart is real; that
particular consequence of it is currently latent.

---

## Q8. `test_profile_expedition.gd` P6 — the scheduled second edit

Line 123, flagged by step-1 Q6 and §13.2 as step 4's job:

```gdscript
# now:
t.check(GameState.active_party == GameState.PARTY_ORDER,
    "active_party still equals PARTY_ORDER (got %s)" % [GameState.active_party])
```

### Recommendation — becomes two checks

```gdscript
t.check(GameState.active_party == ([&"warrior"] as Array[StringName]),
    "active_party is the solo warrior (got %s)" % [GameState.active_party])
t.check(GameState.PARTY_ORDER.size() == 3,
    "PARTY_ORDER is untouched — the 3-hero roster still exists (§4.5)")
```

The second line pins §4.5's "`PARTY_ORDER` stays exactly as it is" — the flip is
`active_party`'s value, *not* a deletion — so a future edit that trims
`PARTY_ORDER` to match trips a test. This assertion runs after `reset_run()` at
P5, i.e. post-`new_profile()`, so `[&"warrior"]` is the expected value.
**Wording OK?**

### Answer — wording accepted as written.

The `PARTY_ORDER.size() == 3` line is the more valuable of the two and the reason
to take both rather than just editing the existing check's expected value. §0.2
("`PARTY_ORDER` is *not* deleted"), §4.5 and §15 all state the roster survives,
and §15 additionally says the drop-coverage machinery written against it must not
be deleted — three prose statements with no test behind them until now. Q11 leans
on the same guarantee from the other side.

The `as Array[StringName]` cast is required, not stylistic: an untyped `[&"x"]`
literal will not compare equal to a typed `Array[StringName]` under `==` in
GDScript. Folded into **§13.2**'s `test_profile_expedition.gd` bullet, which
already documented that this file is edited twice on purpose.

---

## Q9. `test_profile_save.gd` — promote its stand-in items to real slots now?

§13.1: *"Its three equipped items are 'of different slots' only from step 4 on;
at step 2 distinct `weapon_type` / `rarity` / `equipped_by` stand in."*

Today it builds four weapons (MAGIC/RARE/UNCOMMON/COMMON, distinct types, one
forged twice). Step 4 is when `Item.Slot` exists.

### Recommendation — **yes, update it**, low cost, no new assertion needed

Swap the three equipped items to one WEAPON, one ARMOR, one TRINKET
(`generate_item_with_rarity` will pick a type per slot once slot-first
generation lands, or force types explicitly). `slot()` is **derived from
`weapon_type`**, not serialized, so the existing "every `@export`ed field
round-trips" coverage already proves `slot()` survives — no `assert item.slot()
== ...` line required. This just makes the fixture honest about what a real
profile looks like. **Add it to §13.2's edited-tests list?** It isn't there now.

### Answer — yes, update it, and yes, add it to §13.2.

It belongs on the list for the reason §13.2 itself gives about
`test_profile_expedition.gd`: "an edit here should always be traceable to a named
section." An untracked edit to the save fixture is the one edit in this step that
could silently weaken the test guarding player data.

Two specifics settled while folding it in:

- **All three go on the warrior**, not one per hero. §13.1 asks for "three
  equipped items of different slots", and one hero wearing three slots is both
  what a real solo-warrior profile looks like and what makes the fixture exercise
  `equipped_item(hero, slot)`'s actual discriminator. Three items on three
  different heroes would leave the fixture passing while saying nothing about
  slots.
- **No coverage is lost by dropping the mage/ranger `equipped_by` values.** The
  interesting `equipped_by` boundary is `&"warrior"` vs `&""` (the loose item),
  which the fixture keeps; `&"mage"` vs `&"ranger"` are two more non-empty
  StringNames and prove nothing further about serialization. `active_party`'s own
  round-trip check at `test_profile_save.gd:91` already covers StringName arrays.

The fixture assigns `weapon_type` directly after generation (lines 51, 55, 58),
so this is a three-literal change — `&"axe"` / `&"helm"` / `&"ring"` — and does
not depend on slot-first generation having landed first.

---

## Q10. Known consequences to record (not questions — confirm they're accepted)

Folding these into a "What step 4 ships / accepts" section the way steps 1–3
did:

1. **One modifier pool for all three slots.** A helm can roll `+7 Bolt Power`; a
   ring can roll `+5 Fire Damage`. §15 explicitly defers per-slot pools. Accepted.
2. **New types render as the generic gem glyph** until §12 (step 11).
   `item_glyph.gd`'s `WEAPON_TEXTURES` has no `helm`/`mail`/`shield`/`ring`/
   `amulet`/`idol` entry, so `_draw()` falls through to `_draw_gem()`. Step 4 is
   invisible-by-design (§14: "Steps 1–4 are all invisible to the player"), so no
   glyph work here. Accepted.
3. **`Item.type_initial()` letter collisions.** sword/shield → `S`,
   axe/amulet → `A`, helm → `H` vs nothing, etc. It's "spec 17.2 inventory
   chip" and the inventory chip is superseded by the inventory modal at step 6.
   Recommend leaving `type_initial()` untouched this step; flag it for step 6.
4. **`test_drops.gd` D1/D3/D5/D6 keep looping `PARTY_ORDER`, not
   `active_party`.** They call `generate_drop()` with an explicit class, which
   still works per-class for mage/ranger (Q4), so they stay green unedited.
   Only D2 (line 23) and D7 change. Accepted — or do you want D1/D3/D5/D6
   re-pointed at `active_party` for consistency? They'd then only exercise the
   warrior.

### Answer — 1, 2 and 3 accepted. **4 is wrong**; see Q11.

**1 (one modifier pool)** — accepted. §15 already carries it as a named deferral
with a stated reason ("per-slot pools are the obvious next step and want their
own balance pass"). No spec change needed; §14 step 4 now repeats it in the
step's own "what it accepts" note so it is visible without a jump to §15.

**2 (generic gem glyph)** — accepted, and verified: `item_glyph.gd`'s `_draw()`
matches on `weapon_type` with a `_:` arm calling `_draw_gem()`, so the six new
types get the gem with no crash and no missing-texture error. Recorded in §14
step 4 rather than left implicit, because "the new gear all looks the same" is
exactly the kind of thing that reads as a bug in a demo two steps later.

**3 (`type_initial()` collisions)** — accepted, *and* promoted to §15. Leaving it
untouched is right — the inventory chip it feeds is superseded at step 6, and
`staff`'s existing hand-written `T` exception shows where a second exception
table leads — but "flag it for step 6" only survives if it is written somewhere
the step-6 implementer will look. A comment in a step-4 questions document is not
that place, so it is now a §15 bullet ending "revisit at step 6, or delete it
with the chip."

**4** — the D1/D3/D5/D6 half is correct and was verified. The
"only D2 and D7 change" half is **not**: D4 and D9 break too, through a
dependency that is invisible to a `grep` for `active_party`. Q11 covers it.

**No, do not re-point D1/D3/D5/D6 at `active_party`.** Consistency is the wrong
goal here: those four are the *only* remaining coverage of `generate_drop()`
against a class that is not the warrior, and §15 commits to bringing the mage and
ranger back through exactly that seam. Re-pointing them would delete the test for
the return path in the name of tidiness.

---

## Q11. `next_drop_class()` reads `droppable_classes()` — D4 and D9 break too

**Not in the original list; found while verifying Q10.4.** Q10.4 claims "only D2
(line 23) and D7 change" in `test_drops.gd`. Two more blocks break, and neither
mentions `active_party` anywhere in its body:

```
Itemizer.droppable_classes()      # -> active_party after §4.5
  └─ GameState.next_drop_class()   # game_state.gd:288
       ├─ test_drops.gd D4 (line 46)
       └─ test_drops.gd D9 (line 117)
```

- **D4** (lines 42–52) draws 3000 classes from `next_drop_class()` and asserts
  each of `PARTY_ORDER`'s three takes **33.3% ± 2pp**. With one droppable class
  the warrior takes 100% and the other two take 0% — **three failing checks**.
- **D9** (lines 101–138) counts ≥ 3-drop levels whose drops covered *all three*
  `PARTY_ORDER` classes, and requires ≥ 95%. Mage and ranger can never be
  returned by `next_drop_class()`, so `d9_rate` is **0%** — **one failing check**.

Four failing checks, in the step whose acceptance bar (§14) is a green suite.

### Answer — save, override, restore. Do not re-point at `active_party`.

The obvious fix — loop `active_party` instead of `PARTY_ORDER` — makes both
blocks pass and makes both **tautological**. "The single droppable class received
100% of the drops" is true by arithmetic regardless of what `next_drop_class()`
does, and "the single class got at least one of ≥ 3 drops" is true by the
pigeonhole principle. D4 and D9 exist to test `DROP_CATCHUP`'s catch-up
weighting, and §15 explicitly commits to keeping that machinery alive for the
party's return: *"Drop coverage (`DROP_CATCHUP`, `next_drop_class`) is untouched
and waiting for them — do not delete it."* A tautological test is how untouched
code rots without anyone noticing.

So each block saves `GameState.active_party`, sets it to
`PARTY_ORDER.duplicate()` for its own duration, and restores it — keeping the
coverage algorithm under a real three-class test while the field it reads is
solo, and inverting the failure mode: if a future edit breaks the weighting, D4
fails *now* rather than on the day the mage comes back.

This is the file's existing idiom, not a new one: D8 saves and restores
`endless_level_number` (line 92), and `_report_party_bonuses()` saves and
restores `inventory`, `drops_by_class` and `endless_level_number` (lines
181–216). Their `PARTY_ORDER` loops become `Itemizer.droppable_classes()` loops
so they follow the override rather than restating the roster — which also means
they need no further edit the day the party actually grows.

Folded into **§4.5** (the reasoning, beside the value flip that causes it) and
**§13.2** (the edit list).

---

## Step-4 changeset (final — answers above are folded into the spec)

- **`scripts/data/item.gd`** — `Slot` enum + `slot()`; `usable_by()` reads
  `ITEM_TYPES`; comment on `weapon_type` and on `kind` staying `WEAPON` (Q1, Q7).
- **`scripts/autoload/itemizer.gd`** — `WEAPON_TYPES` → `ITEM_TYPES` with `slot`
  on every entry + six new armor/trinket types (§4.2 table); `types_for_slot()`,
  `_equippable_slots_for()`; slot-first `generate_item_with_rarity()` and
  `generate_drop()` (Q4); `weapon_types_for()`/`droppable_classes()` read
  `active_party` (§4.5).
- **`scripts/autoload/game_state.gd`** — `equipped_item(hero, slot)`,
  `equipped_set(hero)`; `equip_item()` / `_maybe_auto_equip()` slot lookups;
  `active_party` initialiser **and `new_profile()`** → `[&"warrior"]` (§4.5, the
  value flip — the edit that actually does the work).
- **`scripts/modals/compare_flyout.gd`** — the §6.3 one-liner.
- **`scripts/autoload/debug.gd`** — `state` line via `equipped_set()` (Q6).
- **`tests/test_drops.gd`** — D2 (line 23) → `active_party`; D7 re-derived (Q2)
  and its loop → `ITEM_TYPES` (Q1); D4 and D9 wrapped in a save / override /
  restore of `active_party`, loops → `droppable_classes()` (Q11).
- **`tests/test_item_distribution.gd`** — four-to-five array widening (Q3).
- **`tests/test_profile_expedition.gd`** — P6 → solo-warrior + PARTY_ORDER-intact
  (Q8).
- **`tests/test_profile_save.gd`** — fixture uses one item per slot (Q9).
- **spec** — §0.3, §4.1, §4.2, §4.3, §4.4, §4.5, §13.1, §13.2, §14 step 4 and §15
  amended per the answers. **Done** — the spec is the source of truth from here;
  this document is the record of why.

Green bar: §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_endless_level_gen`,
`test_retarget`, `test_parallax_seam`, `test_damage_chunk`) plus
`test_enhanced_rarity`, `test_profile_save`, `test_profile_expedition`,
`test_drops`, `test_item_distribution` all passing.

---

## Implementation notes (things that surfaced while writing the code)

Nothing here reopened a design question — the answers above held. These are the
places a literal reading of the spec/answers needed a small, local decision.

1. **`Array[Item.Slot]` typed arrays compile.** §4.4's helper table gives
   `_equippable_slots_for() -> Array[Item.Slot]` and the pseudocode iterates
   `for s: Item.Slot in [...]`. Godot 4.7 accepts both — a typed array of a
   script enum, and a typed loop var over an untyped array literal — so
   `_equippable_slots_for()` / `equipped_set()` are written exactly as specified
   rather than falling back to `Array[int]`.

2. **D7's "within-slot uniformity ± 3pp" (Q2) is implemented as an overall
   per-type share, not a literal within-slot share.** A within-slot check —
   "among the ~2000 WEAPON samples, axe is 50% ± 3pp" — is only ~2.7σ over 6000
   total samples and would flake. The equivalent statement as a fraction of the
   whole run, `(33.3% / n_types_in_slot) ± 3pp` (16.7% for axe/sword, 11.1% for
   the armor/trinket types), is 6–7σ — which is the sizing Q2's own note
   describes ("the tightest band is the 11.1% within-slot share, σ ≈ 0.41pp").
   A separate explicit slot-share check (each slot 33.3% ± 3pp) carries the
   "no slot starved or flooded" half. Same three assertions Q2 asked for, framed
   so they can't flake.

3. **D7's zero-count guard is generic, not a `[bow, dagger, staff]` literal.**
   The loop is `if no active-party class can wield this type: assert count == 0`,
   which prints one PASS line per unwieldable type today and needs only the
   active party changed — not the assertion — the day the mage returns. This is
   the "survives the mage's return in meaning" property Q2's answer called for.

4. **`test_item_distribution.gd`'s mod-count message still reads `(0/1/2/3)`.**
   §13.2 says line 68 "does not change", so the now-slightly-stale label
   (`RARITY_MOD_COUNT` is `0/1/2/3/4`) was left verbatim rather than widened.

5. **`debug.gd`'s `drops` loop moved to `active_party` too**, alongside the
   `equip_bits` loop — Q6's answer folded that into §4.3, and both loops now read
   `GameState.active_party` rather than `Itemizer.droppable_classes()`.

6. **Three "one item per hero" comments were stale and are corrected** — found
   on the verification pass, not the first one. The changeset lists the call
   sites that *compile*; these are prose stating the rule §4.3 replaced, which no
   test can catch:
   - `game_state.gd`'s `party_bonuses()` header said "one per hero" directly
     above the loop whose whole purpose, per §1.5, is that a hero now feeds
     **three** items into that pool. The most misleading of the three.
   - `item.gd`'s `equipped_by` field said "one item per hero"; it now also
     records *why* the field deliberately does not store the slot (recoverable
     via `slot()`), which is the reasoning §4.3 gives for needing no new field.
   - `test_item_distribution.gd`'s element-tie probe justified using two heroes
     with "fire and ice can never tie on the SAME hero, since only one item can
     be equipped there" — false under three slots. **The code is unchanged**
     (§13.2 gives this file one step-4 edit); only the justification is
     rewritten, since the two-hero form still exercises the same tiebreak.

   Comment-only, no logic touched, suite re-run green after.

**Verified at runtime, not just headless.** §14's bar is "leave the game
runnable", and step 4 is the first time the game actually spawns a solo party.
`main.tscn` boots, renders one warrior with one HP bar (no spare/broken bars from
`party_bars.gd`), and `debug.gd`'s `state` prints the new bracketed form —
`equipped warrior=[Weeping Chopper, Grumbling Talisman]`, a weapon and a trinket
with the armor slot empty. A throwaway probe scene confirmed the shape §4.4
predicts: slot split 1928/2074/1998 of 6000; axe/sword ≈16.6%, the six
armor/trinket types ≈11%; **bow, dagger and staff exactly 0** (§1.6);
`_equippable_slots_for()` returning all three slots for the party but `[WEAPON]`
alone for the mage and for the ranger (Q4's whole point); `generate_drop()` 0
unwieldable over 500×3; and equipping a `mail` displacing only the `helm` while
the axe and ring stayed put (§4.3's per-slot replacement). Probe deleted after.

Full suite: 13 test scenes, 287 checks, **0 failures**. `test_drops` goes 19 → 28
checks (re-derived D7: the old 5 per-type bands become 3 slot-share + 11 per-type
assertions); `test_profile_expedition`'s P6 goes from one check to two.
