# Sir Fish — Slot Phase 2: the icon bag

**An implementation prompt.** This is not a spec you must obey to the letter; it
is a brief with the shape of the answer already decided. Where it names a file,
a constant or a number, that is a real thing in this repo — go read it before
you change it.

---

## What you are building

Replace the Vegas-style 3-reel match-to-win slot with a *Luck be a Landlord*
style board: a bag of icons the player builds out of their gear, drawn onto a
3x3 board, where **every icon resolves its own effect independently**. The
payline survives as a bonus, not as the win condition.

The one-line version: **gear stops adding numbers to a payout and starts adding
symbols to the reel.**

---

## Read these first

| file | why |
|---|---|
| `scripts/console/slot_machine.gd` | the current model: `_one_spin()`, `_roll_targets()`, `evaluate()`, `_pay_out()` and the three `_pay_*` functions |
| `scripts/console/slot_reel.gd` | reel geometry. **Five** `SlotSymbol` cells are authored per reel; `_visible_range = 2`; the payline is `_cells[2]`; the window clips to three |
| `scripts/autoload/itemizer.gd` | `MODIFIERS` (lines ~38-50), `RARITY_MOD_COUNT`, `_roll_modifiers()`, `forge()` |
| `scripts/autoload/tuning.gd` | `enum Sym`, `SLOT_STRIP`, `SLOT_REEL_STOPS`, all `SLOT_*` payout constants |
| `scripts/autoload/game_state.gd` | `party_bonuses()` — the aggregator this change largely dismantles |
| `scripts/console/bonus_strip.gd` | read its header before deleting it; it explains the legibility duty you are inheriting |

---

## 1. The board

You already have a 3x3 board on screen and you are only scoring one row of it.

- Scoring cells are `_cells[1]`, `_cells[2]`, `_cells[3]` on each of the three
  reels — offsets -1 / 0 / +1 from the payline. That is **nine scoring cells**.
- `_cells[0]` and `_cells[4]` are scroll bleed, clipped by the reel window.
  They are never scored and need no art changes.
- No cabinet, layout or texture work is required for this. Do not resize the
  machine.

## 2. The bag (fork 1)

Retire the fixed 27-stop `SLOT_STRIP`. The reel is a **bag**, rebuilt whenever
the party's icon set changes.

```
bag = [one icon per living hero]
    + [one icon per equipped item modifier]
    + (BLANK_PAD blanks)
```

Each spin draws **nine icons without replacement** and lays them onto the board.
Draw-without-replacement is deliberate and load-bearing: it makes board
composition near-deterministic, so a cold streak can never leave the party with
no output at all — which matters enormously now that the slot carries the
party's whole offensive contribution.

- `BLANK_PAD` starts at **12** and is reduced by upgrades (see §6) to a floor
  of **4**.
- If the bag is ever smaller than nine, pad with blanks up to nine.
- Adding an icon always raises total board density
  (`icons_drawn ≈ icons * 9 / bag_size`) while slightly thinning each *specific*
  icon's appearance rate. That tension is intended — it is what makes "go tall
  on one icon" a real decision against "go wide".

Target density arc, for calibration:

| stage | icons | bag | icons/spin |
|---|---|---|---|
| start (1 hero, 3 Uncommons) | ~4 | 16 | ~2.3 |
| mid (3 Magic) | ~7 | 19 | ~3.3 |
| late (3 Enhanced, blanks bought down) | ~13 | 17 | ~6.9 |

**Never let the bag be empty of icons.** Every living hero contributes one
innate icon regardless of gear — warrior a damage icon, priest a heal icon,
ranger a damage icon. This gives a floor, and it reconnects party composition to
the slot.

## 3. Icons and how they resolve (fork 2)

The icon vocabulary *is* `Itemizer.MODIFIERS`. One equipped modifier = one icon
in the bag. **The art already exists** — `assets/ui/reliquary/chip_*.png`, one
PNG per modifier id, currently drawn by the bonus strip. Reuse those as the slot
symbols.

| modifier id | icon | resolves as |
|---|---|---|
| `dmg_flat` | sword | damage to one enemy, for its rolled value |
| `dmg_pct` | chevron | **multiplier** — adds its rolled % to every damage icon resolving this spin |
| `elem_fire` | fire | damage, fire-tinted number |
| `elem_ice` | ice | damage, ice-tinted number |
| `elem_light` | bolt | damage, lightning-tinted number |
| `slot_bolt` | chain | damage to **all** enemies |
| `slot_mend` | plus | heals the lowest-HP living hero for its rolled % of max |
| `slot_purse` | coin | **removed from the pool entirely — see fork 3** |

Resolution rules:

- Every non-blank cell resolves, **independently**, once per spin.
- Resolve multiplier icons (`dmg_pct`) first; they modify the damage icons in
  the same spin only. They do not persist.
- Resolve left-to-right, top-to-bottom, staggered by `Tuning.AOE_STAGGER` so the
  board reads as a sequence rather than a single flash.
- An icon's magnitude is **the value already rolled on the item that supplied
  it** (`modifiers[i]["roll"]`). Do not invent a second magnitude table.

**The payline bonus.** Keep `evaluate()` and the whole celebration path. When
the centre row (`_cells[2]` on all three reels) shows three of the same icon,
those three resolve **twice**. That preserves the jackpot moment, the banner,
the confetti and the cabinet shake for very little code. Two-of-a-kind no longer
means anything on its own — every icon already paid.

## 4. Rarity and gear (fork 4)

`RARITY_MOD_COUNT := [0, 1, 2, 3, 4]` already exists and is the whole progression
curve. Use it as-is:

| rarity | modifiers | icons contributed |
|---|---|---|
| Common | 0 | **0** |
| Uncommon | 1 | 1 |
| Magic | 2 | 2 |
| Rare | 3 | 3 |
| Enhanced | 4 | 4 |

- Three equip slots means a **3 → 12 icon** curve from gear.
- **Count is the primary driver of rarity's power.** Do not add a per-rarity
  potency scalar to the `roll` ranges; leave that lever unpulled for now.
- Potency comes from exactly one place, which already exists: the Enhanced rung
  rolls its modifier at `Tuning.FORGE_ENHANCED_MULT` (x2) magnitude and carries
  the `enhanced: true` marker. Keep it, and make an Enhanced icon visually
  distinct on the board.
- A Common item now contributes literally nothing to the slot. That is correct
  and intended; it is what the blacksmith's "Scrap All Common" and "Sell All
  Common" buttons are for.
- `Itemizer.forge()` walking an item one rarity step adds a modifier — which now
  means **it adds an icon to the reel**. Make that visible. The forge has never
  had a legible payoff and this is it.

## 5. Gold leaves the slot (fork 3)

The slot no longer produces gold, in any form.

- Remove `slot_purse` from `Itemizer.MODIFIERS`. The pool drops from 8 ids to 7,
  which still comfortably exceeds `RARITY_MOD_COUNT`'s max of 4 distinct picks.
- **Migration matters.** Saved profiles and `forge_stock` on disk carry items
  holding `slot_purse` modifiers (`Item.from_dict` reads them verbatim). An
  unrecognised modifier id must resolve to *no icon* and must not crash, warn in
  a loop, or break `SaveGame.load_profile()`. Do not bump the save version for
  this; tolerate it.
- Delete `Tuning.SLOT_PAY_2_GOLD`, `SLOT_PAY_3_GOLD` and
  `SlotMachine._pay_gold()`.
- **Gold now comes from exactly two places:** enemy drops
  (`Tuning.ENEMY_GOLD_DROP`, `BOSS_LOOT_MULT`, and the loot pickup path) and
  selling items (`Item.sell_price()`, the shop's and the blacksmith's Sell tabs).
  Quest rewards (`QuestDef.gold_reward`) continue as they are.
- This removes roughly half the run's income. **You must re-tune
  `Tuning.ENEMY_GOLD_DROP` upward** so a run still affords shop and blacksmith
  prices. See §8 for the assertions that pin the old curve.

## 6. Upgrades

The tray has exactly three buttons (`Upgrades.ORDER`, and `UpgradeButton0/1/2`
in `scenes/console/console.tscn`). Keep it at three so no UI work is needed.

| id | before | after |
|---|---|---|
| `quick_reels` | reels spin +X% faster | **unchanged** — and now more valuable, since more spins means more resolutions |
| `overcharge` | Lightning pays +X% | **all damage icons pay +X%** |
| `fat_purse` | Gold pays +X% | **retire.** Replace with `polish`: "Remove X blanks from the reel", reducing `BLANK_PAD` toward its floor of 4 |

Delete `Upgrades.fat_purse_mult()` and its caller in `_pay_gold()`.

## 7. What to delete

- `scripts/console/bonus_strip.gd` and `scenes/console/bonus_strip.tscn`
- `scripts/overlay/bonus_panel.gd` and `scenes/overlay/bonus_panel.tscn`
- Their instances in `scenes/main.tscn` and `scenes/modals/inventory_modal.tscn`,
  and any references from `scripts/console/status_panel.gd` and
  `scripts/console/upgrade_tray.gd`
- `Tuning.enum Sym`, `SLOT_STRIP`, `SLOT_REEL_STOPS`, `SLOT_PAY_*_GOLD`,
  `SLOT_HEAL_*_FRACTION`, `SLOT_LIGHTNING_*`
- `SlotMachine._stop_index_for()` and the three `_pay_*` functions

**Before you delete the bonus strip, read its header.** It calls itself *"the
ONLY place a player can see what their inventory is doing."* That duty does not
disappear with the node — something must inherit it. Build the replacement in
the same change; do not ship the deletion bare.

### 7.1 The replacement readout: per-hero icons in the party modal

Put it in **`scripts/modals/party_modal.gd`**, as a third element in each hero's
row, directly under that hero's health bar.

`_member_row()` already builds a `VBoxContainer` per hero containing `top_line`
(name + HP text) and `bar` (a `ProgressBar`). Append an icon strip as the third
child. Requirements:

- Show **that hero's contribution to the bag**: their one innate icon, plus one
  chip per modifier on each of their three equipped items. Draw the chips with
  the same `assets/ui/reliquary/chip_*.png` art the bonus strip used.
- **Show duplicates as separate chips.** Three sword modifiers means three sword
  chips, so the strip is literally a count of what that hero puts in the reel.
  Label each chip with its rolled magnitude.
- **Mark the innate icon as innate** — the player must be able to tell which one
  chip they cannot lose by unequipping.
- Head the strip with the count, e.g. `Reel icons (5)`.
- Grouping by hero *is* the attribution. "Which item gave me this?" is answered
  by the hero owning it plus the three-slot equipped set already visible in the
  forge and inventory modal; you do not need a per-chip source tooltip.

`GameState.party_status()` already returns one dictionary per `active_party`
member and is what `_rebuild()` iterates — extend that payload (or add a
sibling helper) rather than reaching into inventory from the modal.

The modal is rebuilt on every `open()` and is read-only, so no live-update path
is needed.

**Known and accepted limitation:** the HUD's party button is disabled during
COMBAT (`scripts/hud/hud.gd:55` — *"no peeking at HP to time a heal"*). Keep
that lock. This readout answers **composition** — what is in my bag and why —
which is the question the bonus strip actually owned, and which the player asks
between fights. It deliberately does not answer **resolution** — what just fired
on the board this spin. That is a separate problem, already largely solved by
the floating damage numbers and the celebration path, and you should improve it
there (icon pulse on resolve, number colour per icon type), not by unlocking
this modal mid-combat.

## 8. What breaks, concretely

These tests pin the old model and **will fail**. Rewrite them; do not weaken
them into nothing.

- **`tests/test_slot_odds.gd`** — obsolete wholesale. It exhaustively enumerates
  27^3 = 19,683 outcomes and asserts exactly 9,849 wins, plus the strip
  composition (7 LIGHTNING / 7 GOLD / 7 PLUS / 6 BLANK). Replace with a bag test:
  draw-without-replacement is unbiased, board density matches the §2 table at
  each stage, and the bag is never all-blank.
- **`tests/test_economy.gd`** — four assertions die: `P(exactly 2) = 0.1494`,
  `P(exactly 3) = 0.0174`, `expected gold per spin = 6.8`, and *"a full run's ~44
  spins pay roughly 300 gold"*. It also asserts *"at least one card is affordable
  in >= 95% of shops"* and a mean gold-on-hand band of 150-260 at the encounter-3
  shop — **those two are the real targets**. Keep them, and re-tune
  `ENEMY_GOLD_DROP` until they pass again with slot gold gone.
- **`tests/test_upgrades.gd`** — references the retired `fat_purse`.

Other consumers you must not miss:

- `EventBus.slot_payout(kind: String, count: int)` — `kind` is
  `"lightning"|"gold"|"heal"`. **`scripts/console/sir_fish.gd:96`
  (`_on_slot_payout`) drives Sir Fish's cheer/smug reactions off it.** Redefine
  the signal for per-icon resolution and keep the fish reacting; a bigger board
  should make him more expressive, not less.
- `Debug._cmd_slot()` forces a three-symbol payline via `take_slot_override()`,
  clamped `0..3` against the old enum. Rework it to force board contents, and
  keep the harness useful — it is how the slot gets tested without a GPU.
- `scripts/shader_warmup.gd` references slot symbols; check it still warms what
  is actually drawn.

## 9. Derived decisions — flag these to the user

The four forks above were decided by the user. These were **not** — they were
chosen by whoever wrote this prompt. Call them out rather than burying them:

1. Retiring `fat_purse` for `polish` (keeps the tray at three buttons and gives
   blank-removal a home).
2. Deleting `slot_purse` from the modifier pool outright, rather than
   repurposing it into a passive "+gold from kills".
3. One innate icon per living hero, with the class mapping given in §2.

## 10. Definition of done

- A fresh profile fights with ~2-3 icons resolving per spin, and never zero.
- A fully-forged profile fights with ~7, and the difference is *felt*.
- Forging an item visibly adds an icon to the reel.
- Three-of-a-kind on the centre row still triggers the banner, the confetti and
  the cabinet shake, and pays double.
- Gold comes only from kills, sales and quest rewards, and a normal run still
  affords the shop.
- Sir Fish still reacts to good spins.
- The party modal shows each hero's reel icons under their health bar, and the
  count there matches what that hero actually contributes to the bag.
- The full headless suite is green:
  `for f in tests/test_*.tscn; do godot --headless --path . "res://$f"; done`
- No leftover references to `Tuning.Sym`, `SLOT_STRIP`, `bonus_strip` or
  `fat_purse` anywhere in `scripts/`, `scenes/` or `tests/`.

## 11. Deliberately deferred

Do not build these; note them if they become tempting.

- **Adjacency synergy** (an icon boosting its neighbours). This is the real
  *Luck be a Landlord* hook and the natural Phase 3, but it needs a settled icon
  vocabulary first.
- A per-rarity potency scalar on `roll` ranges (see §4).
- Board growth beyond 3x3 as an upgrade.
- Icon removal / bag editing as a player-facing action.
