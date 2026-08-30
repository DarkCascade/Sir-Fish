# Sir Fish — Town Initiative Acceptance Testing Spec

Companion to *Sir Fish — Town, Quests & Forging Implementation Spec* (referred
to throughout as **the spec**; all bare `§` references are to it) and to the
eight `Town Spec - Step N Questions.md` documents.

The spec's §14 build order runs to eleven steps and all eleven are in the tree.
This document is the **acceptance pass over the finished initiative**: what the
spec promised, what the code actually does, and the gap between them. It exists
because steps 10 and 11 shipped without the questions-and-answers pass every
other step got, and two of the defects below are exactly the kind that pass has
caught every previous time (step-2 Q10 and step-4 Q11 were both found by writing
the document, not by writing the code).

---

## 0. How to use this

### 0.1 Scope

This document does **not** re-open anything. §0.4's four resolved forks stand,
§0.2's exclusions stand, and §15's deferrals stay deferred. Every finding here
is either a place the code contradicts the spec, a place the spec promised
something that was never built, or a place a decision was made in code that no
document records. Where a finding needs the author's ruling rather than an
implementer's fix it is filed in the **E-series** and says so.

**Nothing here is release-blocking.** The suite is green, the game boots clean,
and the loop closes. A1 and A2 are real bugs a player can hit; everything else
is smaller.

### 0.2 Severity classes

| class | meaning | implementer's obligation |
|---|---|---|
| **A** | a rule the spec states outright is violated in play | fix, and pin with a test |
| **B** | the spec asked for something that was never built | build it |
| **C** | test coverage the pass's own conventions require | add it |
| **D** | hygiene, dead code, stale comments, latent cost | fix opportunistically |
| **E** | a decision nothing records — needs a ruling, not a patch | **ask; do not guess** |
| **F** | the spec document is behind the code | amend the spec |

### 0.3 Findings index

| ID | finding | authority | confirmed by |
|---|---|---|---|
| **A1** | Buying out the blacksmith's stock is a free refresh | §7.4 | runtime probe |
| **A2** | `forge()` never emits `party_bonuses_changed` | §3.3, §1.5 | runtime probe |
| **B1** | `CurrencyPlate` has no `OrnateFrame` treatment | §5.3 | scene read |
| **B2** | `Tuning.FORGE_SHOP_SLOTS` is documented-only, never read | §0.1.5, §11 | grep |
| **C1** | No permanent test for step 10 | §13.1 convention, step-1 Q5 | absence |
| **C2** | `tests/_scratch_shop_touch.gd` left in the suite directory | — | file read |
| **D1** | `hud.gd` runs a recursive whole-tree search every frame | — | code read |
| **D2** | `scene_router.go()`'s `place` comment contradicts its code | step-5 I8 | code read |
| **D3** | `item_glyph.gd`'s procedural fallbacks are now unreachable | §12.1 | code read |
| **D4** | `forge_row.gd` duplicates `Item.rarity_name()`'s array | §0.1.5 | code read |
| **D5** | `currency_plate.gd`'s header is stale ("dead until step 9") | — | code read |
| **E1** | The HUD's `CurrencyPlate` collides with `BonusPanel` | §3.2, §0.2 | uncommitted diff |
| **E2** | A quest cannot be abandoned | unrecorded | code read |
| **E3** | Nothing in town sells items | §6.4 | code read |
| **E4** | §11.1's economy arithmetic was never checked against shipped numbers | §11.1 | absence |
| **F1** | §14 steps 10 and 11 carry no **Done** marker and no changeset | §14 convention | doc read |
| **F2** | No step-10/11 questions document exists | steps 1–8 convention | doc read |
| **F3** | §14 states no completion criterion for the pass | — | doc read |

### 0.4 The green bar

Every fix in this document must leave the following passing, and must edit
**none** of §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_endless_level_gen`,
`test_retarget`, `test_parallax_seam`, `test_damage_chunk`).

```bash
for t in test_economy test_slot_odds test_upgrades test_autoload_safety test_endless_level_gen test_retarget test_parallax_seam test_damage_chunk test_enhanced_rarity test_profile_save test_profile_expedition test_drops test_item_distribution test_scene_router test_quest_gen test_quest_flow test_forge test_loot_pickup; do printf '%-28s ' "$t"; "C:/Projects/Godot/Godot/Godot.exe" --headless --path . "res://tests/$t.tscn" 2>&1 | tr -d '\r' | grep -E "RESULT (PASS|FAIL)" | head -1; done
```

Current baseline: **18 scenes, all `RESULT PASS`**, and a
`--headless --quit-after 120` boot that prints nothing but the engine banner.
Both were re-verified while writing this document.

### 0.5 Two workflow costs, already established

Carried forward from step-5 I8, step-6 N2 and step-8 Q10, because they apply to
any work here that adds a `class_name`, an autoload, or a test scene:

- adding a `class_name` costs one `godot --headless --editor --quit-after 20`
  pass before the suite resolves it;
- adding an autoload additionally costs one restart of any running editor.

Verify headless. A running editor's Errors panel can be red while the suite is
green, and it means nothing.

---

## 1. Method

Findings were produced by reading the spec against the tree, then confirming the
two behavioural claims with a throwaway probe rather than by inference. The
probe is reproduced in A1 and A2 so an implementer can re-run it before and
after a fix. It was deleted after use, per the step-6 / step-8 convention for
scratch verification.

Findings **not** confirmed at runtime are marked as such in §0.3's last column
and are argued from code rather than asserted from observation.

---

## 2. A-series — rules the code breaks

### A1. Buying out the blacksmith's stock is a free refresh

**Authority.** §7.4, stated as a rule rather than an aspiration:

> Generated once and cached on the profile (`GameState.forge_stock`), saved with
> it, and rerolled **only** by the refresh button. Walking out of the blacksmith
> and back in must not reroll — that is the same rule the quest shop already
> follows via `EncounterDef.cached_shop_items` (§21-D11), and breaking it turns
> leaving the screen into a free refresh.

**Where.** `scripts/town/blacksmith.gd:49` (the regeneration predicate) and
`:145` (the erase on purchase).

```gdscript
# blacksmith.gd:49 — _ready()
if GameState.forge_stock.is_empty():
    GameState.forge_stock = Itemizer.generate_forge_stock()
    SaveGame.save_profile()

# blacksmith.gd:145 — _on_purchased()
GameState.forge_stock.erase(item)
```

**Root cause.** `forge_stock.is_empty()` is being asked to mean *"never
generated"*, but after `:145` has run six times it also means *"sold out"*. The
two states are indistinguishable, so the sold-out one takes the never-generated
branch.

**Reproduction** (confirmed at runtime):

```gdscript
GameState.new_profile()
GameState.forge_stock = Itemizer.generate_forge_stock()
for i: Item in GameState.forge_stock.duplicate():
    GameState.forge_stock.erase(i)          # buy all six
var gold_before := GameState.gold
if GameState.forge_stock.is_empty():        # blacksmith.gd:49's exact predicate
    GameState.forge_stock = Itemizer.generate_forge_stock()
print("regenerated %d cards for %d gold (SHOP_REFRESH_COST=%d)" % [
    GameState.forge_stock.size(), GameState.gold - gold_before,
    Tuning.SHOP_REFRESH_COST])
```

```
regenerated 6 cards for 0 gold (SHOP_REFRESH_COST=100)
```

Six fresh cards, up to and including Rare, for nothing. The refresh button that
charges 100 gold for the same service is two nodes away in the same tab.

**Fix — put the decision on `GameState`, not in the scene.**

The predicate has to stop being derivable from the array's length, which means a
second field:

```gdscript
## [town] Whether forge_stock has ever been generated for this profile. Distinct
## from `forge_stock.is_empty()`, which is ALSO true once the player has bought
## every card - and using emptiness as the sentinel makes buying out the stock a
## free refresh, which is exactly what spec 7.4 forbids. Cleared by
## new_profile(); set by the blacksmith's first generation and by every reroll.
var forge_stock_generated: bool = false

## [town] Whether the blacksmith should generate stock on entry (spec 7.4). The
## ONLY caller is blacksmith.gd's _ready(); it lives here rather than in the
## scene so it is reachable headless (see tests/test_forge_stock.gd).
func needs_forge_restock() -> bool:
	return not forge_stock_generated
```

- `new_profile()` sets `forge_stock_generated = false` beside the existing
  `forge_stock.clear()` at `game_state.gd:623`.
- `blacksmith.gd:49` becomes `if GameState.needs_forge_restock():`, and the
  branch sets the flag before saving.
- `blacksmith.gd:150`'s `_on_refresh()` sets it too (harmless when already true,
  and correct if the ordering ever changes).
- `save_game.gd` serializes the flag. **No `VERSION` bump** — §2.4's policy is
  "bump when the meaning of an existing key changes, never merely to add one",
  and `load_profile()` reads through `d.get(key, default)`. `save_game.gd:49-51`
  already records exactly this reasoning for `forge_stock` itself; follow it.
- The **default matters**. Use `d.get("forge_stock_generated", not
  GameState.forge_stock.is_empty())` so a save written before this fix, holding
  a real stock, does not present as never-generated on the next load. A pre-fix
  save that was already bought out gets one free reroll; that is a one-time cost
  to a dev save and is not worth migration code.

**Acceptance.**

1. With `forge_stock_generated == true` and `forge_stock` emptied,
   `GameState.needs_forge_restock()` returns `false`.
2. Entering the blacksmith with a bought-out stock leaves `forge_stock` empty
   and spends no gold; the Buy tab shows its `BuyEmpty` label.
3. The refresh button still rerolls, still costs `SHOP_REFRESH_COST`, and still
   works from an empty stock — a player who bought out the stock must have a
   *paid* way back to six cards.
4. `new_profile()` leaves `needs_forge_restock()` true.
5. The flag survives a `save_profile()` / `load_profile()` round-trip.

**Do not** solve this by refusing to erase purchased items from `forge_stock` —
that would leave bought cards on the shelf across visits and contradicts
`blacksmith.gd:145`'s own stated intent ("the bought item leaves the persistent
stock, so walking back in does not offer it again").

---

### A2. `forge()` never emits `party_bonuses_changed`

**Authority.** §1.5 is the section arguing that three slots exist so equipped
gear feeds `party_bonuses()`; §3.3 establishes that gear mutations announce
themselves. Every other mutation of the equipped set — `add_item()`,
`equip_item()`, `unequip_item()`, `heal_party()` — emits
`EventBus.party_bonuses_changed`. `Itemizer.forge()` is the one that does not.

**Where.** `scripts/autoload/itemizer.gd:151-172`. The function appends a
modifier to an item that is, by §7.3's construction, always **equipped** — the
Forge tab lists `equipped_set()` and nothing else — then emits only
`item_forged` at `:171`.

**Reproduction** (confirmed at runtime):

```gdscript
GameState.new_profile()
var it := Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)
it.weapon_type = &"axe"
GameState.add_item(it)
GameState.equip_item(it, &"warrior")
var fired := [0]
EventBus.party_bonuses_changed.connect(func(_b: Dictionary) -> void: fired[0] += 1)
var before := GameState.party_bonuses().duplicate()
GameState.gold = 9999
GameState.scrap = 9999
Itemizer.forge(it)
print("bonuses %s -> %s  fired %d" % [before, GameState.party_bonuses(), fired[0]])
```

```
bonuses {dmg_pct: 0} -> {dmg_pct: 12}  fired 0
```

**Player-visible consequence.** `bonus_strip.gd:56` repaints only on
`party_bonuses_changed`, `run_started`, and its own `_ready()`.
`inventory_modal.open()` calls `_rebuild()` and `_update_currency()` but never
`bonus_strip.refresh()`, and `hud.tscn` — which owns the modal — is an autoload
instanced once at boot, so that `_ready()` fires exactly once per launch.
Therefore: **forge a slot at the blacksmith, open the inventory modal, and the
BonusStrip still shows the pre-forge numbers** for the rest of the session.

The second consumer, `battle_director.gd:66` → `Combatant.apply_party_bonuses()`,
is not currently reachable — the blacksmith is town-only and `spawn_party()`
reads fresh on the next expedition. It is listed because it is what makes the
missing emit a trap rather than only a cosmetic bug: the day anything forges
inside a quest, the heroes silently keep their old bonuses.

**Fix.** One line in `forge()`, after `item.value` is updated and beside the
existing `item_forged` emit:

```gdscript
EventBus.party_bonuses_changed.emit(GameState.party_bonuses())
EventBus.item_forged.emit(item, item.rarity)
```

Emit **unconditionally**, not only when `item.equipped_by != &""`. `forge()`'s
only caller today is the blacksmith, which forges equipped items exclusively;
the `forge <slot>` debug verb does the same. A conditional would encode a
precondition the function does not otherwise enforce, and `party_bonuses()` on
an unequipped item is a cheap no-op recomputation.

**Acceptance.**

1. The probe above prints `fired 1`.
2. Forging an equipped item and then opening the inventory modal shows the new
   bonus totals.
3. `test_forge.gd`'s existing 35 checks stay green, and gain one asserting the
   emission.

---

## 3. B-series — promised, never built

### B1. `CurrencyPlate` has no `OrnateFrame` treatment

**Authority.** §5.3, first sentence:

> `Hud/CurrencyPlate` shows gold and scrap side by side, using the same
> `OrnateFrame` treatment `status_panel`'s `GoldPlate` uses, and the same
> pop-and-float feedback on change.

The second half landed — `currency_plate.gd:16` preloads
`scripts/ui/currency_feedback.gd` and calls `pop()` / `float_delta()` on both
halves, and §5.3's own follow-up paragraph records that helper arriving at step
5. The first half did not: `scenes/hud/hud.tscn`'s `CurrencyPlate` is a bare
`PanelContainer` with no `StyleBox` override, no theme, and no `OrnateFrame`
child, sitting one canvas layer above a console built entirely out of
`OrnateFrame` chrome (`slot_machine.gd:21`, `status_panel.gd:14`,
`bonus_panel.gd:9`).

**Where.** `scenes/hud/hud.tscn`, the `CurrencyPlate` node and its `Row` subtree.

**Why it survived.** Step 5 shipped the plate as functional chrome and §14 step 5
records the deliberate acceptance that "the inventory button … wears no icon
until step 11". The icon was picked up at step 11; the plate's frame was not,
because §12's art list names the backpack, the six glyphs and the two
backgrounds, and never mentions the plate. §5.3 is its only authority and §12
never cross-references it.

**Fix.** Give `CurrencyPlate` the `OrnateFrame` treatment `status_panel`'s
`GoldPlate` uses. Read `scripts/console/status_panel.gd` and
`scripts/console/ornate_frame.gd` first and **reuse**, do not re-author: §12.3
and CLAUDE.md both push toward reuse, and `OrnateFrame` is already a `class_name`
node type. Per CLAUDE.md's "prefer inspector properties over code", the framing
belongs in `hud.tscn`, not in `currency_plate.gd`.

**Acceptance.** The HUD plate reads as part of the same UI family as the
console's gold plate at a glance, in town and in the forest. This is a visual
criterion; verify with a `play_scene` screenshot of `boot.tscn` (town) and of
`route quest` (forest), not headless.

**Do not** add a second scrap readout to `status_panel` while in here — §3.3
forbids it explicitly, and `currency_plate.gd`'s own header repeats the ban.

### B2. `Tuning.FORGE_SHOP_SLOTS` is documented-only

**Authority.** §0.1.5 — Tuning is the single source of truth and "no other file
may hardcode any of them" — and §11, which declares `FORGE_SHOP_SLOTS := 6`.

**Where.** All three live references are comments:

```
scripts/autoload/itemizer.gd:312   ## Tuning.FORGE_SHOP_SLOTS (2 per bucket x 3 buckets).
scripts/autoload/tuning.gd:196     ## ... FORGE_SHOP_SLOTS is the card count; ...
scripts/town/blacksmith.gd:9       ##   - Buy: FORGE_SHOP_SLOTS cards from ...
```

`generate_forge_stock()` (`itemizer.gd:313`) produces six by iterating three
literal bucket arrays and appending twice per bucket. Changing
`FORGE_SHOP_SLOTS` to 8 changes nothing, and three comments would then be lying.

**Fix, and the constraint on it.** §7.4 gives `generate_forge_stock()`'s body
verbatim and §0.3 pins `generate_shop_stock()`'s shape via `test_economy.gd`, so
this is deliberately *not* an invitation to redesign the generator. Two
acceptable resolutions, in preference order:

1. **Derive the count from the constant.** Keep the three buckets and compute
   the per-bucket draw as `Tuning.FORGE_SHOP_SLOTS / 3`, with a comment stating
   that the constant must stay a multiple of three. This makes the constant
   load-bearing and keeps §7.4's bucket structure intact.
2. **Assert the relationship.** If (1) reads worse than the literal, leave the
   body alone and let C1's test assert
   `generate_forge_stock().size() == Tuning.FORGE_SHOP_SLOTS`, which converts a
   silently-ignored constant into a failing test the moment anyone edits it.

Either satisfies §0.1.5's intent. Do not do both — (1) makes (2) tautological,
though (2) is still worth having as C1's first check regardless.

---

## 4. C-series — test coverage

### C1. `tests/test_forge_stock.gd` — the missing step-10 pinning test

**Authority.** Step-1 Q5 established the convention and every step since has
either honoured it or explicitly argued its way out:

> a step that buys isolation and then ships no assertion of its own has spent
> the isolation and not collected.

Steps 6 and 7 argued out of a permanent test on the grounds that their surface
was scene wiring with no cheap headless invariant, and covered themselves with
throwaway smokes. Steps 8 and 9 both *reversed* that reasoning where an
invariant existed — step-8 Q6 added `test_quest_flow.gd` for the keep/drop/heal
economy, and §14 step 9 added `test_loot_pickup.gd` because "`_split()`'s
sum-to-value invariant, the headless award path and the boss multiplier all
reduce to cheap headless checks, so they get a permanent file rather than only a
throwaway smoke."

Step 10 is in the second category and got neither. `generate_forge_stock()`'s
shape, `forge_stock`'s persistence and A1's restock predicate are all pure
headless invariants. **A1 and B2 would both have been caught by this file.**

**Ship `tests/test_forge_stock.gd` + `.tscn`**, in the house style (see
`tests/test_loot_pickup.gd` for the header format and `tests/test_support.gd`
for `check` / `check_between` / `guard_user_file` / `finish`). Wrap it in
`t.guard_user_file(SaveGame.PATH)` — it round-trips a profile, and step-2 Q8 is
emphatic about that guard.

Checks, at minimum:

**Stock shape (§7.4, B2)**
1. `Itemizer.generate_forge_stock().size() == Tuning.FORGE_SHOP_SLOTS`.
2. Over ~400 stocks, **no** item has `rarity == Item.Rarity.ENHANCED` — §7.4's
   "`ENHANCED` never appears in shop stock; it is forge-only", which is the same
   guarantee `test_enhanced_rarity.gd` makes for `generate_item()` and which
   `generate_forge_stock()` reaches by a different path.
3. Over the same sample every rarity `COMMON`..`RARE` appears at least once —
   the three buckets are supposed to span the ladder, and a bucket literal typo
   would otherwise be invisible.
4. Every item's `slot()` is one of the three, and `usable_by()` is non-empty for
   `GameState.active_party` — slot-first generation (§4.4) applies here too.

**`generate_shop_stock()` is untouched (§7.4, §0.3)**
5. `generate_shop_stock().size() == Tuning.SHOP_ITEMS_FOR_SALE`, and the two
   functions are distinct — §7.4's "**This is a new generator function, not a
   parameter on `generate_shop_stock()`**", the whole reason it exists
   separately. `test_economy.gd` pins the shop side; nothing currently pins that
   the forge side did not grow into it.

**Restock predicate (A1)**
6. After `new_profile()`, `GameState.needs_forge_restock()` is `true`.
7. After a generation that sets the flag, it is `false`.
8. After the flag is set and `forge_stock` is emptied item by item, it is
   **still** `false` — *this is A1's regression guard and the most valuable
   check in the file.*
9. A reroll leaves it `false`.

**Persistence (§2.4)**
10. `forge_stock` round-trips through `save_profile()` / `load_profile()`:
    count, and per item `weapon_type`, `rarity`, `value`, `forge_count` and
    `modifiers.size()`.
11. `forge_stock_generated` round-trips.
12. A save dict with **no** `forge_stock_generated` key loads with the derived
    default from A1 (`not forge_stock.is_empty()`), not a bare `false`.

Add the file to §13.1 with its checks listed, in the format that section already
uses for `test_quest_flow.gd` and `test_loot_pickup.gd`.

### C2. Remove `tests/_scratch_shop_touch.gd`

A 180-line scratch harness from the earlier shop pass, self-labelled
`## [scratch]` in its own first line, sitting in `tests/` among the real suites.
It has no `.tscn`, is not run by anything, and its coordinate comments are
already stale by its own admission ("go stale if the row geometry changes").
Steps 6 and 8 both deleted their scratch scenes after use; this one predates that
habit. Delete it.

---

## 5. D-series — hygiene and latent cost

### D1. `hud.gd` runs a recursive whole-tree search every frame

`scripts/hud/hud.gd:42`, inside `_combat_locked()`, called from `_process()` at
`:34`:

```gdscript
var rc := get_tree().root.find_child("RunController", true, false)
```

`find_child(..., recursive = true)` walks the entire tree below `/root`, which
during a quest is `main.tscn` plus the battle world, every rendered frame, on a
portrait Android target. `_combat_locked()` early-returns when
`SceneRouter.place != Place.QUEST`, so town is unaffected — but a quest is where
the frame budget actually matters.

Cache it instead. The natural hook is the same one that already exists:
`RunController._ready()` asserts `SceneRouter.place = Place.QUEST` as its first
line (§14 step 5), so it can equally register itself on `Hud`, with `Hud`
clearing the reference when `place` leaves `QUEST`. Guard the read with
`is_instance_valid()` — `SceneRouter.go()` frees `main.tscn` and the
`RunController` in it, which is the whole subject of step-8 N2.

Behaviour must not change: the button stays disabled exactly when
`place == QUEST and RunController.state == COMBAT`, per §3.2.

### D2. `scene_router.go()`'s `place` comment contradicts its code

`scripts/autoload/scene_router.gd:64-66`:

```gdscript
# Set before the fade-out so the new scene's _ready() reads the right value
# (spec 3.2's InventoryButton COMBAT rule depends on it - step-5 Q8).
place = to
```

The assignment sits *after* `await get_tree().tree_changed` and
`await get_tree().process_frame`, so the incoming scene's `_ready()` has already
run by the time it lands. Step-5 I8 and §14 step 5 both state the true
behaviour — "`place` is assigned after the swap settles, so it trails the
incoming scene's `_ready()`" — and it is precisely *why* every routed scene
re-asserts its own `place` in `_ready()` (step-5 Q8).

The comment is only half wrong — "before the fade-out" is accurate — but the
clause after it inverts the reason the mitigation exists, and would talk a future
reader out of the per-scene re-assertion as redundant. Reword to name what the
ordering actually buys (`place` is correct before the screen is visible again)
and cross-reference step-5 Q8 for why `_ready()` cannot rely on it.

Comment-only. Do not move the assignment: the five `_ready()` re-assertions
depend on the current ordering being harmless, and changing it is a
router-lifecycle edit with no defect behind it.

### D3. `item_glyph.gd`'s procedural fallbacks are unreachable

Step 11 added Meshy icons for all six armor and trinket types, so
`WEAPON_TEXTURES` now covers **all eleven** `ITEM_TYPES` keys. `_draw()`'s
`match weapon_type` block at `scripts/modals/item_glyph.gd:71` lives in the
`else` branch of `if WEAPON_TEXTURES.has(weapon_type)`, so `_draw_blade` (`:87`),
`_draw_axe` (`:105`), `_draw_bow` (`:124`) and `_draw_staff` (`:138`) can no
longer be reached. `_draw_gem` (`:143`) survives as the `_:` arm, reachable only
for `weapon_type == &""` (a bare `Item.new()`), which
`test_item_distribution.gd`'s element-tie probe still constructs — so it stays.

Delete the four dead builders and the `match` arms that call them, keeping the
`_draw_gem` fallback and its comment. `_draw_axe` in particular is the function
CLAUDE.md cites as its cautionary tale for hand-written coordinate geometry
("two failed geometry rewrites before it read correctly"); leaving it in the file
invites someone to maintain it.

Verify with a screenshot of the inventory modal and a shop Buy tab before and
after — this is dead-code removal, so the frames must be identical.

### D4. `forge_row.gd` duplicates the rarity-name array

`scripts/modals/forge_row.gd:18` declares
`const RARITY_NAMES := ["Common", "Uncommon", "Magic", "Rare", "Enhanced"]`,
byte-identical to the literal inside `Item.rarity_name()`
(`scripts/data/item.gd`). The row needs the *destination* rarity's name
(`RARITY_NAMES[item.rarity + 1]` at `:66`), which the instance method cannot
give it — so this is a real need, met by a copy.

Give `Item` a static accessor and delegate:

```gdscript
static func rarity_name_for(r: int) -> String:
	return ["Common", "Uncommon", "Magic", "Rare", "Enhanced"][r]

func rarity_name() -> String:
	return rarity_name_for(rarity)
```

`forge_row.gd:66` then reads `Item.rarity_name_for(item.rarity + 1)` and the
`const` goes. Same class of fix as step 6's `item_card_style.gd` — one array, one
owner. `test_enhanced_rarity.gd` already asserts `rarity_name()` covers
`ENHANCED`, so the delegation is covered.

### D5. `currency_plate.gd`'s header is stale

`scripts/hud/currency_plate.gd`, two claims that stopped being true at step 9:

- "The scrap half has no faucet until step 9 (spec 5); until then
  `scrap_changed` never fires and the value just sits at whatever
  `load_profile()` restored."
- on `SCRAP_COLOR`: "the path is dead until step 9 gives scrap a delta."

Step 9 shipped `add_scrap` / `spend_scrap` and the pickups. Both paths are live.
Reword to present tense.

---

## 6. E-series — decisions nothing records

**These want a ruling, not a patch.** Each is a place where the current behaviour
may well be correct and merely undocumented — but no document says so, which is
the difference between a decision and an omission. §15 exists precisely to hold
this kind of thing ("Recorded so they are decisions rather than omissions"). An
implementing model should surface these and **not** choose.

### E1. The HUD's `CurrencyPlate` collides with `BonusPanel`

`scenes/hud/hud.tscn` puts `CurrencyPlate` at x 724–1056, y 24–110 on the
1080-wide portrait viewport. `scenes/overlay/bonus_panel.tscn` was anchored
top-right at x 874–1064, y 16–46. They overlap, and the HUD is `layer = 10`, so
the plate wins.

There is an **uncommitted** working-tree fix moving `BonusPanel` to
`offset_top = 130` / `offset_bottom = 160`. It is almost certainly the right
call. But:

- §3.2 specifies `CurrencyPlate`'s *contents* and never its position;
- §0.2 fences the slot machine and its reels off from this pass, and
  `BonusPanel` is console furniture;
- so a step-5 node landed on top of an out-of-scope element, and nothing in §3.2,
  §5.3 or §14 step 5 records either the collision or the resolution.

**Ruling wanted:** confirm the 130px move, then record it — in §3.2 beside the
plate's description, and in §14 step 5's changeset as an amendment. Also note
that `CurrencyPlate` uses bare `offset_*` with no anchors, so it is positioned
for exactly one viewport width; whether that is acceptable is a second, smaller
question worth answering at the same time.

Two other uncommitted changes sit alongside it and are **not** town work —
`scripts/console/slot_reel.gd`'s `_stopping` state fix and
`scenes/modals/quest_result.tscn`'s panel re-anchor. The `slot_reel` change looks
like a genuine independent bug fix (the reel froze on its last spinning frame
while `payline_symbol()` already reported the target). It should not be committed
under a town-initiative message.

### E2. A quest cannot be abandoned

In `Place.QUEST` the HUD carries the inventory button and nothing else. Every
other routed scene has a Back button and an `ui_cancel` handler (§7.1: "Every
interior scene carries a **Back** button routing to `Place.TOWN`"); the forest
has neither. The only exits are victory (§8.5) and a party wipe (§8.5's failure
flow).

This may be exactly right — the failure cost in §0.4 is "keep gold and scrap,
lose loose items", and a free walk-out would let a player bank an expedition's
pickups and skip the boss, which is the arbitrage §8.5's discard rule exists to
prevent. But §0.2's "what this does NOT build" list does not mention it, so it
reads as an oversight rather than a decision.

**Ruling wanted:** either a §0.2 bullet ("no quest abandonment — walking out
would let a player bank pickups and skip the risk") or a §15 deferral.

### E3. Nothing in town sells items

§6.4 is deliberate and well argued — the inventory modal has no sell action
because "an always-available sell button in a modal reachable mid-expedition is
an always-available gold faucet". The blacksmith has Forge and Buy only
(`blacksmith.gd:15`: "No Sell tab - selling stays at the quest shop where a
merchant is standing").

The consequence §6.4 does not follow through on: **selling exists only inside a
quest**, at that quest's shop encounter. A player who returns from a hard quest
with nine unequipped items can neither sell nor scrap them in town, and the
inventory has no cap, no bulk action, and no junk-to-scrap conversion — §5.1
forbids the last one outright ("never bought, never sold, and never convertible
to gold in either direction"). The Carried section of the inventory modal grows
monotonically across a profile's life.

**Ruling wanted:** is the quest shop the intended sole sink, with inventory
growth accepted? If so it belongs in §6.4 as a stated consequence. If not, the
options are a blacksmith Sell tab (contradicting `blacksmith.gd`'s header), a
town-only sell action in the modal (§6.4's faucet argument does not apply in
town, where no expedition is running), or an inventory cap. This interacts with
§15's "Repricing the slot economy for a profile-scoped wallet" and probably wants
deciding with it.

### E4. §11.1's economy arithmetic was never checked against shipped numbers

§11.1 ("Does the loop close?") is the economic justification for the entire
pass: ~+198 gold / +32 scrap per easy quest, ~+676 / +84 per hard, against 189
scrap and 750 gold for a full three-slot forge, giving "roughly six runs" on easy
and "two or three" on hard.

Every input is now shipped and tunable — `ENEMY_GOLD_DROP`, `ENEMY_SCRAP_DROP`,
`BOSS_LOOT_MULT`, the three `gold_reward`s, `INN_REST_COST_PER_HERO`,
`FORGE_COSTS` — and nothing checks the arithmetic. There is no test, no playtest
record, and the initiative is nominally complete. §11.1 closes with "These are
starting numbers … in one place precisely so they can be moved", which is a
reason to expect them to move, not a reason not to measure them once.

**Ruling wanted:** whether to add a headless economy-projection check (simulate N
easy and N hard quests through the real drop rolls, assert the per-quest
gold/scrap yield lands within a band of §11.1's figures) or to record §11.1
explicitly as unverified and defer it to a balance pass in §15. The first is
maybe 40 lines against `LootPickup._split()` and the quest `.tres` files; the
second is one bullet. Both are defensible; guessing is not.

---

## 7. F-series — the spec is behind the code

### F1. §14 steps 10 and 11 carry no **Done** marker and no changeset

Steps 1 through 9 each end with **Done.**, a file-by-file changeset, and a "what
this step accepts, deliberately" note. Steps 10 and 11 are two lines:

```
10. **§7.3, §7.4 — the blacksmith**, forge and expanded shop.
11. **§12 — art**: Meshy icons and the two backgrounds.
```

Commit `6b46877` ("step 10 & 11 of the town/forge update") touched 38 files and
**no design document**. Amend §14 to match steps 1–9's format, from the commit:

- **step 10** — `scenes/town/blacksmith.tscn` + `scripts/town/blacksmith.gd`
  (two tabs, `equipped_set()` forge list, empty-slot placeholder rows, cached
  `forge_stock`, refresh button); `scenes/modals/forge_row.tscn` +
  `scripts/modals/forge_row.gd`; `Itemizer.generate_forge_stock()` /
  `_generate_in_bucket()`; `GameState.forge_stock`; `SaveGame`'s `forge_stock`
  key **with the deliberate no-`VERSION`-bump reasoning already at
  `save_game.gd:49-51`**; `Tuning.SHOP_REFRESH_COST` / `FORGE_SHOP_SLOTS`;
  `test_scene_router.gd`'s BLACKSMITH check; router and `town.gd` comments.
- **step 11** — the six `weapon_*.png` glyphs, `ui_backpack.png`,
  `blacksmith-bg.png`, `mayor-bg.png`; `item_glyph.gd`'s `WEAPON_TEXTURES`
  entries; `hud.tscn`'s button icon; `mayor_office.tscn`'s background swap;
  `battle_vfx.gd` and `overworld_field.gd` (both touched in the same commit —
  determine whether they belong to step 11 or rode along, and say which).

Add the "what it accepts, deliberately" notes both steps lack. For step 11 that
should include D3's consequence: the procedural glyph builders are now dead.

### F2. No step-10/11 questions document

Steps 1–8 each produced one, and steps 4, 5 and 8 each found at least one thing
that would otherwise have shipped broken — step-2 Q10 (step 5 destroying the
profile), step-4 Q11 (`test_drops` D4/D9), step-8 Q2 (`RunController` awaiting
its own removal). Steps 7 and 9 skipped the document but folded a full changeset
into §14; steps 10 and 11 folded nothing.

**This document is that missing pass, run late.** The two A-series defects are
its yield, which is roughly the historical rate. Either fold this document's
answers back into the spec the way steps 1–8 did, or explicitly retire the
convention — but record which.

### F3. §14 states no completion criterion for the pass

The build order ends at step 11 and stops. Nothing says what "the town initiative
is finished" means, and §0.1's nine deliverables have no corresponding checklist.
Add a closing subsection to §14 — the green bar from §0.4 above, a runtime smoke
covering the full loop (boot → town → mayor → quest → victory → mayor → inn →
blacksmith → forge), and a pointer to this document's E-series as the open
questions.

---

## 8. Suggested order of work

Dependency-ordered; each group leaves the game green, per §14's own rule.

1. **C2** — delete the scratch file. Zero risk, costs nothing.
2. **A1 + B2 + C1 together.** A1 introduces `forge_stock_generated` and
   `needs_forge_restock()`; B2 makes `FORGE_SHOP_SLOTS` load-bearing; C1 is the
   test that pins both. Writing C1 first, red, then A1 and B2 to green, is the
   cheapest path — C1's check 8 is A1's regression guard and check 1 is B2's.
3. **A2.** One line plus one assertion in `test_forge.gd`. Independent of (2).
4. **D4, D5, D2.** Comment and small-refactor cleanups; no behaviour change.
   Re-run the suite after D4 (it touches `item.gd`).
5. **D3.** Dead-code removal, verified by identical before/after screenshots.
6. **D1.** The `RunController` caching change. Last of the code work because it
   touches the router/HUD lifecycle seam and wants a runtime check, not a
   headless one: `route quest`, confirm the inventory button still disables in
   COMBAT and re-enables in travel.
7. **B1.** The `OrnateFrame` pass on `CurrencyPlate`. Art/chrome, verified by
   screenshot; independent of everything above.
8. **E1–E4.** Surface for a ruling. Do not implement without one.
9. **F1–F3.** Amend the spec last, so the changesets describe what actually
   shipped including this pass's own fixes.

---

## 9. Acceptance checklist

The initiative is accepted when every line is true.

**Behaviour**
- [ ] Buying out the blacksmith's six cards and re-entering rerolls nothing and
      spends nothing; the paid refresh still works from empty (A1)
- [ ] Forging an equipped item updates the inventory modal's BonusStrip in the
      same session (A2)
- [ ] The HUD currency plate carries the console's `OrnateFrame` treatment (B1)
- [ ] `Tuning.FORGE_SHOP_SLOTS` is read by code, or asserted by a test (B2)
- [ ] The inventory button still disables in COMBAT and only in COMBAT (D1)

**Tests**
- [ ] `tests/test_forge_stock.gd` exists and passes, with checks 1–12 of C1
- [ ] `test_forge.gd` asserts `party_bonuses_changed` fires on a forge
- [ ] `tests/_scratch_shop_touch.gd` is gone
- [ ] All 19 suites `RESULT PASS` via §0.4's command
- [ ] §13.3's eight no-edit tests were not edited
- [ ] `--headless --quit-after 120` prints nothing but the engine banner

**Code hygiene**
- [ ] `item_glyph.gd`'s four unreachable builders are gone; `_draw_gem` remains
- [ ] `Item.rarity_name_for()` is the single owner of the rarity-name array
- [ ] `scene_router.go()`'s `place` comment matches its code
- [ ] `currency_plate.gd`'s header no longer says "dead until step 9"

**Runtime smoke** — one pass, driven end to end
- [ ] boot → town → mayor → accept easy → forest → victory → mayor's office with
      `QuestResult` up → "Retire for the evening" → inn → rest → town →
      blacksmith → forge a slot → open the inventory modal and see the new bonus

**Documents**
- [ ] §14 steps 10 and 11 carry **Done.**, a changeset, and an accepts-note (F1)
- [ ] This document's A–D answers are folded into the spec, or the convention is
      explicitly retired (F2)
- [ ] §14 closes with a completion criterion (F3)
- [ ] E1–E4 are each either resolved in the spec or recorded in §15 as deferred
