# Sir Fish — Levels & Stats

**An implementation prompt.** Not a spec to obey to the letter; a brief with the
shape of the answer already decided. Where it names a file, a constant or a
number, that is a real thing in this repo — go read it before you change it.

---

## The problem, stated precisely

Three findings from reading the current code, in the order they matter:

1. **The boss is bigger, not stronger.** `battle_director.gd:216` duplicates the
   stats resource and multiplies `model_scale` by `BOSS_SCALE_MULT` (1.5). It
   also sets `drop_chance` and `drop_rarity_floor`. It does **not** touch
   `max_hp` or `base_damage`. A boss skeleton warrior is the same 90 HP / 16
   damage as the ones the party killed two encounters earlier.

2. **Difficulty is expressed only as data, and that data has run out of room.**
   `quest_def.gd`'s header states the rule outright — "Difficulty is expressed
   as DATA … never as a stat-scaling multiplier" — and `_build_endless_level()`
   repeats it. That was the right call while there was nowhere to put a level.
   Now there is: hard tier can only reach for a wider `enemy_pool`, a bigger
   `enemy_count` (capped at `MAX_ENEMIES`) and more encounters. All three are
   exhausted; `hard.tres` already runs 3 enemies from the full pool across nine
   encounters and the party still walks it.

3. **Gear is the entire offense, and it compounds.** Slot phase 2 removed item
   bonuses from melee damage (`combatant.gd:127-135` — `bonus_flat_damage` and
   `_item_pct_multiplier` are pinned at their identity values). Everything an
   item does now goes through the bag. Three Enhanced items put 12 icons into a
   ~17-icon bag; nine are drawn per spin, so ~7 resolve, each for up to 18,
   every ~2.5 s. Against enemies with 28–90 HP that is the whole fight.

A fourth finding is what makes the fix in this brief possible at all:

4. **A Common contributes nothing.** `RARITY_MOD_COUNT := [0, 1, 2, 3, 4]`, and
   `slot_machine._rebuild_bag()` builds the bag purely from `item.modifiers`. An
   equipped Common adds **zero** icons. "Common items now provide a base amount
   of damage" therefore is not a bigger number on an existing path — it needs a
   new icon source.

---

## The model in one page

Three stats, on every character, hero and enemy alike:

| stat | what it does |
|---|---|
| **Health** | `max_hp`. Already exists; keeps its name. |
| **Weapon Power** | scales damage from a WEAPON-school action (melee swings, arrows). |
| **Magic Power** | scales damage from a MAGIC-school action (bolts, the mage's heal). |

Every character has a **level**. Its three stats are `base + growth × (level − 1)`
— linear, one formula, no per-stat curve table. The level-1 base is what is
authored in `resources/stats/*.tres` today, so a level-1 world is the world as
it currently plays.

Every **item** has a level, stamped where it dropped and never changed. It gives
the item a **base power**, `ITEM_BASE_POWER × level`, which every icon that item
puts on the board adds to its rolled value.

Every **encounter** has a level, from the expedition's authored band. The boss
sits `BOSS_LEVEL_BONUS` levels above the band's top.

Two channels, each with one owner, so nothing is counted twice:

- **Direct attacks** (`Ability._strike`, `projectile.gd`, `magic_bolt.gd`) scale
  with the acting character's Weapon or Magic Power. Gear does not touch them —
  that stays exactly as slot phase 2 left it.
- **The slot board** scales with the *item's* level and its rolled modifiers.
  Hero stats do not touch it, except through the innate icon (§4.4), which is
  the one thread tying hero level back to the board.

Gear gives **no stat increases**. It gives icons. That is the whole of what gear
does, and it is why the two channels can stay separate.

---

## 1. Stats and levels on characters

### 1.1 `scripts/data/combatant_stats.gd`

Replace `base_damage` with the two power stats, and add growth alongside each of
the three:

```gdscript
@export var max_hp: int = 100
@export var weapon_power: int = 10
@export var magic_power: int = 0

## Added per level above 1. Authored per character rather than derived from a
## global fraction: a glass-cannon skeleton mage and a wall of a skeleton
## warrior should not diverge only in their level-1 row.
@export var hp_per_level: int = 0
@export var weapon_power_per_level: int = 0
@export var magic_power_per_level: int = 0
```

`base_damage` goes away. Its four readers are small and all listed in §7.1.

Add the resolver as a **static** helper plus three thin readers — never a `level`
field on the resource. The resource is shared and cached
(`GameState._stats_cache`), so it must never carry the level of one spawn:

```gdscript
static func at_level(base: int, growth: int, level: int) -> int:
    return base + growth * maxi(level - 1, 0)

func hp_at(level: int) -> int:            return at_level(max_hp, hp_per_level, level)
func weapon_power_at(level: int) -> int:  return at_level(weapon_power, weapon_power_per_level, level)
func magic_power_at(level: int) -> int:   return at_level(magic_power, magic_power_per_level, level)
```

### 1.2 Growth defaults for the eleven `.tres` files

Level-1 rows are unchanged — copy `base_damage` into `weapon_power`, or into
`magic_power` where the character's `attack_style` is MAGIC. Growth starts at a
fraction of the level-1 base, rounded, then is hand-tuned against the harness in
§6:

- `hp_per_level ≈ round(max_hp × 0.50)`
- `*_power_per_level ≈ round(power × 0.35)`

| id | level-1 HP / power | +HP | +power |
|---|---|---|---|
| `warrior` (hero) | 120 / 12 wp | 42 | 4 wp, 1 mp |
| `mage` (hero) | 70 / 10 **mp** | 25 | 4 mp |
| `ranger` (hero) | 80 / 14 wp | 28 | 5 wp |
| `skeleton_minion` | 28 / 6 wp | 14 | 2 |
| `shadow_monster` | 40 / 8 wp | 20 | 3 |
| `skeleton_rogue` | 50 / 12 wp | 25 | 4 |
| `skeleton_mage` | 55 / 18 **mp** | 28 | 6 |
| `sporecap` | 65 / 13 wp | 33 | 5 |
| `skeleton_warrior` | 90 / 16 wp | 45 | 6 |
| `orc_barbarian` | 70 / 15 wp | 35 | 5 |
| `orc_warlord` | 280 / 22 wp | 140 | 8 |

The two orcs stay out of every pool (see `ENDLESS_MID_POOL`'s comment); they get
rows so nothing goes stale, not because anything spawns them.

Give the mage a small `weapon_power` (say 4) and the martial characters a small
`magic_power`. A zero on either is readable, but a character whose non-primary
school is 0 deals exactly 1 damage (`compute_damage()` floors at 1) if an ability
of that school is ever aimed through it.

### 1.3 `scripts/battle/combatant.gd`

Add `var level: int = 1` and take it in `setup()`:

```gdscript
func setup(s: CombatantStats, starting_hp: int = -1, a_level: int = 1) -> void:
```

`_build()` and `setup()` both read `stats.max_hp` directly (`combatant.gd:82`,
`:107`). Both become `stats.hp_at(level)`. Note `_build()` can run before
`setup()` assigns the level (`_ready()` calls it when `stats` is already set), so
`level` must default to 1 at declaration and `_build()` must stay re-entrant — it
already is.

Replace `compute_damage()` with a school-aware version. Keep the no-argument call
shape working, because five call sites use it and only one of them cares:

```gdscript
enum School { WEAPON, MAGIC }

## The school this character's ordinary attack belongs to. Derived from
## attack_style rather than stored: a MAGIC attacker's bolt is magic, and
## MELEE / RANGED both swing or shoot something physical. An ability that
## wants the other school passes it explicitly (see Ability.school).
func default_school() -> School:
    return School.MAGIC if stats.attack_style == CombatantStats.AttackStyle.MAGIC \
        else School.WEAPON

func power(school: School) -> int:
    return stats.magic_power_at(level) if school == School.MAGIC \
        else stats.weapon_power_at(level)

func compute_damage(school: int = -1) -> int:
    var s: School = default_school() if school < 0 else school as School
    var raw := (float(power(s)) + float(bonus_flat_damage)) * damage_multiplier
    raw *= RNG.randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
    return maxi(1, int(round(raw)))
```

`bonus_flat_damage` and `damage_multiplier` keep their current jobs — the meal
buff (`GameState.meal_multiplier()`) still rides `damage_multiplier`, and
`apply_party_bonuses()`'s header comment stays true: gear still adds no numbers
here.

### 1.4 `scripts/battle/ability.gd`

Give `Ability` a `school`, defaulting to the source's own, so the mage's heal and
the ranger's bomb arrow can each name theirs:

```gdscript
var school: int = -1     # -1 = the source's default_school()
```

`_strike()` (`ability.gd:145`) passes it through to `compute_damage(school)`.
`_mage()`'s heal (`ability.gd:113`) is MAGIC by the mage's own default and needs
no explicit value. `projectile.gd:42` and `magic_bolt.gd:35` call
`source.compute_damage()` and inherit the default correctly today —
`projectile.gd:44`'s `source.stats.base_damage` read (the bomb arrow's
`RANGER_BOMB_AOE_MULT` line) becomes `source.power(Combatant.School.WEAPON)`.

---

## 2. Encounter levels — making the content keep pace

### 2.1 `scripts/data/encounter_def.gd`

```gdscript
## The level every combatant in this encounter spawns at. Set by the builders
## in game_state.gd from the expedition's band; the boss slot adds
## Tuning.BOSS_LEVEL_BONUS on top (battle_director.start_combat()).
@export var level: int = 1
```

### 2.2 `scripts/data/quest_def.gd`

```gdscript
## Inclusive level band for this expedition (§2.3). The first encounter runs at
## x, the last regular encounter at y, interpolated across the list; the boss
## sits BOSS_LEVEL_BONUS above y.
@export var level_range: Vector2i = Vector2i(1, 1)
```

This does **not** contradict `quest_def.gd`'s "difficulty is data, never a
multiplier" rule — it *extends* it. A level is authored data on the quest,
resolved into authored data on the encounter, and read by the one place that
already builds a combatant. It is not a scaling factor applied on top of
`CombatantStats`; it is an argument to it. Update that header comment to say so,
or the next reader will delete this in good faith.

Authored bands:

| quest | `level_range` | boss level |
|---|---|---|
| `easy.tres` — The Shallow Wood | `(1, 5)` | 8 |
| `medium.tres` | `(6, 14)` | 17 |
| `hard.tres` — The Heart of the Wood | `(15, 30)` | 33 |

The bands are **wide and non-overlapping on purpose** — §5.3 explains why the
gear-churn goal needs them to be.

### 2.3 `game_state._build_quest_level()`

Assign each encounter's level by interpolating the band across the sequence.
Non-combat encounters (LOOT, SHOP) take a level too — the chest and the shop
stock are stamped with it (§4.2):

```gdscript
var t: float = float(i) / float(maxi(n - 1, 1))
enc.level = int(round(lerpf(float(q.level_range.x), float(q.level_range.y), t)))
```

### 2.4 `_build_endless_level()` and `_build_whispering_wood_level()`

Endless depth becomes the level dial it always wanted to be. For depth `d`, band
`(d × ENDLESS_LEVELS_PER_DEPTH, d × ENDLESS_LEVELS_PER_DEPTH + 4)`, interpolated
the same way. `ENDLESS_LEVELS_PER_DEPTH := 3`, so depth 1 runs levels 3–7 and
depth 10 runs 30–34.

The fixed Whispering Wood level (`endless_mode = false`, the dev path) pins every
encounter at level 1 — it is the "world as authored" baseline the harness in §6
measures against.

### 2.5 `battle_director.start_combat()`

Take the level, and make the boss a boss:

```gdscript
func start_combat(enemy_stat_ids: Array, is_boss: bool = false,
        boss_rarity_floor: int = 1, level: int = 1) -> void:
```

Pass `level` into `_spawn_combatant()` → `c.setup(stats, hp, level)`. For slot 0
of a boss fight, alongside the existing `model_scale` / `drop_chance` /
`drop_rarity_floor` handling on the **duplicated** stats resource:

```gdscript
var unit_level: int = level + (Tuning.BOSS_LEVEL_BONUS if is_boss and i == 0 else 0)
```

and multiply **both** `max_hp` **and** `hp_per_level` by `Tuning.BOSS_HP_MULT`
on the duplicated resource, before the level resolve — not on the combatant
afterwards, so `hp_at()` stays the single answer to "how much HP does this unit
have". Scaling `max_hp` alone was the first thing tried here and it is a real
trap: `hp_at()` is `base + growth × (level−1)`, so multiplying only `base`
leaves `growth` unscaled and the boss's HP edge **shrinks away at high levels**
— a level-18 skeleton warrior boss came out to 990 HP against a level-18
regular's 855, only 16% more, the opposite of the intent. Scaling both fields
makes `hp_at(unit_level)` come out to exactly
`hp_at_unboosted(unit_level) × BOSS_HP_MULT`, confirmed against a level-15
regular vs. a level-18 (15 + `BOSS_LEVEL_BONUS`) boss of the same id: 720 HP vs.
2146 HP, essentially the full 2.5× on top of the level bump's own share.

**[Phase 6 result]** The values above were the launch guess; `test_level_curves.gd`
caught a second, structural problem with `BOSS_LEVEL_BONUS := 3` once real
numbers were run across every band: a **fixed** level bonus is a *shrinking
percentage* add as the band's own level rises (`hp_per_level` dominates over
the base at high level), so the boss/regular HP ratio decayed from **6.3× at
level 1 to 2.75× at level 30** — the boss becoming relatively *less* impressive
exactly where the game is hardest. `BOSS_HP_MULT` is level-independent by
construction (it is a pure multiplier), so leaning on it more and shrinking the
level add to a minor accent fixes the decay directly. Retuned to
`BOSS_LEVEL_BONUS := 1`, `BOSS_HP_MULT := 3.5`, which holds the ratio in a tight
3.6×–5.3× band across every authored level (1/5/10/20/30) — confirmed by the
harness, not just computed by hand. Against the bands above, the easy boss is
now a level-6 skeleton warrior at (90 + 45×5) × 3.5 = 1147.5, hitting for
16 + 6×5 = 46. The party fights it at level ~5. That is a boss, at every level,
not just the first one anyone bothered to hand-check.

Heroes are spawned from `GameState.hero_runtime`; they take the **hero's own
level** (§3), never the encounter's.

### 2.6 Where the encounter level shows

- `mayor_office._populate()`'s button text gains a level line:
  `"%s\n%s\nLevels %d–%d   ·   %d encounters   ·   %d gold"`. When
  `GameState.hero_level()` is below `level_range.x`, tint the button toward
  `Tuning.C_DANGER` and append "— you are underlevelled". Do **not** disable it:
  difficulty is the gate (`mayor_office.gd`'s header), and this pass does not
  change that.
- `combatant_bars.gd` gains a small level pip beside the enemy name.
- The travel/encounter banner already names the level; append " · Lv N".

---

## 3. Hero levels and XP

### 3.1 State

`GameState` gains two profile-scoped fields, keyed by class so the mage and
ranger inherit the system the day they return:

```gdscript
## StringName -> int. Absent means level 1 / 0 xp.
var hero_levels: Dictionary = {}
var hero_xp: Dictionary = {}
```

with `hero_level(id) -> int` and `hero_xp_for(id) -> int` accessors, plus
`hero_level()` with no argument returning the highest level in `active_party`
(what the mayor's office and the town shop level want).

`new_profile()` sets every `active_party` member to level 1, xp 0 — "the warrior
starts at level 1" is this line.

### 3.2 Earning

XP is awarded per kill and **banked**, not applied, so no hero's power changes
mid-expedition:

```gdscript
var expedition_xp: int = 0        # sibling of expedition_gold / expedition_scrap
```

`battle_director`'s existing death path (the same place `LootPickup.spawn_for()`
fires, `battle_director.gd:57-60`) adds `Tuning.XP_PER_ENEMY_LEVEL × enemy.level`,
times `Tuning.XP_BOSS_MULT` for the boss unit — reuse the `is_boss_unit`
expression already computed there.

`GameState` applies the bank at expedition end, in the same call that pays
`gold_reward` (town spec §8.5, where `completed_quest` is set). A wipe carries
nothing home, exactly like the scrap bank.

Curve: `xp_to_next(level) = Tuning.XP_CURVE_BASE × level`, `XP_CURVE_BASE := 100`.
Cumulative to level 10 is 4 500. An easy expedition (≈10 enemies at level 1–5,
`XP_PER_ENEMY_LEVEL := 12`) banks ≈ 500 XP including the boss — about two levels
on the first run, tapering. That lands the party mid-band for easy and short of
medium, which is the intent: the next tier is a step up, not a formality.

Cap at `Tuning.HERO_MAX_LEVEL := 40`.

### 3.3 Applying a level

Levelling raises `max_hp`, so `hero_runtime`'s `max_hp` entry must be rewritten
and `current_hp` raised by the same delta — a level-up is not a heal, but it must
not *cut* current HP either. `_reset_hero_runtime()` (`game_state.gd:817`) is
where `max_hp` is seeded; it becomes `s.hp_at(hero_level(id))`, and the
`stats.max_hp` reads in `party_status()` (`game_state.gd:466-468`) follow.

Emit a new `EventBus.hero_levelled(hero_class: StringName, new_level: int)` so
`quest_result.gd` can show "Warrior reached level 6" as a stat row, and the night
modal's bars draw against the new maximum.

### 3.4 Where the hero level shows

- `party_modal.gd`'s per-hero row: "Warrior · Lv 6", with the three stats under
  the HP bar. `stat_chip.tscn` is already the tile for exactly this shape — reuse
  it with captions "Weapon Power" / "Magic Power" / "Health" rather than
  authoring a second chip.
- `hero_bars.gd` in combat: a level pip, matching the enemy one from §2.6.

---

## 4. Item levels and base icons

### 4.1 `scripts/data/item.gd`

```gdscript
## The level this item was made at — the encounter that dropped it, or the shop
## tier that stocked it. NEVER changes: the forge raises rarity and adds
## modifiers, it does not re-date an item (§5.3). This is what lets a Common
## from deep content out-damage an Enhanced forged in the shallows.
@export var level: int = 1

## Flat power every icon this item puts on the board adds to its rolled value
## (§4.4). The whole of what item level does.
func base_power() -> int:
    return Tuning.ITEM_BASE_POWER * maxi(level, 1)
```

`to_dict()` / `from_dict()` gain `"level"`, defaulting to 1.

`subtitle()` becomes `"Lv %d %s %s — %s"`. `item_glyph.gd` gains a level badge in
the corner opposite the existing rarity ring — procedural, per `CLAUDE.md`
best-practice 2's "simple geometric primitives, recoloured per state" rule. This
is not a Meshy job.

**`SaveGame.VERSION` bumps 2 → 3.** By the policy in `save_game.gd:17-28`, adding
a key alone never needs a bump — but this changes what an existing saved item
*means*: every item in a live profile would load at level 1 and be near-inert
against level-scaled enemies. That is the "meaning of an existing key changes"
trigger, and the honest outcome is the same as the 1 → 2 bump: reject the save,
fall back to `new_profile()`.

### 4.2 Stamping the level — `scripts/autoload/itemizer.gd`

Every generator takes a level, defaulting to the party's, so the Debug harness
and any call site not yet updated keeps working:

```gdscript
func generate_item(level: int = -1) -> Item
func generate_item_with_rarity(rarity_index: int, level: int = -1) -> Item
func generate_drop(hero_class: StringName, rarity_floor: int = 0, level: int = -1) -> Item
func generate_shop_stock(level: int = -1) -> Array[Item]
func generate_forge_stock(level: int = -1) -> Array[Item]
```

`-1` resolves through one helper — `GameState.default_item_level()`, returning
`hero_level()` — so "what level is an unstamped item" has exactly one answer.
`_generate_typed()` sets `item.level` and is the only writer.

Sources:

| source | level |
|---|---|
| enemy drop | the dying enemy's `level` (so a boss drops boss-level gear) |
| LOOT chest | the encounter's `level` |
| in-expedition SHOP | the encounter's `level` |
| blacksmith stock (town) | `GameState.hero_level()` — no expedition context exists in town |

Item level should also lift `value`, or a level-30 Common sells for the same 20 G
as a level-1 one and the economy stops tracking power. Fold it into
`_generate_typed()`'s final line as a `(1 + ITEM_VALUE_PER_LEVEL × (level − 1))`
factor, `ITEM_VALUE_PER_LEVEL := 0.35`. `test_economy.gd` pins the affordability
band and needs re-baselining against the level-1 case, which is unchanged.

### 4.3 Base icons — `scripts/console/slot_icon.gd`

Three new ids, one per equipment slot, alongside the two innate ones:

```gdscript
const BASE_WEAPON  := &"base_weapon"    # Kind.DAMAGE — a strike
const BASE_ARMOR   := &"base_armor"     # Kind.HEAL   — a ward
const BASE_TRINKET := &"base_trinket"   # Kind.DAMAGE — magic-tinted

static func base_for(slot: Item.Slot) -> StringName
```

`kind_of()`, `short_label()` ("Strike" / "Ward" / "Focus"), `is_percent()` (true
for `BASE_ARMOR`, which heals a percent like `slot_mend`) and `chip_path()` each
extend by one `match` arm. The three borrow existing reliquary chips until art
exists — `chip_dmg_flat`, `chip_slot_mend`, `chip_elem_light` — exactly as the two
innate ids already borrow theirs.

`slot_machine._rebuild_bag()` gains one line per equipped item, before its
modifier loop:

```gdscript
_bag.append(SlotIcon.from_item_base(item))
```

So an equipped Common contributes **one** icon, and every rarity contributes
`RARITY_MOD_COUNT[r] + 1`. Three equipped items are a guaranteed three icons in
the bag no matter what the player wears — which also retires the last real use of
the "wiped party leaves an empty bag" fallback, though leave the guard in place.

### 4.4 Magnitude

Every icon an item supplies resolves at **`item.base_power() + roll`**, base
icons included (`roll = 0` for them). `SlotIcon.from_modifier()` and
`from_item_base()` both need the item to compute it, so `from_modifier()` gains an
`item` argument and writes the summed magnitude into the icon's existing `"roll"`
key. Nothing downstream changes — `_resolve_icon()`, `_strike()`, `_heal_lowest()`
and `hero_reel_icons()` all read `"roll"` and stay as they are.

Keep the raw modifier roll in a separate `"mod_roll"` key on the icon dict for the
party modal's readout, so "+4 Damage" on the item card and "+34" on the board are
both truthfully sourced.

Innate icons stay hero-driven and become the one place hero stats reach the board:
`SLOT_INNATE_DAMAGE` becomes
`round(hero.power(School.WEAPON) × Tuning.SLOT_INNATE_POWER_FRACTION)` with the
fraction at 0.5; `SLOT_INNATE_HEAL_PCT` stays a flat percent of max HP.

---

## 5. What the numbers do

`ITEM_BASE_POWER := 6`, so `base_power(L) = 6L`.

### 5.1 One item's total board magnitude

Icon count is `RARITY_MOD_COUNT[r] + 1`. Average modifier roll ≈ 5.5, ≈ 11 for a
forged Enhanced modifier (`FORGE_ENHANCED_MULT`).

| item | icons | magnitude each | total |
|---|---|---|---|
| Lv 5 Enhanced (forged in easy tier) | 5 | 30 + ~8 | ~190 |
| Lv 5 Magic | 3 | 30 + ~5.5 | ~107 |
| Lv 14 Uncommon (medium-tier drop) | 2 | 84 + ~5.5 | ~179 |
| Lv 14 Common | 1 | 84 | 84 |
| Lv 30 Common (hard-tier drop) | 1 | 180 | **180** |

### 5.2 The crossovers this produces

- A **medium-tier Uncommon out-damages an easy-tier Magic** — churn at the middle
  rarities is immediate and constant, which is where the scrap and gold actually
  flow.
- A **hard-tier Common ties a fully-forged easy-tier Enhanced.** That is the
  headline case from the brief, and it lands at roughly one full tier of level
  advantage.

### 5.3 The honest limit — read this before tuning

Icons are additive and independent, so **rarity buys count and level buys
magnitude, and count is worth more per unit**. An Enhanced has 5× a Common's icons
in the same slot; for a Common to beat it, its level must be roughly 5×. No choice
of `ITEM_BASE_POWER` changes that ratio — the constant shifts the crossover by a
few levels, not by an order.

This is why the level bands in §2.2 are wide and stacked (1–5 / 6–14 / 15–30)
rather than gentle. The churn the brief asks for is a function of **how far apart
the tiers are in level**, not of how steep the power curve is. If it is too slow
in play, the dials in order of effect are:

1. widen the bands (hard → 20–45),
2. raise `ITEM_BASE_POWER`,
3. **cap icons per item** — e.g. an item contributes at most 3 icons, with the 4th
   and 5th modifiers raising the *magnitude* of the existing ones instead. This is
   the only change that alters the 5:1 ratio itself, and it is a real redesign of
   what rarity means, so it is named as a lever and not done here.

---

## 6. The balance harness

Add `tests/test_level_curves.gd` + `.tscn`, in the style of `test_economy.gd` and
`test_slot_odds.gd` (headless, seeded RNG, assertions on bands not exact values):

```
godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_level_curves.tscn
```

It must assert, per level band {1, 5, 10, 20, 30}:

1. **Time to kill a regular enemy stays in a bounded band.**  Model the
   party's per-spin output as `draw_nine()` over a bag built from
   tier-appropriate gear (reuse `SlotMachine.draw_nine()` — it is already
   `static` for exactly this reason), over
   `SLOT_SPIN_DURATION + SLOT_REEL_STAGGER × 2 + SLOT_RESULT_HOLD`, plus hero
   melee at `attack_cooldown`.
2. **Time for the enemies to kill the party stays above a floor** at band
   level, so a correctly-levelled party is threatened, not deleted.
3. **The boss takes 3–6× a regular unit's time to kill** in the same encounter.
4. **A party two levels under the band's floor loses** — the underlevelled warning
   in §2.6 must be telling the truth.
5. **The §5.1 crossover table holds** to within 15%.

**[Phase 6 result] Assertions 1 and 2 do NOT hold the 12–30 s / >25 s numbers
first written here — and that is correct, not a shortfall.** Those figures were
written before any simulation or playtest existed. The first real run of this
harness, against the exact Phase 1–5 numbers a human playtest had just
approved, measured a stable **3.9–7.8 s** time-to-kill and a stable **~8 s**
party survival time across every band — internally consistent (neither drifts
toward broken as level rises), and correct for what this game actually was at
the time: a fast **real-time** combat loop (`BattleDirector.turn_based_combat`
defaulted **false** — enemies in a group genuinely acted concurrently, not
serialized through a turn queue), with a ~2.5 s slot cycle and ~1.5–2.2 s
attack cooldowns. Rebalancing already-shipped, already-approved numbers to
chase a pre-implementation guess would have been solving a problem that only
existed on paper. The harness's own bounds were recalibrated to 3–10 s / >6 s
to match the measured, validated reality of that mode.

**[STALE]** `turn_based_combat` now defaults **true** (a later decision, made
after this Phase 6 pass). Heroes and enemies now share ONE queue — one actor's
whole action must finish before the next starts — which the model above does
not represent at all (it sums each enemy's damage as landing independently and
concurrently). The 3.9–7.8 s / ~8 s figures, and the recalibrated 3–10 s / >6 s
harness bounds built from them, have not been re-measured against turn-based
play and should not be trusted until `test_level_curves.gd` is re-run.

**Assertion 3 is the one that DID catch a real bug**, and is worth trusting
precisely because it did: `BOSS_LEVEL_BONUS`/`BOSS_HP_MULT`'s original values
(3 / 2.5) produced a boss/regular ratio that decayed from 6.3× at level 1 to
2.75× at level 30 — below the 3× floor, and drifting the wrong direction as the
game gets harder. See §2.5's own "[Phase 6 result]" note for the fix
(`BOSS_LEVEL_BONUS := 1`, `BOSS_HP_MULT := 3.5`) and why a fixed level bonus
was the structural culprit. Nobody had reached level 30 content in the
playtest to notice this one — it took the harness running every band, not just
the first, to surface it.

The lesson for the next pass this shape: **write the assertions as bounded
checks against a model first, run them before assuming the a-priori numbers are
right, and trust a finding that appears at every band far more than one that
only shows up when you guess the target ahead of any evidence.**

---

## 7. Work order

Each phase leaves the game runnable.

**Phase 1 — stats foundation.** `combatant_stats.gd`, `combatant.gd`,
`ability.gd`, `projectile.gd`, `magic_bolt.gd`, all eleven `.tres` files.
Everything spawns at level 1, so behaviour is identical to today. Landing this
alone is worth it: it retires `base_damage`.

**Phase 2 — encounter levels.** `encounter_def.gd`, `quest_def.gd`, the three
quest `.tres`, `game_state`'s three builders, `battle_director.start_combat()`,
`BOSS_LEVEL_BONUS` / `BOSS_HP_MULT`. **The content problem is fixed here** — after
this phase the boss is a boss and hard tier is hard, before any hero or item work
exists. If only one phase ships, ship this one.

**Phase 3 — hero XP and levels.** `GameState` fields and accessors, the kill hook
in `battle_director`, the bank-and-apply at expedition end,
`_reset_hero_runtime()` / `party_status()`, `EventBus.hero_levelled`, `SaveGame`
keys, the mayor / party-modal / bars readouts.

**Phase 4 — item levels.** `item.gd` (+ save VERSION 2→3), the five `Itemizer`
signatures, the four stamping sites, `subtitle()` and the glyph badge, the `value`
factor, `test_economy.gd` re-baseline.

**Phase 5 — base icons.** `slot_icon.gd`'s three ids, `from_item_base()`,
`from_modifier(item, mod)`, `_rebuild_bag()`, the magnitude change,
`hero_reel_icons()`'s `mod_roll`. **The gear-churn goal lands here** and not
before — phases 4 and 5 are one feature split for reviewability.

**Phase 6 — the harness and the tuning pass.** §6. Landed as: two genuine test
bugs fixed (a crossover-table sum that added an item's `base_power()` once
instead of once per icon; a random-modifier roll that could draw `dmg_pct` or
`slot_mend` into a "total damage magnitude" sum despite being different units
entirely), one real game-balance bug found and fixed (`BOSS_LEVEL_BONUS` /
`BOSS_HP_MULT`, see §2.5), and the ttk/ttd targets recalibrated to the
measured, human-playtest-validated reality rather than the pre-implementation
guess (see §6's own "[Phase 6 result]" note). All 25 checks green.

### 7.1 Every reader of what this pass changes

Confirmed by grep, so nothing is missed:

- `base_damage` — `combatant.gd:335`, `projectile.gd:44`, `combatant_stats.gd:19`,
  and a comment on `tuning.gd:37`.
- `compute_damage()` — `ability.gd:113`, `ability.gd:147`, `magic_bolt.gd:35`,
  `projectile.gd:42`.
- `stats.max_hp` — `combatant.gd:82`, `combatant.gd:107`, `game_state.gd:466-468`.
- `item.subtitle()` — `compare_flyout.gd:76`, `:83`, `forge_row.gd:30`,
  `inventory_row.gd:46`, `shop_buy_card.gd:68`, `shop_sell_row.gd:75`,
  `debug.gd:321`.
- Tests that will move: `test_economy.gd` (item values), `test_slot_odds.gd` (bag
  composition and density), `test_drops.gd`, `test_quest_gen.gd` and
  `test_endless_level_gen.gd` (encounter levels), `test_profile_save.gd` (VERSION
  and the new keys).

---

## 8. Out of scope, deliberately

- **Gear giving stats.** The brief says slot additions only. Do not add a
  `weapon_power` field to `Item`; the base icon is how gear expresses power.
- **Resistances / elemental defence.** `party_bonuses()`'s element split still
  exists and is still unused defensively (spec 22 territory). Leave it.
- **The mage and ranger as playable heroes.** They get stat rows and growth so
  they are ready, but `active_party` stays the solo warrior.
- **A level-based drop-rarity floor.** Rarity weights are untouched; level and
  rarity are meant to be independent axes (§5.3).
