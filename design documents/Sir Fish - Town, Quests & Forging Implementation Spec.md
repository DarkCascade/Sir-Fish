# Sir Fish — Town, Inventory, Quests & Forging Implementation Spec

Target: turn the game from a single endless forest run into a **town hub loop** —
take a quest, run a bounded forest expedition, come home with gold and scrap,
spend it on gear, go again — with the player's progress surviving the app being
closed.

Written against the `meshy-shop-pass` branch, on top of
`quest-system-initial-vision.txt`. Section numbers in the form §13.5 refer to
*Sir Fish — Demo v5 Implementation Spec*; references to the drops document are
marked "(drops §4.2)"; bare §4.2 refers to **this** document.

---

## 0. Scope

### 0.1 What this builds

1. **A profile** — gold, scrap, inventory and equipment that live *above* a
   single expedition and are **saved to disk** (§2).
2. **Three equipment slots** per hero (weapon / armor / trinket), replacing
   today's one-item-per-hero rule (§4).
3. **Scrap metal**, a second currency, with one faucet (combat) and one sink
   (the forge) (§5).
4. **A persistent HUD** — inventory button and currency plate that survive
   scene changes — and the **inventory modal** behind it (§3, §6).
5. **A town hub** with three interiors: inn, blacksmith, mayor's office (§7).
6. **The forge** — spend scrap and gold to walk an equipped item up the rarity
   ladder, one modifier per step, ending at a new **Enhanced** rarity (§7.3,
   §10).
7. **Quests** — three bounded, authored expeditions with real difficulty tiers,
   replacing endless mode as the default (§8).
8. **Gold and scrap pickups** that burst from dying enemies (§9).
9. Tests that gate the save round-trip, the forge ladder and the quest
   generator (§13).

### 0.2 What this does NOT build — do not drift into these

- **No mid-quest save/resume.** Closing the app inside the forest loses that
  expedition and returns the player to town on next launch. The profile is
  saved; the expedition is not (§2.4).
- **No party beyond the warrior.** Mage and ranger keep their `.tres`, scenes,
  rigs and animations; nothing spawns them. `PARTY_ORDER` is *not* deleted
  (§4.5).
- **No new modifier ids.** The Enhanced pool is the existing pool with doubled
  rolls, not a second table (§10.3). This is the single most important
  simplification in this document.
- **No changes to `SLOT_STRIP`, the win rule, or the 50.038% win rate**
  (§16.2). The slot machine's *payouts* change only through
  `party_bonuses()`, which is data it already reads.
- **No physics for loot pickups.** Tweened arcs, not `RigidBody3D` (§9.2).
- **No Meshy spend on coins or scrap.** Those are primitives; see §12.
- **No town NPCs, dialogue, day/night cycle, or quest log.** The mayor hands
  out three buttons.

### 0.3 What must keep working byte-for-byte

These tests must pass **with no edits to the test files**:

| test | what pins it |
|---|---|
| `test_economy.gd` | `Tuning.STARTING_GOLD` stays **75** and keeps its meaning (§2.3). `generate_shop_stock()` keeps returning `SHOP_ITEMS_FOR_SALE` items with the same bucket spread — the blacksmith gets a **new** function, not a parameter on this one (§7.4). `buy_price()` / `sell_price()` formulas are untouched (§10.5). Every new item type's `base_value` lands in the existing **18–25** band, so the affordability gate at `test_economy.gd:94` holds (§4.2). |
| `test_slot_odds.gd` | nothing in this pass touches the reels. |
| `test_upgrades.gd` | slot upgrades stay run-scoped and are **not** the forge (§5.4). |
| `test_autoload_safety.gd` | new autoloads must be safe to instantiate headless (§3.1). |
| `test_item_distribution.gd` | `modifiers.size() == RARITY_MOD_COUNT[rarity]` must hold **after every forge step too** (§10.2). Adding `ENHANCED` at weight **0** keeps it out of generated output entirely (§10.1). |

Four tests **do** need edits, and those edits are part of this pass (§13.2 is
the full list; all four land at step 4):

- `test_drops.gd` — its `droppable_classes() == PARTY_ORDER` assertion becomes
  `== GameState.active_party` (§4.5), and **D7's type-mix expectations are
  re-derived** for §4.4's slot-first roll. D7 is the suite's only
  type-distribution assertion; D4 and D9 also move, because `next_drop_class()`
  reads `droppable_classes()` transitively (§4.5).
- `test_item_distribution.gd` — its four-wide rarity arrays widen to five
  (step-3 Q6). It asserts no type mix, so nothing in §4.4 reaches it, and the
  mod-count invariant above does **not** change.
- `test_profile_expedition.gd` — P6's `active_party` check (§4.5).
- `test_profile_save.gd` — its fixture's three equipped items become one per
  slot (§13.1).

### 0.4 Decisions taken

Four forks were resolved before writing. They are recorded here because the
rest of the document assumes them.

| fork | decision | why |
|---|---|---|
| Solo warrior vs. party | **Solo warrior, three equip slots** | One item per hero made `party_bonuses()` collapse to a third of its former strength and turned 60% of generated loot into vendor trash. Three slots restore the magnitude, give the forge a screen worth opening, and give scrap a sink that lasts (§4). |
| Persistence | **Save to disk, profile-scoped** | This is a portrait Android game; the OS kills backgrounded apps. A hub loop whose bank evaporates on app suspend is not a hub loop (§2). |
| Quest failure cost | **Keep gold and scrap, lose loose items** | Equipped gear survives, currency banks, unequipped items found on the expedition are lost. Keeps a failed hard quest from being pure profit without making a 9-encounter loss total (§8.5). |
| Forge ladder | **Walk the full enum, four steps** | The original three-step ladder skipped `UNCOMMON` (30% of all rolls) and broke `modifiers.size() == RARITY_MOD_COUNT[rarity]`, the invariant `test_item_distribution.gd:68` encodes. Four steps preserve it exactly (§10.2). |

---

## 1. The problems this pass solves

Stated plainly, because each one is a thing that is broken *today* the moment
the town becomes a hub.

**1.1 There is no persistence of any kind.** `grep -r "user://\|ConfigFile\|ResourceSaver\|FileAccess" scripts/`
returns nothing. Every number the player accumulates lives in autoload memory,
and `GameState.reset_run()` clears gold and inventory on every retry.

**1.2 `reset_run()` conflates two lifetimes.** It resets gold, inventory, hero
HP, `Upgrades`, `drops_by_class` and `run_stats` in one breath. Under a hub the
first two belong to the *profile* and the rest to the *expedition*. This is the
highest-risk refactor in the document, because `_start_run()` calls it on every
path into the forest.

**1.3 `main.tscn` *is* the run.** `RunController._ready()` reaches into its
parent by literal node path (`BattleView/BattleViewport/BattleWorld`,
`ModalLayer/ShopModal`, …). There is no scene router, no transition, and the
town scenes are scriptless `Control` mockups with two dead buttons.

**1.4 Gold has exactly one faucet.** `GameState.add_gold()` is called from
`slot_machine._pay_gold()` and `shop_sell_row._on_sell()`. Enemies drop items,
never currency.

**1.5 `party_bonuses()` is party-wide and additive.** Every equipped item feeds
one pool of `dmg_flat` / `dmg_pct` / `slot_bolt` / `slot_purse` / `slot_mend`.
Three heroes carried three items into that pool. One hero carrying one item
carries a third as much — and the slot machine, the core loop, is what reads it.

**1.6 Loot rolls weapon type uniformly across five types.** Bow, dagger and
staff are 60% of `Itemizer.generate_item()`'s output and a solo warrior can
equip none of them.

**1.7 The rarity ladder has a hole in it.** `Item.Rarity` is
`COMMON, UNCOMMON, MAGIC, RARE`. The original plan's forge goes
common → magic → rare and never says what an Uncommon becomes.
`RARITY_MOD_COUNT = [0, 1, 2, 3]` means "Common + 1 modifier" is a **1-modifier
Magic**, where a found Magic has 2 — the rarity label starts lying about power,
and `test_item_distribution.gd:68` is the assertion that says so.

**1.8 `compare_flyout.show_for()` looks up the equipped item with no slot.** It
calls `GameState.equipped_item(hero_class)`, which returns the *first* item in
inventory that hero has equipped. With three slots it will happily compare a
helm against a sword.

**1.9 "Sleep in the street for half your missing HP, free" converges to a full
heal** if it can be repeated. Half of half of half is arbitrarily close to
whole.

**1.10 Difficulty tiers differ only in length.** Same enemy pool, same counts.
Hard is not harder per encounter, it is longer — and with no between-encounter
heal (`game_state.gd` header) length *is* difficulty, but it is the only axis,
so the curve is flat forever after the first clear.

**1.11 The loot explosion as originally specified costs ~2 seconds per
combat.** "After the model is done fading" puts the burst *after*
`ENEMY_DEATH_HOLD_RUSH + ENEMY_DEATH_FADE_RUSH` (0.75s), then adds a 1s settle
and a fade, *then* the existing `ENCOUNTER_RESOLVE_PAUSE` (0.8s) and the drop
label stagger. On a project that has a *Gameplay Smoothness Analysis* on disk,
that is the wrong trade.

---

## 2. Profile vs. expedition

### 2.1 The split

Two lifetimes, named explicitly so no future reader has to guess:

- **Profile** — survives everything, saved to disk. Gold, scrap, inventory
  (including equipped state and forge history), hero HP, and the
  street-sleep flag.
- **Expedition** — one quest, from the mayor's desk to the result modal.
  `run_stats`, `Upgrades` levels, `current_encounter_index`, `level`,
  `drops_by_class`, and the quest's own banked gold/scrap.

Hero HP is deliberately **profile**-scoped: the inn only means something if
damage carries home.

### 2.2 `scripts/autoload/game_state.gd` — new state

```gdscript
## [town] Scrap metal. The forge's currency (§7.3). Profile-scoped, exactly
## like gold - the two are siblings everywhere they appear, which is why this
## sits directly under `gold` rather than in a resources dictionary: two named
## fields read better at every call site than `resources[&"scrap"]`, and there
## is no third currency planned.
var scrap: int = 0

## [town] The heroes that actually take the field. PARTY_ORDER stays the
## canonical roster (it is what the drop-coverage weighting is written against,
## and what a returning three-hero party would restore in one line); this is
## who is currently in it. Profile-scoped.
##
## `[&"warrior"]` is the END-state value. §14 step 1 initialises this to the
## full `PARTY_ORDER` instead, deliberately - see §4.5, which is where the
## value flips and the party actually goes solo.
var active_party: Array[StringName] = [&"warrior"]

## [town] The quest currently being run, or null in town. Replaces
## endless_mode as the thing build_level() dispatches on (§8.3).
var quest: QuestDef = null

## [town] Gold and scrap picked up during the CURRENT expedition, banked
## separately so the result modal can state "you brought home 47 scrap"
## without diffing two profile totals across a scene change (§8.5).
var expedition_gold: int = 0
var expedition_scrap: int = 0

## [town] Whether the free street-sleep has already been used since the last
## quest start. Cleared by start_expedition(). Without this, half-of-missing
## repeated is a free full heal (§1.9).
var street_sleep_used: bool = false

## [town] Inventory size at the moment the current expedition started. §8.5's
## failure flow discards unequipped items at indices >= this mark, which is
## what lets "brought from town" be told apart from "found this trip" without
## a flag on every Item. Written only by start_expedition(); the underscore
## means the failure flow should reach it through a GameState helper rather
## than by touching the field from RunController.
var _expedition_inventory_mark: int = 0
```

`add_scrap(amount)` / `spend_scrap(amount)` mirror `add_gold` / `spend_gold`
exactly, including the `EventBus.scrap_changed(new_total, delta)` emission
(§3.3). `spend_scrap` returns `false` and mutates nothing when the player
cannot afford it, same contract as `spend_gold`.

### 2.3 Splitting `reset_run()`

`reset_run()`'s *body* is replaced by two functions. Do this first and in
isolation — nothing else in this document is safe until it is done.

**`reset_run()` itself survives this pass**, reduced to a two-line wrapper that
calls both halves in sequence. It is not a temporary shim: §13.3 requires
`test_endless_level_gen.gd` to keep passing with **no edits** for the whole
pass, and that test calls `reset_run()` directly. Deleting the function would
force exactly the test edit §13.3 forbids. It stays as endless mode's entry
point, while quest accept (§8) calls `start_expedition()` **alone** — and that
lone call is the path on which gold, scrap and inventory finally survive a
retry. The split is what matters; the old name keeping a caller is free.

```gdscript
## The endless-mode entry point: the one caller that wants BOTH halves.
func reset_run() -> void:
	new_profile()
	start_expedition()
```

```gdscript
## [town] A brand new profile. Called once, when there is no save file.
## Everything a player owns starts here.
##
## DOES NOT SAVE - see "new_profile() never persists" below.
func new_profile() -> void:
	gold = Tuning.PROFILE_STARTING_GOLD
	scrap = Tuning.PROFILE_STARTING_SCRAP
	inventory.clear()
	active_party = [&"warrior"]
	street_sleep_used = false
	_reset_hero_runtime(true)      # full HP

## [town] Everything an expedition owns, and NOTHING a profile owns. Called
## from the mayor's office on quest accept.
##
## Note what is absent: gold, scrap and inventory. That absence is the whole
## point of this function existing separately from new_profile(), and is the
## one thing a future edit here must not undo.
func start_expedition(q: QuestDef) -> void:
	quest = q
	current_encounter_index = -1
	endless_level_number = 1       # MUST precede build_level(), which reads it
	expedition_gold = 0
	expedition_scrap = 0
	street_sleep_used = false
	_expedition_inventory_mark = inventory.size()   # §8.5
	drops_by_class.clear()
	Upgrades.reset()
	level = build_level()
	_reset_hero_runtime(false)     # keep current HP - the inn is the heal
	for key: String in run_stats.keys():
		run_stats[key] = 0.0 if key == "run_time" else 0
	EventBus.gold_changed.emit(gold, 0)
	EventBus.scrap_changed.emit(scrap, 0)
	EventBus.party_bonuses_changed.emit(party_bonuses())
```

`_reset_hero_runtime(full_heal: bool)` rebuilds `hero_runtime` from
`active_party` (not `PARTY_ORDER`), preserving `current_hp` when `full_heal` is
false and an entry for that `stats_id` already exists. `alive` is **derived**
from the resulting hp (`hp > 0`), never assumed true — a hero who died stays
dead until §8.5's recovery buttons heal them.

`endless_level_number = 1` is expedition progress, not profile state, and
belongs here: `_build_endless_level()` reads it, so it must be assigned
**before** `build_level()`. Omitting it makes a retry regenerate at the depth
the party died on; `test_endless_level_gen.gd:13` is what catches that.

**Step-1 placeholders.** `new_profile()` above is written against §11's
`PROFILE_STARTING_GOLD` / `PROFILE_STARTING_SCRAP` and §2.4's
`SaveGame.save_profile()`, none of which exist at step 1. Step 1 therefore ships
`gold = Tuning.STARTING_GOLD`, `scrap = 0` and no save call, marked inline in
the source. **Step 2 resolves all three** as it lands `SaveGame` and makes this
function the genuine no-save fallback — a 75-gold profile shipping forever is
the failure mode. Two are replaced with the §11 constants; the third — the save
call — is **removed by design**, per the rule immediately below. *(Settled in
step-2 Q4; this paragraph previously said "replace all three".)*

**`new_profile()` never persists.** It is a memory-only reset. Whoever *decides*
a new profile is real — `boot.tscn`, on `load_profile()` returning `false`
(§3.1) — is what calls `SaveGame.save_profile()`, on the one line where that
decision is actually made.

The reason is that `new_profile()` is **destructive** and `reset_run()` calls it
unconditionally, which `RunController._start_run()` calls on every boot and
every retry. A save inside it means every launch of the game overwrites the
player's file with a fresh profile *before anything has had a chance to load
it*. A new profile is fully deterministic — 150 gold, empty inventory, full HP —
so re-deriving it after a crash costs nothing; there is no state here worth
persisting eagerly. §2.4's own "When to save" list never names this function.

The same property is what keeps the test suite honest: `test_endless_level_gen.gd`
and `test_profile_expedition.gd` both reach `new_profile()` through `reset_run()`,
and neither may be allowed to overwrite the dev's real save at
`user://profile.save`. With the save call gone they touch no file at all — which
matters because §13.3 forbids editing the first of those two (step-2 Q8).

**`Tuning.STARTING_GOLD` keeps its value of 75 and is not renamed.** It now
means "gold the *slot economy* was balanced against", which is exactly what
`test_economy.gd:41` asserts and §5.4 derived. The new `PROFILE_STARTING_GOLD`
(§11) is a separate constant. Conflating them breaks a green test for no gain.

### 2.4 `scripts/autoload/save_game.gd` — new autoload

Registered **after** `GameState` in `project.godot` via `set_project_setting` —
never edit `project.godot` by hand, per CLAUDE.md.

Serialization is **explicit dictionaries of primitives**, written with
`var_to_str` / `str_to_var`, not `ResourceSaver` on the `Item` resources.
`Item` *is* a `Resource` and `ResourceSaver` would be less code, but a saved
`.tres` embeds the script path: moving or renaming `scripts/data/item.gd` a
year from now silently invalidates every player's save, and `load()`'s resource
cache makes a saved inventory alias live objects. An explicit `to_dict()` /
`from_dict()` pair is forty lines and immune to both.

```gdscript
extends Node
## [town] The profile save (§2.4). One file, rewritten whole - the profile is
## a few kilobytes and a partial-write scheme buys nothing at this size.
##
## `var_to_str` rather than JSON because StringName round-trips natively
## (&"warrior" survives as a StringName, not as "warrior"), and item.modifiers
## is an Array[Dictionary] whose keys are StringNames.

const PATH := "user://profile.save"
const VERSION := 1

func save_profile() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveGame: cannot write %s (%d)" % [PATH, FileAccess.get_open_error()])
		return
	f.store_string(var_to_str({
		"version": VERSION,
		"gold": GameState.gold,
		"scrap": GameState.scrap,
		"active_party": GameState.active_party,
		"street_sleep_used": GameState.street_sleep_used,
		"heroes": GameState.hero_runtime,
		"inventory": GameState.inventory.map(func(i: Item) -> Dictionary: return i.to_dict()),
		# "forge_stock" joins this dict with §7.4, NOT before - see below.
	}))

## Returns false when there is no save, or it is unreadable, or its version is
## from the future - every one of which means "start a new profile", not
## "crash". A corrupt save must never be a launch failure.
func load_profile() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = str_to_var(f.get_as_text())
	if not (data is Dictionary) or int((data as Dictionary).get("version", 0)) != VERSION:
		return false
	# ... assign back onto GameState, rebuilding Items via Item.from_dict() ...
	return true
```

**`Item.to_dict()` / `Item.from_dict()`** live on `item.gd` and cover exactly
the `@export`ed fields, `forge_count` (§10.4) among them. `modifiers` is copied
element-wise with `duplicate(true)` so a loaded item never aliases the
dictionary literals in `Itemizer.MODIFIERS`. The per-modifier `enhanced` flag
(§10.3) needs no special handling — the deep copy carries whatever keys a
modifier dictionary holds, so it round-trips the day §10.3 starts setting it.

**The dict grows with the step that introduces the field.** Two rules decide
whether a not-yet-real field may be declared early and serialized now, and they
pull in opposite directions on purpose (settled in step-2 Q1 / Q2):

- **`forge_count` is serialized from step 2**, even though nothing increments it
  until §7.3. Its zero value is *true*: this item has been forged zero times.
- **`forge_stock` is not serialized until §7.4.** Its empty value is not "the
  blacksmith's stock is empty", it is "there is no blacksmith" — a statement the
  save format has no business making. Serializing it early would encode a lie
  and invite §7.4 to wire the screen against a schema it never thought about.

The general form: **a field whose zero value is a true statement about the
profile may be declared early; a field whose zero value is meaningless may
not.** §2.2's inert step-1 fields all pass that test.

**`VERSION` policy.** Bump it when the *meaning* of an existing key changes;
do **not** bump it merely to add a new key. `load_profile()` reads every key
through `d.get(key, default)`, so a save written before a key existed loads
cleanly under a later build — which is exactly why `forge_stock` can join the
dict at §7.4 without a bump.

The case that *does* need one is `active_party`: before §4.5 it means "the
authored three-hero roster", after it means "the solo warrior". A save from
either side of that flip describes a party the other side does not support, and
`load_profile()` restores `heroes` verbatim without reconciling it against
`active_party` — so a stale save would resurrect a three-hero party that §4.5
had just retired. The build order happens to make this moot (nothing writes a
save until §3.1's `boot.tscn` at step 5, which lands *after* §4.5 at step 4), so
no bump is required in this pass. It is recorded because the shape recurs.

**When to save.** Every one of these, no exceptions:

- any profile mutation in town — buy, sell, forge, equip, unequip, rest,
  shop refresh;
- `start_expedition()`, and again when the expedition result is banked;
- `boot.tscn`, immediately after falling back to `GameState.new_profile()`
  because `load_profile()` returned `false` (§3.1);
- `NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_WM_CLOSE_REQUEST` in
  `SaveGame._notification()`.

That last line is the mobile-critical one. Android backgrounds the app without
warning and may never return; a save that only happens on a clean quit is a
save that never happens. `_notification()` is part of step 2, not a later
polish pass (step-2 Q5).

Note what is **not** on that list: `new_profile()` itself. See §2.3's
"`new_profile()` never persists" — the boot line above is the one place that
decision gets made, and it is deliberately the caller's job rather than the
function's.

---

## 3. Scene routing and the persistent HUD

### 3.1 `scripts/autoload/scene_router.gd`

```gdscript
extends Node
enum Place { TOWN, INN, BLACKSMITH, MAYOR, QUEST }

const PATHS := {
	Place.TOWN:       "res://scenes/town/town.tscn",
	Place.INN:        "res://scenes/town/inn.tscn",
	Place.BLACKSMITH: "res://scenes/town/blacksmith.tscn",
	Place.MAYOR:      "res://scenes/town/mayor_office.tscn",
	Place.QUEST:      "res://scenes/main.tscn",
}

var place: Place = Place.TOWN

## Fades through Hud's transition rect, swaps the scene, fades back. `await`able
## so a caller can present a modal only once the destination is actually up
## (§8.5's failure flow depends on that ordering).
func go(to: Place) -> void:
```

`res://scenes/main.tscn` stops being the project's main scene. A new
`res://scenes/boot.tscn` becomes it: it calls `SaveGame.load_profile()`, falls
back to `GameState.new_profile()` **followed by `SaveGame.save_profile()`**
(§2.3 — the fallback is persisted here, by the caller, and nowhere else), and
routes to `Place.TOWN`.

**`RunController._start_run()` must stop calling `GameState.reset_run()` in this
same step.** This is the single most destructive latent bug in the document and
it is invisible until the moment persistence starts working, so it is called out
here rather than left to be discovered.

`RunController._ready()` calls `_start_run()`, whose first line is
`GameState.reset_run()` — which is `new_profile()` (wipes gold, scrap and
inventory) followed by `start_expedition()` (which, per §2.4, **saves**). Once
`main.tscn` is a routed destination rather than the main scene, entering
`Place.QUEST` therefore wipes the profile `boot.tscn` just loaded *and writes
the wipe to disk*. The player loses everything the first time they accept a
quest, and the save file is already overwritten by the time anyone notices.

`new_profile()` not saving (§2.3) is what keeps this survivable up to step 5 —
before then the wipe is memory-only and a relaunch restores nothing because
nothing was ever stored. It is **not** a fix. The fix is that expedition start
belongs to the mayor's office (§7.5) and the router, not to `RunController`'s
`_ready()`:

- `_start_run()` drops the `reset_run()` call and assumes `GameState.level` is
  already built — which it is, because §7.5 calls `start_expedition(quest)`
  *before* routing to `Place.QUEST`.
- `reset_run()` survives exactly as §13.3 requires, as endless mode's dev entry
  point and `test_endless_level_gen.gd`'s. It is from that step on a **dev path
  that wipes the profile**, which is also precisely what §13.4's `wipe` verb
  wants.

Both new autoloads must be inert when instantiated headless with no scene-tree
work pending — `test_autoload_safety.gd` covers this and must stay green.

### 3.2 `scenes/hud/hud.tscn` — autoload `Hud`

A `CanvasLayer` at layer 10, above every scene, holding:

- `InventoryButton` — top-left, backpack icon (§12.1);
- `CurrencyPlate` — gold and scrap, the shared readout (§3.3);
- `ModalLayer` — `PROCESS_MODE_ALWAYS`, hosting `InventoryModal`,
  `CompareFlyout` and `QuestResult`;
- `Transition` — a full-screen `ColorRect` for `SceneRouter.go()`.

This one node solves three separate problems at once: the inventory button
needing to exist in both town and forest scenes, the result modal needing to
present *over* a town scene it was never a child of, and scene transitions
needing something that outlives both scenes.

**`RunSummary` moves out of `main.tscn` into `Hud/ModalLayer`** and is renamed
`QuestResult` (§8.5). Its `retry_pressed` signal becomes `dismissed`;
`RunController` no longer owns it or wires it.

**Visibility.** `InventoryButton` and `CurrencyPlate` are visible in every
`Place`. During `Place.QUEST` the button is additionally **disabled while
`RunController.state == COMBAT`**.

The reason is `shop_modal`'s own precedent: an open modal sets
`get_tree().paused = true`. An inventory button that pauses combat is a free
"stop the fight and think about it" during a cooldown-driven battle, and worse,
a free heal-timing tool. Disabling it in `COMBAT` only — travel, loot and shop
stay open — keeps the button useful without making it an exploit. This is a
one-line policy and is called out here so a future reader knows it was a
choice, not an oversight.

### 3.3 `EventBus` additions

```gdscript
signal scrap_changed(new_total: int, delta: int)
signal item_equipped(item: Item, hero_class: StringName, slot: int)
signal item_forged(item: Item, new_rarity: int)
signal quest_started(quest: QuestDef)
signal quest_finished(victory: bool)
```

`CurrencyPlate` binds `gold_changed` and `scrap_changed` and is the **only**
new gold/scrap readout written for this pass. `status_panel.gd`'s existing
`GoldPlate` stays as it is — the console is the *expedition's* readout and the
HUD is the *profile's*, and during a quest they show the same number because
banked gold goes straight onto the profile (§8.4). Do not build a second scrap
label inside `status_panel`; the HUD plate is already on screen there.

---

## 4. Equipment: three slots

### 4.1 `scripts/data/item.gd` — the slot

```gdscript
## [town] Which of the hero's three equipment slots this item occupies.
## DERIVED from the item's type via Itemizer.ITEM_TYPES, for the same reason
## usable_by() derives its classes from the same table (drops §2.2): a second
## copy of the mapping is a second thing to drift.
enum Slot { WEAPON, ARMOR, TRINKET }

func slot() -> Slot:
	var entry: Dictionary = Itemizer.ITEM_TYPES.get(weapon_type, {})
	return entry.get("slot", Slot.WEAPON) as Slot
```

`Item.Kind` is **left alone**. It already reads `WEAPON, POTION, RELIC` and is
used by `item_glyph.gd`; slot is a separate axis and overloading `Kind` to
carry it would break the glyph's kind-based fallback drawing.

**Every generated item keeps `kind = Item.Kind.WEAPON` — armor and trinkets
included** (step-4 Q7). `_generate_typed()` sets it unconditionally and that does
not change, because three separate derivations read it: `usable_by()`
early-returns empty unless `kind == Kind.WEAPON`, so a helm marked `RELIC` would
render as "Anyone", never auto-equip and never be targeted by `generate_drop()`;
`type_name()`'s "Helm" comes off the same branch; and `shop_sell_row.gd` /
`shop_buy_card.gd` feed `kind` to the glyph. So until `POTION` / `RELIC`
generation exists, `kind` effectively means "was generated" and `slot()` carries
all the real classification. Recorded as a known wart rather than silently left,
so the next reader does not "fix" it into three broken derivations — §15 defers
the per-slot behaviour that would make `kind` earn its keep.

`weapon_type` keeps its name even though it now names armor and trinkets too.
Renaming it touches `item_glyph.gd`, `shop_sell_row.gd`, `shop_buy_card.gd`,
`compare_flyout.gd`, `debug.gd` and two tests, for zero behavioural gain. A
comment on the field is enough:

```gdscript
## The item's type id, keying Itemizer.ITEM_TYPES. Named `weapon_type` for
## history; since [town] it also names armor and trinket types. The table it
## keys is what decides which slot the item fills (slot()).
```

### 4.2 `scripts/autoload/itemizer.gd` — one table

`WEAPON_TYPES` is renamed `ITEM_TYPES` and every entry gains a `slot`. The five
existing weapon entries are otherwise **unchanged, including their
`base_value`s** — moving those moves `test_economy.gd`'s affordability gate.

```gdscript
const ITEM_TYPES := {
	# --- weapons (unchanged from WEAPON_TYPES) ---
	&"axe":    { "slot": Item.Slot.WEAPON, "base_value": 20, "classes": [&"warrior"], "nouns": ["Axe", "Hatchet", "Cleaver", "Chopper"] },
	&"sword":  { "slot": Item.Slot.WEAPON, "base_value": 22, "classes": [&"warrior"], "nouns": ["Sword", "Blade", "Saber", "Longsword"] },
	&"bow":    { "slot": Item.Slot.WEAPON, "base_value": 20, "classes": [&"ranger"],  "nouns": ["Bow", "Longbow", "Shortbow", "Recurve"] },
	&"dagger": { "slot": Item.Slot.WEAPON, "base_value": 18, "classes": [&"ranger"],  "nouns": ["Dagger", "Knife", "Dirk", "Shiv"] },
	&"staff":  { "slot": Item.Slot.WEAPON, "base_value": 25, "classes": [&"mage"],    "nouns": ["Staff", "Rod", "Cane", "Scepter"] },
	# --- armor [town] ---
	&"helm":   { "slot": Item.Slot.ARMOR,  "base_value": 18, "classes": [&"warrior"], "nouns": ["Helm", "Casque", "Barbute", "Coif"] },
	&"mail":   { "slot": Item.Slot.ARMOR,  "base_value": 24, "classes": [&"warrior"], "nouns": ["Mail", "Hauberk", "Cuirass", "Plate"] },
	&"shield": { "slot": Item.Slot.ARMOR,  "base_value": 22, "classes": [&"warrior"], "nouns": ["Shield", "Buckler", "Targe", "Kite"] },
	# --- trinkets [town] ---
	&"ring":   { "slot": Item.Slot.TRINKET, "base_value": 19, "classes": [&"warrior"], "nouns": ["Ring", "Band", "Signet", "Loop"] },
	&"amulet": { "slot": Item.Slot.TRINKET, "base_value": 21, "classes": [&"warrior"], "nouns": ["Amulet", "Pendant", "Charm", "Talisman"] },
	&"idol":   { "slot": Item.Slot.TRINKET, "base_value": 23, "classes": [&"warrior"], "nouns": ["Idol", "Fetish", "Totem", "Effigy"] },
}
```

Two things about the new entries, both deliberate:

**Every `base_value` is inside the existing 18–25 band.** `test_economy.gd`
asserts a ≥95% affordability rate and a 100% teaser rate against the mean gold
a player holds at the encounter-3 shop. Those rates are functions of item
value; keeping every new type inside the band the five weapons already span
means the mean barely moves and both gates hold without touching the test.

**Armor and trinkets list `classes: [&"warrior"]`, not `[]`.** An empty
`classes` array would make `usable_by()` return empty, which `class_label()`
already renders as "Anyone" — tempting, and wrong for now. Empty also makes
`Itemizer.weapon_types_for()` skip the type, so trinkets would never be
targeted by `generate_drop()`, and `_maybe_auto_equip()` (which iterates
`usable_by()`) would never auto-equip one. Listing the warrior explicitly keeps
every existing derivation working untouched. When the mage and ranger return,
they get their own armor and trinket types in this same table, and the "Anyone"
path is there if a truly universal item is ever wanted.

**No deprecated alias: `WEAPON_TYPES` is renamed in one commit** (step-4 Q1).
The live references are one production file (`itemizer.gd` — the `const` plus six
internal reads in `generate_item_with_rarity()`, `_generate_typed()` and
`weapon_types_for()`), one helper (`item.gd`'s `usable_by()`), and one test block
(`test_drops.gd` D7, which §13.2 rewrites this step anyway). No scene file or
`.tres` references it. An alias that "must not survive the branch" is a second
cleanup commit to remember on a rename this small, and the compiler finds every
miss.

### 4.3 `GameState` — the equip API takes a slot

Today `equipped_item(hero_class)` returns the first inventory item that hero has
equipped. With three slots that is a bug in every call site, including
`compare_flyout.show_for()` (§1.8).

```gdscript
## The item in `hero_class`'s `slot`, or null. `equipped_by` still records only
## the hero, not the slot - the slot is recoverable from the item's own type
## (Item.slot()), so one item can never be ambiguous about which slot it fills.
## That is why this change needs no new field on Item.
func equipped_item(hero_class: StringName, slot: Item.Slot) -> Item:
	for i: Item in inventory:
		if i.equipped_by == hero_class and i.slot() == slot:
			return i
	return null

## Every item `hero_class` currently wears, in Slot order. What the forge and
## the inventory modal's Equipped section both list.
func equipped_set(hero_class: StringName) -> Array[Item]:
```

`equip_item(item, hero_class)` replaces only the occupant of `item.slot()`.
`_maybe_auto_equip(item)` fills that slot only when it is empty. Neither
signature changes; both bodies gain the slot lookup.

**Every caller of the old one-arg `equipped_item()` must be updated.**
`grep -rn "equipped_item" scripts/` before declaring this done. It returns
exactly four, and three of them are mechanical (step-4 Q6):

| site | fix |
|---|---|
| `compare_flyout.gd:58` | `GameState.equipped_item(hero_class, item.slot())` — §6.3 gives it verbatim |
| `game_state.gd:191` (`equip_item`) | `var previous := equipped_item(hero_class, item.slot())` |
| `game_state.gd:209` (`_maybe_auto_equip`) | `if equipped_item(hero_class, item.slot()) == null:` |
| `debug.gd:392` (`state`) | no longer retargetable — with three slots "the hero's equipped item" is not a thing |

`debug.gd`'s `state` line iterates `equipped_set()` instead, one bracketed list
per hero:

```gdscript
equip_bits.append("%s=[%s]" % [c, ", ".join(equipped_set(c).map(
    func(i: Item) -> String: return i.display_name))])
```

so a fully-kitted warrior reads `warrior=[Rusty Axe, Fat Helm, Lucky Ring]` and an
empty-handed one reads `warrior=[]`. Showing only the WEAPON slot would keep the
line shorter but would hide exactly the state a forge tester is checking. That
loop (and the `drops` loop above it) reads `GameState.active_party` rather than
`Itemizer.droppable_classes()`; the two are equal under a solo warrior, but the
`state` line is about who is on the field.

### 4.4 Generation rolls the slot first

`generate_item_with_rarity()` currently draws `weapon_type` uniformly from the
type table. With eleven types split 5/3/3 across slots, a uniform draw means
45% weapons, 27% armor, 27% trinkets — and adding a twelfth type silently
reweights it again.

Roll the **slot** first, then the type within it. This is the same reasoning
drops §0.3 gave for rolling the class before the weapon: the number of types a
slot happens to have must not decide how often that slot is served.

**Roll over the slots that are actually fillable, not over all three** (step-4
Q4). An earlier draft of this section gave two formulations — a uniform-over-3
roll with a WEAPON fallback for `generate_item_with_rarity()`, and "class first,
then slot" prose for `generate_drop()`. For a solo warrior they are identical
and the fallback is dead code; they diverge the moment `generate_drop(&"mage")`
is called, which `test_drops.gd` D1 does 1000 times. A uniform-over-3 roll lands
on ARMOR or TRINKET two thirds of the time for a class that has no armor or
trinket type, and the party-wide WEAPON fallback is, for a single-class call,
just "give up on slots". One helper filtering to non-empty slots collapses both
paths onto the stricter behaviour, and makes "a drop is always wieldable" true by
construction rather than by a fallback:

```gdscript
## The slots at least one member of `classes` can fill. Rolling over THIS rather
## than over all three is what lets one helper serve both generators: a
## party-wide call gets [WEAPON, ARMOR, TRINKET], a single-class call for the
## mage gets [WEAPON] and can never land on a slot that class has no type for.
func _equippable_slots_for(classes: Array[StringName]) -> Array[Item.Slot]

## The types in `slot` wieldable by some class in `classes`. Built on
## weapon_types_for(), which stays as the "all types for a class, any slot"
## accessor droppable_classes() reads.
func types_for_slot(slot: Item.Slot, classes: Array[StringName]) -> Array[StringName]

## Slot first, then type within it - the shared body of both generators.
func _roll_typed(classes: Array[StringName], rarity_index: int) -> Item:
	var slots := _equippable_slots_for(classes)
	if slots.is_empty():
		# Unreachable while some class can wield something, but a generated item is
		# better than a crash - the guard generate_drop() already carried.
		var all: Array = ITEM_TYPES.keys()
		return _generate_typed(all[RNG.randi_range(0, all.size() - 1)], rarity_index)
	var slot: Item.Slot = slots[RNG.randi_range(0, slots.size() - 1)]
	var types := types_for_slot(slot, classes)
	return _generate_typed(types[RNG.randi_range(0, types.size() - 1)], rarity_index)

func generate_item_with_rarity(rarity_index: int) -> Item:
	rarity_index = clampi(rarity_index, 0, Item.Rarity.RARE)   # never ENHANCED (§10.1)
	return _roll_typed(GameState.active_party, rarity_index)

func generate_drop(hero_class: StringName, rarity_floor: int = 0) -> Item:
	var rarity: int = maxi(RNG.weighted_index(RARITY_WEIGHTS),
		clampi(rarity_floor, 0, Item.Rarity.RARE))
	return _roll_typed([hero_class] as Array[StringName], rarity)
```

`generate_item_with_rarity()` passes the **active party**, so with a solo warrior
staves and bows stop appearing in chests and shop stock entirely and every item
the player sees is an item they can wear — this is the §1.6 fix. The mage's staff
comes back the day the mage does, with no further edit.

`generate_drop(hero_class, rarity_floor)` (drops §4) still picks the class first
— its rarity roll and floor are untouched — and now picks the slot second, from
*that class's* fillable slots. Its guarantee is unchanged and now unconditional:
a drop is always something the target class can wield.

The helper names §4.1–§4.4 use are canonical; the full set this step adds
(step-4 Q5):

| name | file | signature |
|---|---|---|
| `Item.Slot` | `item.gd` | `enum { WEAPON, ARMOR, TRINKET }` |
| `Item.slot()` | `item.gd` | `-> Slot` — reads `Itemizer.ITEM_TYPES[weapon_type]["slot"]`, default `WEAPON` |
| `Itemizer.types_for_slot()` | `itemizer.gd` | `(Item.Slot, Array[StringName]) -> Array[StringName]` |
| `Itemizer._equippable_slots_for()` | `itemizer.gd` | `(Array[StringName]) -> Array[Item.Slot]` |
| `Itemizer._roll_typed()` | `itemizer.gd` | `(Array[StringName], int) -> Item` |
| `GameState.equipped_item()` | `game_state.gd` | `(StringName, Item.Slot) -> Item` |
| `GameState.equipped_set()` | `game_state.gd` | `(StringName) -> Array[Item]` — Slot order, gaps omitted |

`_random_equippable_slot()`, named in an earlier draft of this section, does not
exist: `_equippable_slots_for()` replaces it. `weapon_types_for(hero_class)`
(drops §2.2) is unchanged and stays the "all types for a class, any slot"
accessor the other two are built on.

### 4.5 `active_party` replaces `PARTY_ORDER` at three call sites

`PARTY_ORDER` stays exactly as it is — it is the canonical roster the
drop-coverage weighting is written against, and restoring a three-hero party is
one assignment.

**The edit that actually makes the party solo is the value flip**, and it is
easy to miss because it is not a call site: `active_party`'s initialiser and
`new_profile()`'s matching assignment both change from `PARTY_ORDER` to
`[&"warrior"]`. Switching only the reads below changes *nothing* — every one of
them would be reading a variable that still equals `PARTY_ORDER`. Do the flip
and the reads in the same commit.

Three functions read `active_party` instead of `PARTY_ORDER`:

- `Itemizer.droppable_classes()` — otherwise drops keep targeting a mage who is
  not on the field and generating staves nobody can hold;
- `GameState._reset_hero_runtime()` — who actually spawns. **Already done in
  step 1**: §2.3 words the helper against `active_party`, and while the field
  still equals `PARTY_ORDER` that read is a provable no-op, so step 1 wrote it
  the way §2.3 specifies rather than shipping a body that contradicts its own
  section. Nothing to change here;
- `BattleDirector.spawn_party()` — reads `hero_runtime`, so this follows for
  free.

Moving one read early decouples nothing, because the coupling this list guards
against — drops aimed at a hero who is not on the field — is created by the
*value* changing, not by which name each site reads.

`test_drops.gd:23`'s assertion changes from `== GameState.PARTY_ORDER` to
`== GameState.active_party`, and `test_profile_expedition.gd`'s
"active_party still equals PARTY_ORDER" check (§13.1) is updated here too —
deliberately, which is the point of it existing. Everything else in
`test_profile_expedition.gd` is party-size agnostic and stays.

**`droppable_classes()` is read transitively by `next_drop_class()`, so two more
`test_drops.gd` blocks move with it** (step-4 Q11) — this is the one consequence
of the value flip that is not visible from a `grep` for `active_party`:

- **D4** asserts each of `PARTY_ORDER`'s three classes takes 33.3% ± 2pp of 3000
  `next_drop_class()` draws. With one droppable class the warrior takes 100% and
  the other two take 0% — three failing checks.
- **D9** requires ≥ 95% of ≥ 3-drop levels to have given *all three* classes a
  drop. With one droppable class that rate is 0% — one failing check.

Both test `DROP_CATCHUP` and `next_drop_class()`, which §15 explicitly keeps
alive for the party's return ("untouched and waiting for them — do not delete
it"). Re-pointing their loops at `active_party` would leave them passing and
**tautological** — "the only droppable class got 100% of the drops" asserts
nothing about the weighting, and a rewrite of `next_drop_class()` would sail
through. So instead each block **saves `active_party`, sets it to
`PARTY_ORDER.duplicate()` for its own duration, and restores it**, keeping the
coverage algorithm under a real three-class test while the field it reads is
solo. D8 and `_report_party_bonuses()` already save and restore
`endless_level_number` / `inventory` / `drops_by_class` the same way, so this is
the file's existing idiom rather than a new one. Their `PARTY_ORDER` loops become
`Itemizer.droppable_classes()` loops so they follow the override rather than
restating the roster.

`party_bars.gd` already handles a short party ("A party smaller than the
authored roster leaves spare bars"), and `world.hero_slot_position()` already
range-checks. No layout work is needed for a solo party.

**Known consequence, accepted:** the slot machine's 2-of-a-kind heal ("lowest
HP hero") and 3-of-a-kind heal ("whole party") become the same payout with one
hero. `SLOT_HEAL_3_FRACTION` is larger than `SLOT_HEAL_2_FRACTION`, so the
three-of-a-kind still pays more — the payout stays distinguishable, it just
stops being *wider*. Do not restructure the slot to compensate; §0.2 puts the
reels out of scope.

---

## 5. Scrap

### 5.1 What it is

The forge's currency. It has exactly one faucet — enemies drop it (§9) — and
exactly one sink — forging (§7.3). It is never bought, never sold, and never
convertible to gold in either direction (§10.5). Two currencies with disjoint
uses is the whole point: gold buys *breadth* (new items, shop refreshes, inn
stays), scrap buys *depth* (making the item you already like better).

### 5.2 Why three slots matter to it

With one equipped item, a full forge from Common to Enhanced costs 63 scrap
(§11) and the player is done with scrap forever after roughly one and a half
quests. With three slots it is 189 scrap for a full set, and every upgrade to a
*base* item resets that slot's ladder. That is a sink that lasts as long as gear
churn does, which is the only reason scrap is worth adding as a currency at all.

### 5.3 Display

`Hud/CurrencyPlate` shows gold and scrap side by side, using the same
`OrnateFrame` treatment `status_panel`'s `GoldPlate` uses, and the same
pop-and-float feedback on change (`status_panel._float_delta()` is the
reference implementation; lift it into a shared helper rather than copying it a
third time).

### 5.4 Not to be confused with `Upgrades`

`scripts/autoload/upgrades.gd` is the **slot machine's** three run-scoped
upgrades (Quick Reels, Overcharge, Fat Purse), bought with gold in the console
tray, reset at the start of every expedition. It is unrelated to the forge, and
`run_stats["upgrades_bought"]` continues to count only those.

The forge gets its own stat key, `run_stats["items_forged"]`, and its own
signal (`EventBus.item_forged`). Naming the forge "upgrade" anywhere in code
will cost somebody an hour; call it **forge** throughout.

---

## 6. The inventory modal

### 6.1 What it is

`scenes/modals/inventory_modal.tscn`, living in `Hud/ModalLayer`. Opened by the
HUD's backpack button, available in town and in the forest (§3.2's combat
caveat).

Layout, top to bottom:

- header: title, gold + scrap readout, close X (the red X remains the only
  required close path, §15.4);
- **Equipped** — three rows, one per slot, in `Slot` order, each either an item
  row or an empty-slot placeholder naming the slot;
- **Carried** — every unequipped inventory item.

`BonusStrip` is instanced under the header, exactly as `shop_modal.tscn`
authors it: seeing what the party actually gains is what makes equipping a
decision rather than a chore.

### 6.2 `inventory_row.tscn` is a new scene, not a modified sell row

`shop_sell_row.tscn`'s entire layout hangs off a **full-width primary `SellBar`**
with Equip as a small secondary button and Compare hidden behind
`swipeable_face`'s reveal gesture. Deleting the Sell bar leaves a card built
around a hole, and the original plan's "Compare and Equip side by side under the
details" is a different composition, not a button toggle.

So: a new `inventory_row.tscn` and `scripts/modals/inventory_row.gd`, which
**reuses** `swipeable_face`, `item_glyph` and the rarity-tinted panel stylebox
from `shop_sell_row.gd` verbatim. Lift that `setup()` styling block into a
shared `item_card_style.gd` static helper rather than copy-pasting it a third
time — `shop_buy_card.gd` already carries a second copy.

The row's action area is two equal-width buttons side by side:

| button | behaviour |
|---|---|
| **Compare** | emits `compare_requested(item)`; the modal forwards to `CompareFlyout.show_for(item)`. |
| **Equip** / **Unequip** | toggles via `GameState.equip_item()` / `unequip_item()`, then emits `equip_changed`. |

`Equip` is hidden when `item.usable_by()` is non-empty and excludes every member
of `active_party` — an item nobody on the field can wear says so by having no
Equip button, rather than by having a button that silently fails.

`equip_changed` rebuilds **both** sections, for the reason `shop_modal` already
documents: equipping may have displaced a different row's item.

### 6.3 `CompareFlyout` needs the slot

```gdscript
# was: GameState.equipped_item(hero_class)
var equipped: Item = GameState.equipped_item(hero_class, item.slot()) if hero_class != &"" else null
```

That single line is §1.8's fix. Nothing else in `compare_flyout.gd` changes —
including `_fill_changes()`, which iterates `Itemizer.MODIFIERS` by id and
therefore handles Enhanced modifiers correctly with no edit at all, because
§10.3 gives them the same ids.

### 6.4 Selling

The inventory modal has **no sell action**. Selling stays in the shop, where a
merchant is standing. This is the original plan's rule and it is the right one:
an always-available sell button in a modal reachable mid-expedition is an
always-available gold faucet.

---

## 7. Town

Four scenes under `scenes/town/`. `town.tscn` exists as a mockup with a
`town_overview.png` background and two dead buttons; `tavern.tscn` exists with
`inn-bg.png` and authored fire/dust particles and is renamed `inn.tscn`.

### 7.1 `town.tscn` — the hub

Keeps `TownOverview` and its current framing. The two existing buttons are
rewired and a third is added:

| button | destination |
|---|---|
| `InnButton` (was `TavernButton`) | `SceneRouter.Place.INN` |
| `BlacksmithButton` | `SceneRouter.Place.BLACKSMITH` |
| `MayorButton` (new) | `SceneRouter.Place.MAYOR` |

Button positions and sizes are authored in the scene, per CLAUDE.md's "prefer
inspector properties over code". `scripts/town/town.gd` does nothing but connect
three `pressed` signals to `SceneRouter.go()`.

Every interior scene carries a **Back** button routing to `Place.TOWN`, and
`_unhandled_input` maps `ui_cancel` (and therefore Android's back gesture) to
the same call.

### 7.2 `inn.tscn` — the inn

The existing tavern scene, fleshed out, with two actions:

| action | cost | effect |
|---|---|---|
| **Rest for the night** | `INN_REST_COST_PER_HERO` × `active_party.size()` (50 with a solo warrior) | every hero to full HP |
| **Sit by the fire** | free | no heal; a flavour beat only |

"Sit by the fire" exists because the original plan listed both "sit and rest for
the evening to heal" and "rest for the night for 50 gold", which read as two
paid heals. One paid heal is the mechanic; the free option must not heal, or the
paid one has no reason to exist.

The Rest button is disabled and shows the price greyed when the player cannot
afford it, using `upgrade_button.gd`'s existing affordability pattern
(re-evaluate on `gold_changed`) rather than a new one.

Resting saves the profile (§2.4).

### 7.3 `blacksmith.tscn` — the forge

New scene. Needs a static background of a medieval blacksmith (§12.1).

Two tabs, mirroring the shop's `TabContainer`: **Forge** and **Buy**.

**The Forge tab lists `GameState.equipped_set(&"warrior")`** — the three
equipped items and nothing else. Unequipped inventory is deliberately absent:
forging is for the gear you have committed to, and a list of everything you are
carrying is the inventory modal's job.

Each row shows the item card (§6.2's shared style), its current rarity, and one
button:

```
FORGE  →  Magic          [ 18 scrap   70 gold ]
```

- disabled, with the reason shown, when the player cannot afford it;
- replaced by a static **"Fully forged"** plate at `ENHANCED`;
- on press: `Itemizer.forge(item)` (§10.2), then `SaveGame.save_profile()`,
  then a rebuild of the row with a rarity-coloured flash on the new modifier
  line.

An empty slot shows a placeholder row naming the slot, not a missing row —
"you have nothing in your trinket slot" is information the forge screen should
volunteer.

### 7.4 The blacksmith's expanded shop

Six items, in three tiers of two, refreshable for `SHOP_REFRESH_COST` gold.

**This is a new generator function, not a parameter on `generate_shop_stock()`.**
`test_economy.gd:106` asserts `generate_shop_stock()` always returns
`SHOP_ITEMS_FOR_SALE` items, and lines 94–97 gate its affordability and teaser
rates. Adding a count parameter with a default would keep that green today and
break it the first time somebody changed the default.

```gdscript
## [town] The blacksmith's six-card stock: two cheap, two average, two dear.
## Same bucket technique as generate_shop_stock() (§13.6) at twice the width -
## a separate function rather than a parameter on that one, because
## test_economy.gd pins its shape and this stock has different guarantees.
func generate_forge_stock() -> Array[Item]:
	var stock: Array[Item] = []
	for bucket: Array in [
		[Item.Rarity.COMMON,   Item.Rarity.UNCOMMON],   # cheap
		[Item.Rarity.UNCOMMON, Item.Rarity.MAGIC],      # average
		[Item.Rarity.MAGIC,    Item.Rarity.RARE],       # dear
	]:
		stock.append(_generate_in_bucket(bucket))
		stock.append(_generate_in_bucket(bucket))
	stock.shuffle()
	return stock
```

`ENHANCED` never appears in shop stock; it is forge-only (§10.1).

**Stock lifetime.** Generated once and cached on the profile
(`GameState.forge_stock: Array[Item]`), saved with it, and rerolled **only** by
the refresh button. Walking out of the blacksmith and back in must not reroll —
that is the same rule the quest shop already follows via
`EncounterDef.cached_shop_items` (§21-D11), and breaking it turns leaving the
screen into a free refresh.

**The refresh button** uses standard circular-arrow iconography, sits in the tab
header, and is disabled when `gold < SHOP_REFRESH_COST` — same affordability
pattern as everything else on this screen. On press: spend, regenerate, rebuild
the cards with their existing staggered `play_entrance()`, save.

### 7.5 `mayor_office.tscn` — quests

New scene. Needs a static background of a village mayor's office (§12.1).

Three buttons, one per `QuestDef` in `res://resources/quests/`, each showing
name, blurb, encounter count, and gold reward. Pressing one calls
`GameState.start_expedition(quest)` and routes to `Place.QUEST`.

A quest is **always available**; there is no cooldown, no lockout, and no
prerequisite. Difficulty is the gate.

---

## 8. Quests

### 8.1 `scripts/data/quest_def.gd`

```gdscript
class_name QuestDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var blurb: String = ""
## The encounter sequence, as EncounterDef.Type values. Authored in the
## inspector rather than built in code so the pacing of a tier can be retuned
## without touching a script (CLAUDE.md, "prefer inspector properties").
@export var encounter_types: Array[int] = []
@export var gold_reward: int = 0
## Difficulty, expressed as data rather than as a multiplier: which enemies
## show up and how many. There is deliberately no stat-scaling factor here -
## GameState._build_endless_level()'s own comment gives the reason (a second
## source of truth for combatant power alongside CombatantStats).
@export var enemy_pool: Array[StringName] = []
@export var enemy_count: Vector2i = Vector2i(2, 2)
@export var boss_pool: Array[StringName] = []
@export_range(0, 4, 1) var boss_drop_rarity_floor: int = 0
@export var travel_durations: Array[float] = []
```

### 8.2 The three quests

`res://resources/quests/easy.tres`, `medium.tres`, `hard.tres`. Sequences are
exactly as the original plan specified; the difficulty columns are this
document's addition, and are the fix for §1.10.

| | easy | medium | hard |
|---|---|---|---|
| encounters | 5 | 7 | 9 |
| sequence | C, L, C, S, **B** | C, C, L, C, C, S, **B** | C, L, C, C, C, L, S, C, **B** |
| combats (incl. boss) | 3 | 5 | 6 |
| `enemy_pool` | `ENDLESS_EARLY_POOL` | early + mid | `ENDLESS_MID_POOL` |
| `enemy_count` | 2–2 | 2–3 | 3–3 |
| `boss_drop_rarity_floor` | 1 (Uncommon) | 2 (Magic) | 3 (Rare) |
| `gold_reward` | 200 | 400 | 600 |

(C = COMBAT, L = LOOT, S = SHOP, B = boss COMBAT.)

The rarity floor is what gives hard a reason to exist beyond gold: a guaranteed
Rare base item is the only cheap way to reach an Enhanced Rare, since forging a
Common all the way costs 63 scrap and 250 gold.

### 8.3 `GameState.build_level()` dispatches on the quest

```gdscript
func build_level() -> LevelDef:
	if quest != null:
		return _build_quest_level(quest)
	if endless_mode:
		return _build_endless_level(endless_level_number)
	return _build_whispering_wood_level()
```

`_build_quest_level()` walks `quest.encounter_types`, filling COMBAT encounters
from `quest.enemy_pool` at `quest.enemy_count`, LOOT from
`Tuning.LOOT_ITEMS_PER_CHEST`, SHOP from `Tuning.SHOP_ITEMS_FOR_SALE`, and
marking the last encounter `is_boss` with its enemy list **led** by a
`quest.boss_pool` pick — leading the list matters, because §7.3 puts the first
enemy at the leftmost slot so the scaled-up boss body stays in frame.

`endless_mode` and both existing builders stay, untouched, as the dev path.

`RunController._next_encounter()`'s endless wraparound gains a quest branch:
when `GameState.quest != null` and the encounters run out, call
`_run_complete()` instead of generating another level. **`_run_complete()`
becomes reachable for the first time** — it is currently dead code, because
`endless_mode` defaults to true.

### 8.4 Banking

Gold and scrap picked up in the forest go onto the **profile immediately**
(`GameState.add_gold` / `add_scrap`), and are *also* accumulated into
`expedition_gold` / `expedition_scrap` for the result modal's readout. Items go
into `inventory` immediately, as they do today.

Immediate crediting rather than end-of-quest settlement is what lets the quest's
mid-run shop encounter work at all: a shop you cannot spend today's winnings in
is a shop that only sells you what you walked in with.

### 8.5 Victory and failure

**Victory** — `_run_complete()`:

1. `GameState.add_gold(quest.gold_reward)`.
2. `GameState.quest = null`; `EventBus.quest_finished.emit(true)`;
   `SaveGame.save_profile()`.
3. `await SceneRouter.go(Place.MAYOR)`.
4. `Hud.quest_result.present(true)` — the stats list gains a **Quest Reward**
   row showing `gold_reward`, plus rows for expedition gold and scrap. Button
   text is **"Retire for the evening"**.
5. On dismiss: `SceneRouter.go(Place.INN)`.

**Failure** — `_game_over()`:

1. Hold on the battlefield 1.0s (existing behaviour, §18.1).
2. **Keep** profile gold and scrap, including everything banked this
   expedition. **Discard** every inventory item acquired during the expedition
   that is not equipped. Equipped gear survives.
3. `GameState.quest = null`; `EventBus.quest_finished.emit(false)`;
   `SaveGame.save_profile()`.
4. `await SceneRouter.go(Place.INN)`.
5. `Hud.quest_result.present(false)` with **two** recovery buttons instead of
   one dismiss:
   - **Rest at the Inn — 50g** → full heal, spend gold, dismiss. Disabled when
     unaffordable.
   - **Sleep in the street — free** → heal
     `ceili((max_hp - hp) * INN_STREET_HEAL_FRACTION)`, set
     `street_sleep_used = true`, dismiss. **Disabled when `street_sleep_used`
     is already true.**

That flag is §1.9's fix. `street_sleep_used` is cleared by
`start_expedition()`, so the free half-heal is once per expedition, not once
per press.

**Tracking which items are expedition loot.** Rather than a timestamp or a flag
on `Item`, `start_expedition()` snapshots the inventory size
(`_expedition_inventory_mark`) and, on failure, unequipped items at indices ≥
that mark are discarded. Items bought at the quest's shop encounter are included
in that discard, which is correct — they were bought with expedition gold and
never made it home.

**Observation, not a change:** the mayor's office becomes a room the player only
ever passes through, since the victory button sends them to the inn and the
failure flow starts there. That is what the original plan specified and it reads
fine as a narrative beat — collect your pay, then go to bed. If it ever feels
like a dead end, routing "Retire for the evening" to `Place.TOWN` instead makes
the town the single return point; it is a one-enum-value change.

---

## 9. Combat loot: gold and scrap pickups

### 9.1 When

**At the moment of death, concurrently with the corpse hold** — not after the
fade. `Combatant` already signals `EventBus.combatant_died(c)`, and
`ENEMY_DEATH_HOLD_RUSH + ENEMY_DEATH_FADE_RUSH` is 0.75s in which nothing else
is happening. The whole pickup animation (arc + settle + fade, 0.90s per §11)
fits inside that plus the front of `ENCOUNTER_RESOLVE_PAUSE` and costs the
encounter **zero additional seconds**.

This is §1.11's fix and it is not optional. The original "after the model is
done fading" ordering added roughly two seconds to every combat encounter in the
game.

### 9.2 How — tweens, not physics

Each pickup is a `MeshInstance3D` following a **computed ballistic arc**: a
`tween_method` driving position along a parabola from the corpse's
`hit_world_position()` to a landing point at a random offset within
`LOOT_SCATTER_RADIUS`, with an independent spin on the mesh.

No `RigidBody3D`, no collision shapes, no physics ticks. Up to three enemies can
die within a frame of each other; at up to five objects per currency that is
thirty bodies settling on the most expensive screen in the game —
`main_layout.gd`'s own comment on `set_world_rendering()` documents how tight
that budget already is. A tweened arc is deterministic, cheaper, easier to make
read well, and visually indistinguishable at the size and duration these appear.

### 9.3 How many

```gdscript
const ENEMY_GOLD_DROP := Vector2i(3, 9)     # value, not object count
const ENEMY_SCRAP_DROP := Vector2i(2, 6)
const BOSS_LOOT_MULT := 3
const LOOT_PICKUP_MAX_OBJECTS := 5
```

**Object count is decoupled from value.** The original 0–9 made the number of
objects *be* the reward, which caps how much a boss can pay at whatever the
frame budget allows, and gives a 1-in-100 chance of a kill that drops literally
nothing from either currency. Instead: roll the value in the range above, then
spawn `mini(value, LOOT_PICKUP_MAX_OBJECTS)` objects to represent it. A boss
paying 27 gold spawns five coins, same as a grunt paying five — the *number* is
flavour, the *counter* is the reward.

The floors (3 and 2, not 0) mean every kill pays something. A kill that pays
nothing reads as a bug.

### 9.4 Where it goes

At the end of the settle, each object fades and the corresponding
`GameState.add_gold()` / `add_scrap()` fires, which the HUD's `CurrencyPlate`
already animates via `gold_changed` / `scrap_changed`.

*Optional polish, explicitly outside the required scope:* on fade, spawn a 2D
sprite at the object's `unproject_position()` and tween it to the currency
plate. `overlay.spawn_world_label()` already does the 3D→2D conversion this
needs. Nice, and skippable.

---

## 10. Rarity: Enhanced

### 10.1 The fifth rarity

```gdscript
enum Rarity { COMMON, UNCOMMON, MAGIC, RARE, ENHANCED }
```

**Five index-addressed arrays must grow in lockstep.** Missing one is an
out-of-bounds at runtime or, worse, silently correct-looking output:

| array | new entry | note |
|---|---|---|
| `Item.rarity_name()`'s inline array | `"Enhanced"` | |
| `Tuning.RARITY_COLORS` | `Color("FF6B4A")` | a forge-hot red-orange, distinct from Rare's `F2C230` gold and Magic's `4A9BE8` blue. Flows into `item_glyph`'s ring for free — it takes `ring_color` as an export set from `rarity_color()`. |
| `Itemizer.RARITY_WEIGHTS` | **`0`** | the important one. |
| `Itemizer.RARITY_MOD_COUNT` | `4` | |
| `Itemizer.RARITY_VALUE_MULT` | `[6.5, 8.0]` | never actually used — forging does not recompute value from this table (§10.5) — but the array must be the same length as the others or an index is wrong. |

**Weight 0 means Enhanced is forge-only and can never be rolled.**
`RNG.weighted_index()` is safe with a trailing zero: `roll` is
`randi_range(1, total)`, a zero-weight entry adds nothing to the accumulator, so
its index is unreachable. Verified against `rng.gd:35-47`. Nothing else is
needed to keep Enhanced out of chests and shops.

Also clamp `generate_item_with_rarity()`'s input to `Item.Rarity.RARE` rather
than the literal `3` it uses today, so the guard says what it means.

**There are three such guards, not one** (step-3 Q3). All three were already
safe with the literal — nothing moves — but a bare `3` sitting next to a
`RARITY_WEIGHTS` that now has a fifth entry makes a reader stop and work out
whether index 4 is reachable, and the enum name answers that inline:

- `Itemizer.generate_item_with_rarity()` — named above;
- `Itemizer.generate_drop()`'s `clampi(rarity_floor, 0, 3)` — same file, same
  meaning, and it sits directly under the `weighted_index(RARITY_WEIGHTS)` call;
- `Debug._parse_rarity()`'s `clampi(int(token), 0, 3)` — the guard that enforces
  "no debug verb mints an ENHANCED item" (§13.4), so writing it as the enum is
  what makes that rule visible at the site holding it.

`_parse_rarity()` deliberately gains **no** `"enhanced"` case: the token falls
through to the int parse (`int("enhanced")` is 0 → Common), and `item 4` clamps
to Rare. The harness route to an Enhanced item is §13.4's `forge` verb, which is
the only thing that should ever produce one.

### 10.2 The forge ladder

Four steps, one modifier each, walking the enum:

| from | to | scrap | gold | mods after |
|---|---|---|---|---|
| Common | Uncommon | 5 | 20 | 1 |
| Uncommon | Magic | 10 | 40 | 2 |
| Magic | Rare | 18 | 70 | 3 |
| Rare | **Enhanced** | 30 | 120 | 4 |

The "mods after" column is exactly `RARITY_MOD_COUNT`. **That is the point of
four steps rather than three**: a forged item and a found item of the same
rarity carry the same number of modifiers, so the rarity name never lies about
power, and `test_item_distribution.gd:68`'s invariant holds for forged items as
well as generated ones.

**That claim does not need `forge()` to test.** Each rung raises rarity by one
and adds one modifier, so it holds exactly when every adjacent pair of
`RARITY_MOD_COUNT` differs by one — a pure property of the array. §13.1's
`test_enhanced_rarity.gd` asserts it at **step 3**, six steps before this
function exists. That ordering is deliberate: §0.4 records the three-step ladder
being rejected for breaking this invariant, and if the replacement broke it too,
the fix at step 3 is a one-line array edit rather than a redesign discovered
underneath a finished blacksmith screen.

**`forge()` itself lands at step 9, not step 3** (step-3 Q1). Its body depends on
four things that do not exist until later: `GameState.spend_scrap` / `add_scrap`
(§2.2's API, which §14 step 1 explicitly deferred), `EventBus.item_forged`
(§3.3, step 5), `run_stats["items_forged"]` (§5.4), and §11's `FORGE_COSTS` /
`FORGE_ENHANCED_MULT`. Writing it at step 3 would mean either front-loading the
whole scrap currency API out of order, or deducting scrap inline with
`GameState.scrap -= n` — bypassing the `scrap_changed` contract §2.2 gives it,
to be rewritten six steps later. §10.2, §10.3, §11's forge constants and
`test_forge.gd` therefore all travel together to step 9, where `spend_scrap` is
born. §7.3's blacksmith at step 10 then calls a `forge()` that already exists and
is already tested.

```gdscript
## [town] Raises `item` one rarity step, adding one modifier. The ONLY way an
## item's rarity ever changes after generation.
##
## The new modifier is drawn from the same MODIFIERS pool, excluding ids the
## item already carries - _generate_typed()'s "never roll the same modifier
## twice on one item" rule has to survive forging, or a player ends up with two
## "+N Damage" lines that party_bonuses() happily sums.
func forge(item: Item) -> bool:
	if item == null or item.rarity >= Item.Rarity.ENHANCED:
		return false
	var cost: Array = Tuning.FORGE_COSTS[item.rarity]
	if GameState.scrap < int(cost[0]) or GameState.gold < int(cost[1]):
		return false
	var pool := _modifier_pool_excluding(item)
	if pool.is_empty():
		return false                       # unreachable: 8 modifiers, 4 slots
	if not GameState.spend_scrap(int(cost[0])):
		return false
	if not GameState.spend_gold(int(cost[1])):
		GameState.add_scrap(int(cost[0]))  # refund - never half-charge
		return false
	var enhanced: bool = item.rarity == Item.Rarity.RARE
	item.modifiers.append(_roll_modifier(pool, enhanced))
	item.rarity = (item.rarity + 1) as Item.Rarity
	item.forge_count += 1
	item.value += int(cost[1])             # §10.5
	GameState.run_stats["items_forged"] = int(GameState.run_stats["items_forged"]) + 1
	EventBus.item_forged.emit(item, item.rarity)
	return true
```

Note the refund branch. `spend_scrap` and `spend_gold` are two separate
transactions and the affordability check above them is not atomic with them; a
half-charged forge would be the worst possible bug in a screen that spends the
player's savings.

### 10.3 Enhanced modifiers are the same ids, doubled

This is the single most important simplification in the document.

The original plan called for "a new Enhanced pool which is the same as the
normal pool of modifiers but doubled in strength". Implement that as **the same
`MODIFIERS` table, with the roll doubled and an `enhanced: true` marker on the
resulting dictionary** — *not* as a second table with new ids.

```gdscript
func _roll_modifier(pool: Array, enhanced: bool) -> Dictionary:
	var def: Dictionary = pool[RNG.randi_range(0, pool.size() - 1)]
	var roll: int = RNG.randi_range(int(def["roll"][0]), int(def["roll"][1]))
	if enhanced:
		roll *= Tuning.FORGE_ENHANCED_MULT
	return {
		"id": def["id"],
		"label": (def["label"] as String) % roll,
		"roll": roll,
		"value_mult": RNG.randf_range(float(def["value_mult"][0]), float(def["value_mult"][1])),
		"enhanced": enhanced,
	}
```

Because the ids are unchanged:

- `GameState.party_bonuses()`'s `match` statement needs **no edit** — it reads
  `mod["id"]` and `mod["roll"]`, and a doubled roll is just a bigger roll;
- `compare_flyout._fill_changes()` needs **no edit** — it iterates
  `Itemizer.MODIFIERS` by id to order the change list, and an Enhanced modifier
  is one of those ids;
- `_modifier_pool_excluding()`'s no-duplicates rule works on ids and therefore
  covers Enhanced automatically;
- nothing in the save format needs a second modifier table.

A second pool with ids like `&"dmg_flat_enhanced"` would require touching every
one of those and would double the `match` statement forever.

**Display.** The `enhanced` flag is what the UI reads. Every place a modifier
line is rendered — `inventory_row`, `compare_flyout._fill_mods()`, the forge
row, `shop_buy_card` — draws an enhanced line in
`Tuning.RARITY_COLORS[Item.Rarity.ENHANCED]` instead of the default text colour.
Without a marker, "+18 Damage" is indistinguishable from a lucky roll of the
normal 5–18 range, and the player never learns that the last forge step gave
them something special.

### 10.4 `Item` gains one field

```gdscript
## [town] How many times this item has been through the forge (§10.2). Not
## derivable: rarity alone cannot say whether a Rare was found or forged up
## from Common. Drives the "Forged x2" line on the item card and is part of the
## save format.
@export var forge_count: int = 0
```

### 10.5 Value, and why scrap can never become gold

**Forging adds the gold half of its cost to `item.value`, and nothing else.** It
does *not* re-derive value from `RARITY_VALUE_MULT` and the new modifier sum.

The consequence is the invariant that matters:

> Forging is never profitable to flip. `sell_price()` is `value × 0.5`, so
> forging returns at most half the gold spent and **none** of the scrap. Scrap
> cannot be laundered into gold through the forge at any rarity.

Re-deriving value from the rarity table instead would make a Common bought for
30 gold, forged twice for 60 gold and 15 scrap, sell for ~100 — a slow but real
money printer, and worse, a scrap-to-gold exchange that undermines §5.1's whole
premise of two currencies with disjoint uses.

`buy_price()` and `sell_price()` formulas are **not touched**, which is what
keeps `test_economy.gd:110-111` green.

---

## 11. New tuning constants

All of these go in `scripts/autoload/tuning.gd`, which is the single source of
truth — no other file may hardcode any of them (§0.1.5).

```gdscript
# --- [town] Profile economy -------------------------------------------------
## Distinct from STARTING_GOLD (75), which stays exactly as it is: that number
## is what spec 5.4's slot-economy arithmetic and test_economy.gd:41 are
## written against, and it now means "gold the slot economy was balanced
## against" rather than "gold a new player has". Conflating the two breaks a
## green test for nothing.
const PROFILE_STARTING_GOLD := 150
const PROFILE_STARTING_SCRAP := 0

const INN_REST_COST_PER_HERO := 50
const INN_STREET_HEAL_FRACTION := 0.5      # of MISSING hp, once per expedition
const SHOP_REFRESH_COST := 100
const FORGE_SHOP_SLOTS := 6

# --- [town] The forge -------------------------------------------------------
## [scrap, gold] to raise an item FROM rarity index i to i + 1. Indexed by the
## item's CURRENT rarity, so the array is one shorter than Rarity - there is no
## step out of ENHANCED.
const FORGE_COSTS := [
	[5, 20],      # Common   -> Uncommon
	[10, 40],     # Uncommon -> Magic
	[18, 70],     # Magic    -> Rare
	[30, 120],    # Rare     -> Enhanced
]
## The final step's modifier rolls at double magnitude (§10.3).
const FORGE_ENHANCED_MULT := 2

# --- [town] Combat pickups --------------------------------------------------
const ENEMY_GOLD_DROP := Vector2i(3, 9)    # VALUE, not object count (§9.3)
const ENEMY_SCRAP_DROP := Vector2i(2, 6)
const BOSS_LOOT_MULT := 3
const LOOT_PICKUP_MAX_OBJECTS := 5
const LOOT_ARC_TIME := 0.45
const LOOT_ARC_HEIGHT := 0.9               # world units at the apex
const LOOT_SCATTER_RADIUS := 0.7
const LOOT_SETTLE_TIME := 0.20
const LOOT_FADE_TIME := 0.25               # 0.45 + 0.20 + 0.25 = 0.90s total,
                                           # which is why §9.1 can hide the
                                           # whole animation inside the corpse
                                           # hold and fade (0.75s) plus the
                                           # front of ENCOUNTER_RESOLVE_PAUSE.
```

### 11.1 Does the loop close?

Worth stating, because the original plan added three faucets and four sinks
without costing either side.

Per **easy** quest (3 combats including the boss, ~2 enemies each, the boss
counting triple): roughly 8 enemy-units → ~32 scrap and ~48 gold in pickups,
plus the 200 reward, minus a 50-gold inn stay ≈ **+198 gold, +32 scrap**, before
slot income and item sales.

Per **hard** quest (6 combats, ~3 enemies each, boss triple): roughly 21
enemy-units → ~84 scrap and ~126 gold, plus 600, minus 50 ≈ **+676 gold, +84
scrap**.

A full three-slot forge from Common is **189 scrap and 750 gold**. So a player
running easy quests reaches a fully-forged set in roughly six runs; a player
running hard reaches it in two or three, but has to survive nine encounters with
no heal to do it. Both are inside the range where the forge stays interesting,
and gear churn — finding a Rare base worth restarting a slot's ladder for —
keeps scrap relevant past that point.

These are starting numbers. They are all in one place precisely so they can be
moved.

---

## 12. Art and assets

Per CLAUDE.md's rule on flagging Meshy versus procedural, and its warning that a
generated image is baked pixels that lose runtime parametricity.

### 12.1 Meshy: yes

- **Backpack icon** for the HUD inventory button. A recognisable silhouette with
  real shape detail, sitting next to the Meshy-generated weapon icons in
  `assets/icons/`. Exactly the case CLAUDE.md says to generate.
- **Armor and trinket glyphs** — `helm`, `mail`, `shield`, `ring`, `amulet`,
  `idol` — matching the existing `weapon_*.png` set in `assets/icons/`.
  `item_glyph.gd` keys off `weapon_type`, so these slot in beside the five
  weapon icons with no code change. Six icons, one prompt run, same style
  reference as the existing set.
- **Two static backgrounds**: a medieval blacksmith's forge and a village
  mayor's office, matching `inn-bg.png`'s treatment and painted for a 1080×1920
  portrait crop.

### 12.2 Meshy: no

- **Gold coins and scrap pieces.** A coin is a `CylinderMesh` with
  `radial_segments` high and `height` tiny; a nut is the same cylinder with
  `radial_segments = 6`; a bolt is that plus a small `BoxMesh` head. These are
  "a handful of vertices" — CLAUDE.md's own keep-it-procedural case — and they
  appear at a few dozen pixels, tumbling, for under a second. Generating them
  would spend credits on shapes the player cannot resolve.

  The rarity ring and glow in `item_glyph.gd` stay procedural for the reason
  that file already documents: they are recoloured per rarity at runtime, and
  Enhanced adds a fifth colour they need to keep taking.

### 12.3 Reuse

`town_overview.png` and `inn-bg.png` are already on disk and stay.
`world-map.png` is unused by any scene and is not part of this pass.

---

## 13. Tests

### 13.1 New

**`tests/test_profile_save.gd`** — the one that matters most, because a save bug
is the only bug in this document that destroys player data.

- round-trip: build a profile with gold, scrap, three equipped items of
  different slots and rarities (one forged twice), one loose item and a wounded
  hero; save; clear `GameState`; load; assert field-by-field equality including
  every modifier's `id`, `roll` and `enhanced` flag;
- a missing file returns `false` and leaves `GameState` untouched;
- a corrupt file (truncated, and garbage bytes) returns `false` and does not
  push an error that would fail a headless run;
- a file with `version: 999` returns `false`;
- a loaded item's `modifiers` does not alias `Itemizer.MODIFIERS` — mutate the
  loaded item, assert the constant is unchanged;
- `new_profile()` writes **no** file — §2.3's rule, asserted so that re-adding a
  save call there fails a test rather than quietly costing every player their
  profile on next launch.

Its three equipped items are "of different slots" only from step 4 on; at step 2
distinct `weapon_type` / `rarity` / `equipped_by` stand in, which exercises every
serialized field without depending on an enum that does not exist yet (step-2 Q9).
**Step 4 makes it honest**: all three move onto the warrior as one WEAPON, one
ARMOR and one TRINKET — what a real solo-warrior profile looks like — with no new
assertion, because `slot()` is derived rather than serialized (step-4 Q9, §13.2).

**The suite must not clobber the dev's save.** `test_profile_save.gd` reads and
writes the real `user://profile.save`, because `SaveGame.PATH` is a `const` and
threading a test seam through production code is not worth it for a dev-only
file. Instead `test_support.gd` grows a `guard_user_file(path)` helper that
snapshots the file and restores it byte-for-byte in `finish()`, including when
the test fails partway. Once §3.1's `boot.tscn` loads that file, "run the tests"
silently resetting your town progress is a papercut that would recur forever
(step-2 Q8).

**`tests/test_profile_expedition.gd`** — landed with step 1, because the split
is the one change in this document whose *whole value* is a thing that does not
happen.

- `start_expedition()` alone leaves `gold`, `scrap` and `inventory` untouched.
  This is §2.3's "the one thing a future edit here must not undo", and it is the
  assertion that fails if someone ever tidies that absence away;
- `start_expedition()` still resets everything expedition-scoped:
  `current_encounter_index`, `endless_level_number`, `level`, the expedition
  banks, `drops_by_class`, `_expedition_inventory_mark`;
- a hero at 3 hp keeps 3 hp across `start_expedition()`, and a hero at 0 hp is
  **not** resurrected — the `full_heal = false` branch, which is unreachable
  while `reset_run()` is the only caller of either half and would otherwise
  first be exercised by whichever later step breaks that;
- `new_profile()` full-heals that same wounded hero;
- `reset_run()` still equals both halves in sequence — the contract §13.3 and
  `test_endless_level_gen.gd` lean on.

**`tests/test_enhanced_rarity.gd`** — landed with step 3, for the reason step-1
Q5 gave and steps 1 and 2 both followed: a step that buys isolation and then
ships no assertion of its own has spent the isolation and not collected. Step 3's
acceptance bar is "nothing should move", and "nothing moved" is not something the
existing suite can state about a value it has never heard of.

- `Item.Rarity.ENHANCED == 4` and `RARE` is still `3` — appended, not inserted;
- all five rarity-indexed arrays are length 5, and
  `RARITY_WEIGHTS[ENHANCED] == 0`;
- **every rung of `RARITY_MOD_COUNT` adds exactly one** — §10.2's four-step
  justification, asserted as array arithmetic while it is still cheap to fix;
- **the weight-0 mechanism, asserted directly**: `RNG.weighted_index()` never
  returns a trailing zero-weight index over 20,000 draws. §10.1's guarantee rests
  entirely on that property of a function in another file, so a future rewrite of
  `weighted_index()` fails *here* rather than by leaking Enhanced gear into a
  chest;
- `generate_item()` never rolls `ENHANCED` over 4,000 samples, and its mod count
  still matches its rarity against the widened array;
- `generate_item_with_rarity(ENHANCED)`, `(999)` and `generate_drop(c, 99)` all
  clamp to `RARE`.

**`tests/test_forge.gd`** — lands at **step 9** with `forge()` itself, not step 3
(§10.2, step-3 Q1). Every assertion below needs real scrap spending to mean
anything.

- the ladder reaches `ENHANCED` in exactly four steps from `COMMON`;
- after **every** step, `item.modifiers.size() == RARITY_MOD_COUNT[item.rarity]`
  — the §10.2 invariant, asserted at each rung, not just the top;
- no duplicate modifier `id` at any rung, over 1,000 items;
- `forge()` on an `ENHANCED` item returns `false` and mutates nothing;
- insufficient scrap **or** insufficient gold returns `false` and spends
  neither — assert both totals unchanged, including the §10.2 refund path;
- only the final step produces `enhanced: true` modifiers, and their rolls fall
  within `[min × 2, max × 2]` of the source definition;
- **the arbitrage gate**: over 1,000 items, buying at `buy_price()`, forging to
  every rung, and selling at `sell_price()` never returns more gold than was
  spent. This is §10.5's invariant, and it is the assertion most likely to catch
  a future well-meaning "let's recompute value properly" edit.

**`tests/test_quest_gen.gd`**

- each of the three `.tres` quests produces a `LevelDef` whose encounter type
  sequence matches its `encounter_types` exactly;
- exactly one encounter has `is_boss`, and it is the last;
- the boss's `enemy_stat_ids[0]` comes from `boss_pool` (leftmost slot, §7.3);
- every combat encounter's enemy count is within `enemy_count`;
- every enemy id in the level is in `enemy_pool` or `boss_pool`.

### 13.2 Edited

- `test_drops.gd` — **four edits, all step 4** (step-4 Q2, Q11). An earlier
  draft of this section named only line 23; the type-mix re-derivation it
  attributed to `test_item_distribution.gd` belongs here, because D7 is the only
  type-distribution assertion in the suite.
  - **D2** (line 23): `droppable_classes() == GameState.active_party`.
  - **D7** (lines 77–88) is re-derived. Its `check_between(pct, 16.0, 24.0)` on
    every type's share cannot survive §4.4: slot-first with a solo warrior gives
    axe and sword ≈ 16.7% each, the six armor/trinket types ≈ 11.1% each, and
    bow / dagger / staff exactly 0%. Every one of those is outside the band, and
    the loop iterates the renamed constant besides. The replacement keeps D7's
    spirit — generation is evenly spread, no slot starved or flooded — pointed at
    what §4.4 actually produces, over ~6000 samples:
    - **slot share**: `item.slot()` is WEAPON / ARMOR / TRINKET 33.3% ± 3pp each;
    - **within-slot uniformity**: among the types rolled in a slot, each is
      `1 / n_types_in_slot` ± 3pp;
    - **the §1.6 guarantee, asserted directly**: `bow`, `dagger` and `staff`
      appear **exactly zero** times. This is the regression guard D7 was always
      meant to be, now aimed at the thing slot-first generation is *for*.
  - **D4 and D9** save / override / restore `active_party` and loop
    `droppable_classes()` — §4.5 gives the reasoning.
  - D1, D3, D5, D6 and D8 are **not** edited. D1/D3/D5/D6 pass an explicit class
    to `generate_drop()`, which still works per-class for the mage and ranger
    under §4.4's slot filter, so they keep looping `PARTY_ORDER` and stay green.
- `test_item_distribution.gd` — **one edit**: widen its `by_rarity`, `names` and
  `expected` arrays from four entries to five (step-3 Q6), so `[0, 0, 0, 0]`
  becomes `[0, 0, 0, 0, 0]`, `names` gains `"Enhanced"`, `expected` gains `0.0`
  and the report loop becomes `range(5)`. They are safe unedited at step 3 —
  weight 0 means `by_rarity[item.rarity]` is never indexed at 4 — but they are a
  four-wide array indexed by a five-value enum, and the only thing standing
  between that and an out-of-bounds write is a weight this pass deliberately
  makes editable. Widening costs nothing and removes the trap.

  It asserts **no** type mix (its rarity split is an informational `print`, not a
  `check`), so nothing type-related changes here and no new distribution test is
  added — that is D7's job. **The mod-count assertion at line 68 does not
  change** and must stay passing throughout.
- `test_profile_save.gd` — its three equipped items become one WEAPON, one ARMOR
  and one TRINKET **on the warrior**, which is what §13.1 has always asked for
  and what a real solo-warrior profile looks like; at step 2 distinct
  `weapon_type` / `rarity` / `equipped_by` stood in (step-4 Q9). The fixture
  assigns `weapon_type` directly after generation, so this is three literals
  (`&"axe"` / `&"helm"` / `&"ring"`, all `equipped_by = &"warrior"`) and no new
  assertion: `slot()` is **derived** from `weapon_type` and never serialized, so
  the existing "every `@export`ed field round-trips" coverage already proves it
  survives. `equipped_by`'s StringName round-trip stays covered by the
  `&"warrior"` / `&""` pair, which is the boundary that matters.
- `test_profile_expedition.gd` — edited **twice**, deliberately, and that is a
  feature rather than churn. It is the file that pins whichever seam each step
  moves, so an edit to it is the visible cost of moving one:
  - **step 2** re-points its `new_profile()` / `reset_run()` gold and scrap
    checks from `Tuning.STARTING_GOLD` to §11's `PROFILE_STARTING_GOLD` /
    `PROFILE_STARTING_SCRAP`, because §2.3 mandates the constant swap (step-2 Q3);
  - **step 4** replaces its P6 "`active_party` still equals `PARTY_ORDER`" check
    (line 123) with **two** checks when §4.5 flips the party solo (step-4 Q8):

    ```gdscript
    t.check(GameState.active_party == ([&"warrior"] as Array[StringName]),
        "active_party is the solo warrior (got %s)" % [GameState.active_party])
    t.check(GameState.PARTY_ORDER.size() == 3,
        "PARTY_ORDER is untouched - the 3-hero roster still exists (spec 4.5)")
    ```

    The second line is the one worth having: §4.5 and §0.2 both say the flip is
    `active_party`'s *value*, **not** a deletion of `PARTY_ORDER`, and without an
    assertion a future tidy-up that trims the roster to match would go unnoticed
    until the mage came back. P6 runs after `reset_run()` at P5, i.e. post-
    `new_profile()`, so `[&"warrior"]` is the expected value.

  An edit here should always be traceable to a named section. An edit that is
  not is a regression wearing a test's clothes.

### 13.3 Must stay green with no edits

`test_economy.gd`, `test_slot_odds.gd`, `test_upgrades.gd`,
`test_autoload_safety.gd`, `test_retarget.gd`, `test_parallax_seam.gd`,
`test_damage_chunk.gd`, `test_endless_level_gen.gd`.

`test_endless_level_gen.gd` in particular: endless mode is still there, still
default-`true` on `GameState`, and only bypassed when `quest != null`. It calls
`GameState.reset_run()` directly, which is why §2.3 keeps that function alive
for the whole pass rather than deleting it.

### 13.4 Debug harness

`scripts/autoload/debug.gd` gains verbs, in its existing one-line-per-command
style:

```
scrap <n>                   add scrap
forge <weapon|armor|trinket>  forge the item in that slot once
quest <easy|medium|hard>    start that quest from anywhere
town                        route to town
wipe                        delete the save file and start a new profile
```

`wipe` is the one a tester will reach for most and the one most easily
forgotten.

---

## 14. Build order

Each step should leave the game runnable. Do not start the next until the
previous is green.

1. **§2.3 — split `reset_run()`** into `new_profile()` / `start_expedition()`,
   with `active_party` still equal to `PARTY_ORDER` and nothing else changed.
   The game plays exactly as it does today. This is the riskiest step and it is
   first, alone, so a regression here is unambiguous. **Done.** All of §2.2's
   fields land here as inert data (defaults only — no `add_scrap`/`spend_scrap`,
   no `scrap_changed` emission, no `SaveGame` call, `quest` untyped until
   `QuestDef` exists), `reset_run()` becomes the two-line wrapper §2.3
   describes, and `test_profile_expedition.gd` (§13.1) pins the seam.
2. **§2.4 — `SaveGame`** plus `Item.to_dict()` / `from_dict()`, and
   `test_profile_save.gd`. Still no town. **Done.** Registered as an autoload
   after `GameState` (anywhere after is sufficient — being later in the list
   also means `SaveGame` is freed *earlier*, so it can never outlive the
   `GameState` its `_notification()` save reads). `forge_count` ships here as an
   inert `@export` so the item serializer is complete from day one;
   `forge_stock` deliberately does not (§2.4's two rules). `new_profile()` swaps
   to the §11 constants and, contrary to §2.3's original listing, **does not
   save** — see §2.3 and the step-5 warning in §3.1, which is the bug that rule
   exists to defuse.
3. **§10.1 — the `ENHANCED` rarity**, all five arrays, weight 0. Run the full
   suite; nothing should move. **Done.** §10.1 *only* — the section reference was
   originally the bare "§10", which reads as though `forge()` belongs here; it
   does not, and cannot (§10.2, step-3 Q1). This step is purely additive: a
   fifth enum value, a fifth entry in three `Itemizer` arrays and in
   `RARITY_COLORS`, a fifth `rarity_name()` string, and three `clampi` literals
   tightened into the enum name they already meant. No behaviour changes and no
   existing test is edited, which is exactly what "nothing should move" asks
   for. `test_enhanced_rarity.gd` (§13.1) is what makes that claim checkable.
4. **§4 — three slots**: `Item.slot()`, `ITEM_TYPES`, the slot-aware
   `equipped_item()`, the `compare_flyout` fix, slot-first generation. Update
   `test_drops.gd` and `test_item_distribution.gd`. The last invisible step, and
   the one with the largest test surface in the pass. Its changeset, after the
   step-4 questions were resolved:

   - `scripts/data/item.gd` — the `Slot` enum and `slot()`; `usable_by()` reads
     `ITEM_TYPES`; comments on `weapon_type` and on `kind` staying `WEAPON`
     (§4.1). `type_initial()` is **not** touched (see §15).
   - `scripts/autoload/itemizer.gd` — `WEAPON_TYPES` → `ITEM_TYPES` with a `slot`
     on every entry plus the six new armor / trinket types (§4.2);
     `types_for_slot()`, `_equippable_slots_for()`, `_roll_typed()`, and
     `generate_item_with_rarity()` / `generate_drop()` rebuilt on them (§4.4);
     `droppable_classes()` reads `active_party` (§4.5).
   - `scripts/autoload/game_state.gd` — `equipped_item(hero, slot)` and
     `equipped_set(hero)`; the slot lookups in `equip_item()` and
     `_maybe_auto_equip()` (§4.3); **and the value flip** — `active_party`'s
     initialiser *and* `new_profile()`'s assignment both become `[&"warrior"]`
     (§4.5). That flip is the edit that actually does the work; the read swaps
     without it change nothing.
   - `scripts/modals/compare_flyout.gd` — the §6.3 one-liner.
   - `scripts/autoload/debug.gd` — the `state` line via `equipped_set()` (§4.3).
   - tests: `test_drops.gd` (D2, D7, D4/D9), `test_item_distribution.gd` (the
     four-to-five widening), `test_profile_expedition.gd` (P6),
     `test_profile_save.gd` (one item per slot) — all §13.2.

   **What step 4 accepts, deliberately:** one modifier pool serves all three
   slots, so a helm can roll `+7 Bolt Power` and a ring `+5 Fire Damage` (§15
   defers per-slot pools). The six new types render as the generic gem glyph
   until §12 at step 11, since `item_glyph.gd`'s `WEAPON_TEXTURES` has no entry
   for them and `_draw()` falls through to `_draw_gem()` — which is correct for a
   step that is invisible by design.
5. **§3 — `SceneRouter` and `Hud`**, `boot.tscn`, `RunSummary` → `QuestResult`
   moved into the HUD. The forest still starts, now via the router. **Read
   §3.1's `RunController._start_run()` warning before starting this step** — it
   is the step where a leftover `reset_run()` on the boot path stops being
   harmless and starts destroying saved profiles.
6. **§6 — the inventory modal** and `inventory_row.tscn`.
7. **§7.1, §7.2 — town hub and inn**, wired to the router.
8. **§8 — `QuestDef`, the three `.tres` files, `_build_quest_level()`**, and the
   victory/failure flows. The loop closes here: this is the first commit where
   the game is the game this document describes.
9. **§5, §9 — scrap and the pickups**, and with them **§10.2, §10.3 and
   `test_forge.gd`** (step-3 Q1). `GameState.add_scrap` / `spend_scrap` and the
   `scrap_changed` emission are born here, which is what `forge()` has been
   waiting for; `EventBus.item_forged` arrived at step 5 and
   `run_stats["items_forged"]` lands alongside the scrap API. §11's
   `FORGE_COSTS` / `FORGE_ENHANCED_MULT` come with them. Order within the step:
   the currency API first, then `forge()`, then `test_forge.gd` — the test's
   "insufficient scrap spends neither" and arbitrage assertions are meaningless
   against anything less than real spending.
10. **§7.3, §7.4 — the blacksmith**, forge and expanded shop.
11. **§12 — art**: Meshy icons and the two backgrounds.

Steps 1–4 are all invisible to the player and all individually testable. Step 8
is the one worth demoing.

---

## 15. Deferred — deliberately not in this pass

Recorded so they are decisions rather than omissions.

- **Mid-quest save/resume** (§0.2). Wants a snapshot of encounter index, hero
  HP, pending drops and the generated `LevelDef`.
- **The mage and ranger returning.** The seam is `active_party` plus armor and
  trinket rows in `ITEM_TYPES` carrying their class ids. Drop coverage
  (`DROP_CATCHUP`, `next_drop_class`) is untouched and waiting for them — do
  not delete it.
- **Armor and trinket modifiers of their own.** Right now every slot draws from
  the same eight-modifier pool, so a helm can roll "+7 Bolt Power". Per-slot
  pools are the obvious next step and want their own balance pass.
- **`Item.type_initial()`'s letter collisions.** Eleven types share ten initials
  once armor and trinkets land — sword / shield both `S`, axe / amulet both `A`
  (`staff` already has a hand-written `T` exception). It feeds only the spec 17.2
  inventory chip, which §6's inventory modal supersedes at step 6, so step 4
  leaves it alone rather than inventing a second exception table for a widget on
  its way out. Revisit at step 6, or delete it with the chip.
- **Fly-to-counter pickup polish** (§9.4).
- **More than one town.** `SceneRouter.Place` is an enum for a reason; a second
  town is a second set of entries.
- **A quest log, quest variety, or quest-specific objectives.** Three fixed
  tiers is the vertical slice.
- **Repricing the slot economy for a profile-scoped wallet.** `STARTING_GOLD`
  and the slot payouts were balanced for a 75-gold single run; a player who
  walks into a quest with 900 banked gold is in a different economy. Worth a
  pass once the loop is playable and there are real numbers to look at.
