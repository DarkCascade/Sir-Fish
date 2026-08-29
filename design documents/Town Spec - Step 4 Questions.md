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

**None are answered yet.** Each carries a recommended resolution; every one
needs a yes/no before it goes in, and the answers get folded back into the spec
the way steps 1–3 were.

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

---

## Proposed step-4 changeset (pending the answers above)

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
- **`tests/test_drops.gd`** — line 23 → `active_party`; D7 re-derived (Q2); D7
  loop → `ITEM_TYPES` (Q1).
- **`tests/test_item_distribution.gd`** — four-to-five array widening (Q3).
- **`tests/test_profile_expedition.gd`** — P6 → solo-warrior + PARTY_ORDER-intact
  (Q8).
- **`tests/test_profile_save.gd`** — fixture uses one item per slot (Q9).
- **spec** — §4.1, §4.2, §4.4, §13.2 amended per the answers.

Green bar: §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_endless_level_gen`,
`test_retarget`, `test_parallax_seam`, `test_damage_chunk`) plus
`test_enhanced_rarity`, `test_profile_save`, `test_profile_expedition`,
`test_drops`, `test_item_distribution` all passing.
