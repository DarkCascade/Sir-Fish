# Town Spec — Step 6 Implementation Questions

Raised while preparing §14 step 6 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("**§6 — the inventory modal** and `inventory_row.tscn`.
Unblocked by step 5's `Hud/ModalLayer` and `SceneRouter`; three hazards are
already visible from there.").

Step 6 is the **second player-visible step** and the first that puts a real
screen behind the HUD chrome step 5 shipped inert. Unlike steps 4 and 5, §14
gives step 6 **no itemised changeset** — just the prose above and the three
named hazards. Most of the questions below fill that in: names §6 uses without
pinning down, a fork §14 explicitly hands to this step ("one shared node or
two"), and two places where §6 / §3.3 point at each other without either
spelling out the wiring.

**Nothing here is a design fork** — §0.4 settled the slot model, and §6 settled
"no sell action, Compare + Equip side by side, rebuild both sections on any
equip change". These are implementation gaps.

**Answers pending.** Each carries a recommendation. The step was built against
these; the "as built" section at the end records what shipped.

| Q | gap | recommendation | spec |
|---|---|---|---|
| Q1 | §14 step 6 has no changeset | derive it from §6 + the three §14 hazards; recorded below | §14 step 6 |
| Q2 | `CompareFlyout`: one shared node or two? | **two** — the inventory modal carries its own, exactly as the shop does | §3.2, §6.3, §14 step 6 |
| Q3 | `item_card_style.gd` — where, and how much to lift | `scripts/ui/`, next to `currency_feedback.gd`; lift only the block both `setup()`s share verbatim | §6.2 |
| Q4 | does `equip_item()` emit `EventBus.item_equipped`? | yes — from the deliberate-equip path only; auto-equip stays silent | §3.3 |
| Q5 | `InventoryButton` `pressed` wiring | `hud.gd._ready()` connects it to `inventory_modal.open`; `_process()` drops the `or true` — nothing else changes | §3.2, §14 step 6 |
| Q6 | `type_initial()` — "revisit at step 6, or delete it" | delete it: zero callers remain, the chip that used it is already gone | §15 |
| Q7 | does step 6 ship a pinning test? | no new file — a headless smoke during the step, then the full suite stays green | §13, step-1 Q5 |
| Q8 | `get_tree().paused` in town, where nothing is running | keep it (harmless in town, needed in the forest); drop the world-rendering toggle | §3.2 |
| Q9 | §6.1 "BonusStrip … exactly as shop_modal.tscn authors it" is stale | instance `bonus_strip.tscn` under the header anyway — §6.1's intent is clear; `shop_modal.tscn` just dropped its copy | §6.1 |

---

## Q1. §14 step 6 ships no changeset

Steps 4 and 5 each carry a bulleted, file-by-file changeset in §14. Step 6 has
only the one-paragraph description and three hazards. That is probably
deliberate — §6 is short and self-contained — but it leaves "what files does
this touch" unstated.

### Recommendation — derive it, record it here

The step's surface, from §6 plus the three §14 hazards:

- **new** `scripts/ui/item_card_style.gd` — the shared card-frame helper (Q3).
- **new** `scenes/modals/inventory_row.tscn` + `scripts/modals/inventory_row.gd`
  — the row (§6.2).
- **new** `scenes/modals/inventory_modal.tscn` + `scripts/modals/inventory_modal.gd`
  — the modal (§6.1), with its own `CompareFlyout` child (Q2) and a
  `BonusStrip` under the header (Q9).
- `scripts/modals/shop_sell_row.gd`, `scripts/modals/shop_buy_card.gd` —
  `setup()`'s styling block replaced by `ItemCardStyle.apply()` (§6.2), behaviour
  preserved.
- `scripts/hud/hud.gd` — a `_ready()` that connects `inventory_button.pressed`
  to `inventory_modal.open`; `_process()` drops the `or true` (Q5).
- `scenes/hud/hud.tscn` — instance `InventoryModal` under `ModalLayer`.
- `scripts/autoload/game_state.gd` — `equip_item()` emits
  `EventBus.item_equipped` (Q4).
- `scripts/data/item.gd` — delete `type_initial()` (Q6).

No test file (Q7). No spec section other than §6 changes shape.

---

## Q2. `CompareFlyout` — one shared node in `Hud/ModalLayer`, or one per modal?

§14 step 6 states the fork outright:

> **`CompareFlyout` moving into `Hud/ModalLayer`** (§3.2's end-state list)
> collides with the shop's own `compare_flyout` instance — step 6 has to decide
> whether that is one shared node or two, and §6.3's slot fix … lands on
> whichever it is.

§3.2's end-state list reads "`ModalLayer` … hosting `InventoryModal`,
`CompareFlyout` and `QuestResult`", which suggests one shared flyout. But:

- `shop_modal.tscn` instances its **own** `CompareFlyout` as its last child, and
  `shop_modal` lives in `main.tscn`'s `ModalLayer` (`Place.QUEST` only), not in
  `Hud/ModalLayer`. Sharing would mean re-parenting the shop's flyout to `Hud`
  and giving `shop_modal` a cross-scene reference to reach it.
- `compare_flyout.gd`'s Escape handling depends on being **the last child of the
  modal that opened it** ("this node is added as ShopModal's last child, so
  unhandled input reaches it first") — a single flyout under `Hud/ModalLayer`
  can't be the last child of two different modals.
- The shop and the inventory modal never coexist — you are in one or the other.

### Recommendation — two instances

The inventory modal carries its own `CompareFlyout` as its last child, exactly
as the shop does. §6.3's slot fix (`equipped_item(hero, item.slot())`) lives in
`compare_flyout.gd` **itself** — a shared script, already fixed at step 4 — so
both instances inherit it with no per-instance work.

This is the same call step 5 made for `RunController.run_summary` ("renaming the
field as well is pure diff noise on a step whose point is that nothing
player-visible changed"): unifying two identical-behaviour nodes across a scene
boundary is churn with no player-visible gain. §3.2's end-state list should read
"`InventoryModal` (with its own `CompareFlyout`) and `QuestResult`".

---

## Q3. `item_card_style.gd` — location and exact scope

§6.2: "Lift that `setup()` styling block into a shared `item_card_style.gd`
static helper rather than copy-pasting it a third time — `shop_buy_card.gd`
already carries a second copy." Unspecified: which directory, and where the
shared block ends.

### Recommendation — `scripts/ui/`, lift only the verbatim-shared lines

`scripts/ui/item_card_style.gd`, next to step 5's `currency_feedback.gd` — the
"shared UI helper" bucket, not "modal" (one of its three callers is a shop card,
one an inventory row; none is uniquely a modal).

The block that is **byte-identical** in both `shop_buy_card.setup()` and
`shop_sell_row.setup()` is exactly:

```gdscript
var face_style: StyleBoxFlat = (face.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
face_style.border_color = rarity_color
face_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.45)
face_style.shadow_size = 8
face.add_theme_stylebox_override("panel", face_style)
glyph.set("ring_color", rarity_color)
glyph.set("weapon_type", i.weapon_type)
glyph.set("kind", i.kind)
```

→ `ItemCardStyle.apply(face, glyph, item)`. The `name_label` / `subtitle_label`
lines are **not** lifted — the buy card builds a modifier `VBox` and the sell row
a "N modifiers" `Label`, so only the caller knows what to do there. The one-line
`subtitle_label.add_theme_color_override("font_color", i.rarity_color())` stays
per-caller too (both do it, but it is trivial and reads better inline than as a
fourth helper argument).

---

## Q4. Does `equip_item()` emit `EventBus.item_equipped`?

§3.3 declares `signal item_equipped(item, hero_class, slot)` and attributes it to
"step 6", but §6 never references it — §6.2's row bubbles a **local**
`equip_changed()` signal, which the modal connects to its own `_rebuild()`. So
`item_equipped` has a home (step 6) but, read literally, no emitter.

### Recommendation — emit it from the deliberate-equip path

`GameState.equip_item()` emits `EventBus.item_equipped.emit(item, hero_class,
int(item.slot()))` after assigning `equipped_by`, alongside the existing
`party_bonuses_changed`. `_maybe_auto_equip()` stays **silent** — it only fills a
slot the player left empty, `add_item()` already fires `party_bonuses_changed`
for it, and "the player equipped something" is a different event from "a pickup
slotted itself".

This honours §3.3's step-6 attribution and hands step 9's forge (and any future
equip SFX / tutorial hook) a signal to bind, for one line. `unequip_item()` gets
nothing: there is no `item_unequipped` signal and §3.3 does not add one — the
row's local `equip_changed` covers the modal's own rebuild need.

---

## Q5. `InventoryButton` `pressed` — the one line step 5 left out

§3.2 / step-5 Q9: "step 6 adds `Hud.inventory_modal.open()` and deletes the `or
true` from `hud.gd`, and nothing else about the button changes." Step-5 I6
confirms `_combat_locked()` is already evaluated every frame.

### Recommendation — a `_ready()` in `hud.gd`, one token out of `_process()`

`hud.gd` gains:

```gdscript
@onready var inventory_modal = $ModalLayer/InventoryModal

func _ready() -> void:
	inventory_button.pressed.connect(inventory_modal.open)
```

and `_process()`'s line becomes `inventory_button.disabled = _combat_locked()`
(the `or true` gone). `InventoryModal` is instanced in `hud.tscn` under
`ModalLayer` (`process_mode = ALWAYS`, so it animates while the tree is paused).
No change to the button's icon (still §12 / step 11), position, or the COMBAT
predicate.

---

## Q6. `type_initial()` — §15 says "revisit at step 6, or delete it with the chip"

§15 (deferred): "`Item.type_initial()`'s letter collisions … feeds only the spec
17.2 inventory chip, which §6's inventory modal supersedes at step 6 … Revisit
at step 6, or delete it with the chip."

`grep -rn "type_initial" scripts/ scenes/ tests/` → **one hit, the definition**.
The chip scene it fed was removed in an earlier pass; nothing calls it.

### Recommendation — delete the function

Six dead lines, zero callers, and §15 explicitly sanctions it. There is no
collision table to invent and nothing to migrate — the modal names types in full
("Magic Sword — Warrior" via `subtitle()`), so the single-letter form has no
consumer to replace. §15's `type_initial()` bullet can be struck.

---

## Q7. Does step 6 ship a pinning test?

Steps 1–5 each added one, on step-1 Q5's principle. §13 lists no inventory-modal
test.

But step 6 is **UI wiring over already-tested primitives**: `equip_item()`,
`equipped_item(hero, slot)` and `equipped_set()` are covered by
`test_profile_expedition.gd`, `test_drops.gd` and `test_profile_save.gd`. What
step 6 adds on top is scene instantiation, signal forwarding
(`compare_requested` → flyout, `equip_changed` → rebuild) and rebuild-on-signal —
none of which reduces to a cheap headless invariant, and all of which need a
full scene driven to assert anything.

### Recommendation — no new test file; a throwaway smoke during the step

Run (and then delete) a scratch scene that: instantiates the `Hud` autoload,
`new_profile()` + `add_item()` a mixed set, `Hud.inventory_modal.open()`, asserts
the Equipped section has three rows (item or placeholder) and Carried has the
rest, calls a carried row's `_on_equip_pressed()`, asserts **both** sections
rebuilt and the slot was displaced, then `close()` and asserts `not visible` and
`not get_tree().paused`. Plus the whole §13.3 no-edit list and the four
earlier-edited tests staying green.

This is the same call step 5 made for the parts of its own acceptance that were
runtime rather than headless-invariant ("a `--headless --quit-after` boot … is
what actually covers this file"). Flag for confirmation if step 6 is expected to
leave a permanent test behind.

---

## Q8. `get_tree().paused` when the modal opens in town

`shop_modal.open()` sets `get_tree().paused = true` and
`owner.set_world_rendering(false)`. The inventory modal is reachable in town,
where there is no `RunController`, no `BattleWorld`, and nothing to pause.

### Recommendation — keep the pause, drop the world-rendering toggle

`paused = true` is harmless in town (town scenes are scriptless `Control`s) and
**necessary** in the forest — opening the modal during travel/loot must freeze
the fight, exactly as the shop does (an unpaused inventory screen mid-expedition
is a free "stop and think" and a heal-timing tool; §3.2 makes the same argument
for the COMBAT disable). `close()` unpauses on every exit path, first, per
`shop_modal`'s own rule.

The `_set_world_rendering()` call is dropped: it depends on `owner` being
`MainLayout`, which the modal — a child of `Hud/ModalLayer`, not `main.tscn` —
never is. The scrim already covers the frozen world.

---

## Q9. §6.1's "BonusStrip … exactly as `shop_modal.tscn` authors it" is stale

§6.1: "`BonusStrip` is instanced under the header, exactly as `shop_modal.tscn`
authors it." But `shop_modal.tscn` **no longer instances a `BonusStrip`** — its
own header: "Bonus strip removed after the other bonus strip was moved to the
upper-right corner."

### Recommendation — instance it anyway; §6.1's intent is unambiguous

§6.1's reasoning still holds ("seeing what the party actually gains is what makes
equipping a decision rather than a chore"), and there is no persistent
`BonusPanel` in town — `main.tscn`'s lives only in `Place.QUEST`. So the
inventory modal instances `scenes/console/bonus_strip.tscn` under its header,
`vertical = false`, `size_flags_horizontal = 3`. It is self-wiring —
`bonus_strip.gd._ready()` binds `party_bonuses_changed` / `run_started` and
paints from `GameState.party_bonuses()` — so the modal adds no code for it. §6.1
should be reworded to "as `shop_modal.tscn` **used to** author it" or just "under
the header".

---

## What step 6 ships (as built)

- **`scripts/ui/item_card_style.gd`** — new. Static `apply(face, glyph, item)`,
  the rarity-tint + glyph block lifted verbatim from `shop_buy_card.setup()` /
  `shop_sell_row.setup()` (Q3). Both shop scripts refactored onto it,
  behaviour-preserving.
- **`scenes/modals/inventory_row.tscn` + `scripts/modals/inventory_row.gd`** —
  new (§6.2). Reuses `swipeable_face` (the Stage/ActionLayer/Face structure it
  requires), `item_glyph`, `shop_buy_stage`, and the rarity frame via
  `ItemCardStyle`. Action area is two equal-width buttons — Compare and
  Equip/Unequip — plus the swipe-revealed Compare lane. Emits
  `compare_requested(item)` and a local `equip_changed()`. The Equip button is
  hidden when no `active_party` member can wield the item (Q via §6.2).
- **`scenes/modals/inventory_modal.tscn` + `scripts/modals/inventory_modal.gd`**
  — new (§6.1). `Scrim` + `Panel` (Header: title, gold+scrap readout, red X;
  then `BonusStrip`, Q9; then a scrolled Body: **Equipped** — one row or an
  empty-slot placeholder per `Item.Slot` in enum order; **Carried** — every
  unequipped item) + its own **`CompareFlyout`** last child (Q2). `open()`
  pauses the tree (Q8); `close()` unpauses first on every path. Both sections
  rebuild on any row's `equip_changed`. No sell action (§6.4).
- **`scripts/modals/shop_sell_row.gd`, `scripts/modals/shop_buy_card.gd`** —
  `setup()`'s styling block → `ItemCardStyle.apply()` (§6.2). No behaviour
  change; `test_economy.gd` and the shop are untouched otherwise.
- **`scripts/hud/hud.gd`** — new `_ready()` connecting
  `inventory_button.pressed` → `inventory_modal.open`; `_process()` drops the
  `or true` (Q5). New `inventory_modal` accessor.
- **`scenes/hud/hud.tscn`** — `InventoryModal` instanced under `ModalLayer`,
  before `QuestResult`, `visible = false`.
- **`scripts/autoload/game_state.gd`** — `equip_item()` emits
  `EventBus.item_equipped(item, hero_class, int(item.slot()))` (Q4);
  `_maybe_auto_equip()` stays silent.
- **`scripts/data/item.gd`** — `type_initial()` deleted (Q6).
- **spec** — §3.2 end-state list "InventoryModal (with its own CompareFlyout)"
  (Q2); §6.1 BonusStrip wording (Q9); §15 `type_initial()` bullet struck (Q6);
  §14 step 6 marked **Done** with the changeset above.

**Green bar:** §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_endless_level_gen`,
`test_retarget`, `test_parallax_seam`, `test_damage_chunk`) plus
`test_enhanced_rarity`, `test_profile_save`, `test_profile_expedition`,
`test_drops`, `test_item_distribution`, `test_scene_router` — all passing. A
headless smoke populated a profile, opened the modal (3 Equipped rows / 2
Carried), equipped a spare weapon, and confirmed both sections rebuilt with the
weapon slot displaced, then closed clean and unpaused.

---

## Implementation notes — issues found while building step 6

### N1. `ItemCardStyle.apply()` reads `item.rarity_color()` itself

Both `setup()`s computed `var rarity_color := i.rarity_color()` once and used it
three times. Folding the block into the helper means the local is gone from the
callers; the one place they still needed it (the subtitle colour override) now
calls `i.rarity_color()` directly. One extra call per row, no behaviour change.

### N2. Editor `play_scene` still can't see `SceneRouter` / `Hud` — step-5 I8 recurs

A `play_scene` of a scratch scene that names `Hud` fails to compile in the
**running editor** (`Compile Error: Identifier not found: Hud`), exactly as
step-5 I8 documented for `SceneRouter`. Every `--headless` run is a fresh process
and is unaffected — the functional smoke (row counts, rebuild, unpause) ran
headless and passed. A visual screenshot needs the editor restarted once; not a
code issue.

### N3. `inventory_row.setup()` must run *after* `add_child()`

The row's `@onready` vars (`face`, `glyph`, the labels, the two buttons) resolve
on `_ready()`, i.e. when the row enters the tree. So the modal adds the row to
its section first, *then* calls `row.setup(i)` — the same order `shop_modal`
uses for its cards. Calling `setup()` on a detached instance null-derefs.

### N4. Equipping a carried row rebuilds the list that row lives in

`equip_changed` → `_rebuild()` → `queue_free()` on every row including the one
whose button was just pressed. This is fine — `queue_free` is deferred to
frame-end, the signal callback returns first — and it is the same pattern
`shop_modal._on_equip_changed()` → `_build_sell()` already relies on. Confirmed
in the smoke: after equipping the spare Blade, Equipped stayed at 3 rows
(Blade / Helm / Loop) and Carried at 2 (the displaced Axe now among them).
