# Sir Fish — Recruitment Quest Acceptance Test (Outline)

> **Status: idea parked. Nothing is scheduled and no work is to begin.**
> This is a placeholder so the idea is not lost. It is an outline, not a spec — the
> open questions in §5 are genuinely open, and several of them are design calls rather
> than engineering ones.
>
> Filed under `content-phase-1/` because it can only be *run* after Phase 1, but it
> exercises both phases. Move it up a level if it grows into its own initiative.

---

## 1. The idea in one line

A quest whose objective is to retrieve a specific item, and bringing that item home
adds a new member to the party.

---

## 2. Why this is the right acceptance test

It is a single vertical slice that touches nearly every structure both phases build,
and it fails loudly if any of them was done shallowly. Existing precedent: the project
already has `Sir Fish - Town Initiative Acceptance Testing Spec.md` playing this role
for the town work.

- It is **one quest**, so the scope is small enough to actually finish.
- It is **player-visible end to end**, so it cannot be faked in a headless test alone.
- It grows `active_party` from one to two, which is the single event most of the
  current code was never exercised against.

---

## 3. What it exercises

### From Phase 0

| Structure | How this test hits it |
|---|---|
| Content lint test | The new party member must register cleanly with no table edits |
| `AbilityDef` | The recruit's abilities are authored, not a new `match` branch |
| `RigProfile` | The recruit's animations bind without a new registry entry |
| Tags / `EnemyPool` | The quest's roster is composed by tag, not by listing ids |
| **Party keyed by `stats_id`** | **The main event.** Going from one hero to two is what breaks index coupling |
| Save migration | The recruit, and the quest item, must survive a quit |

### From Phase 1

| Structure | How this test hits it |
|---|---|
| `QuestObjective` | First real use of `CollectObjective`, and of a quest that can end early |
| `ClassDef` | The recruit needs a board identity or it is a warrior in a different hat |
| `AreaDef` | The quest is sited somewhere specific |
| `QuestTemplate` | Open question: is this quest authored or generated? See §5 |
| Board persistence | A recruitment quest presumably should not reroll off the board |

---

## 4. Rough player-facing shape

1. The mayor's office offers a quest that names its goal: retrieve a specific thing.
2. The expedition runs normally. The objective's progress is visible somewhere —
   HUD strip or the quest panel, undecided.
3. The item is obtained. Most likely from the boss, possibly from a dedicated
   encounter type.
4. The party returns. `QuestResult` reports the objective met.
5. The new member joins, and appears in the party panel, the slot bag, and the field.

---

## 5. Open questions

Ordered roughly by how much they change the work.

### 5.1 Is the token an `Item` at all?

- `Item.Kind` declares `POTION` and `RELIC` and generates neither. `kind` currently
  means "was generated", and `slot()` carries the real classification.
- A quest token could be the first real `RELIC`, or a separate `QuestItem` concept
  that never enters the sellable inventory.
- **Hazard if it is an `Item`:** `Item.slot()` defaults to `Slot.WEAPON` for an
  unknown `weapon_type`, so a token with no `ITEM_TYPES` row would claim the weapon
  slot if anything ever equipped it.
- **Already safe:** `usable_by()` early-returns empty unless `kind == WEAPON`, so
  `_maybe_auto_equip()` would leave a `RELIC` alone. Verify this still holds after
  Phase 1 Step 2 inverts the item table.

### 5.2 What happens to the token on a wipe?

- `GameState.discard_expedition_loot()` removes **every unequipped item** at index
  `>= _expedition_inventory_mark` on a failed quest. A quest token sitting in
  inventory would be thrown away with the rest of the loot.
- That may well be the right design — fail the quest, lose the prize, run it again.
- But it must be a **decision**, not an accident. If the token should survive, the
  discard loop needs an exemption and `_expedition_inventory_mark`'s contract changes.

### 5.3 When does the recruit actually join?

- **On return to town** — safe. `_reset_hero_runtime()` rebuilds from `active_party`
  at the next `start_expedition()`, so the plumbing already works.
- **Mid-expedition** — dramatic, but `spawn_party()` runs once per run and
  `hero_runtime` is built at expedition start. This needs a real "add a combatant to a
  live fight" path that does not exist.
- Recommend town for the first version, and treat mid-expedition as a later stretch.

### 5.4 Is the token consumed?

Does it stay in inventory as a keepsake, vanish on recruitment, or become the new
member's starting trinket? The last is the most satisfying and the most work.

### 5.5 How does a quest reward a recruit? — *resolved by D2*

D2 settled the reward shape: every quest pays gold, and `QuestDef.reward_extras`
carries anything else. A recruit is a `RecruitRewardExtra` whose `grant()` adds a class
to `active_party`. The recruitment quest still pays gold, like every quest.

Still open: whether `grant()` runs at victory, alongside gold, or is deferred until the
party is back in town. That is §5.3's question in a different form.

### 5.6 Where does the recruit sit in the roster? — *resolved by D3*

The roster becomes derived from hero resources, ordered by an authored `roster_order`
(Content Phase 0, Step 5; moved onto `ClassDef` in Phase 1). A recruit takes its
formation position from its own class resource, and a class outside today's three needs
no code edit to join it.

A correction this surfaced: `PARTY_ORDER` was never what admitted a hero to the party.
It has no production reads at all. A hero joins through `active_party`, which today is
set only by `new_profile()` and the save loader — so a `RecruitRewardExtra` writing
`active_party` would be the **first new path into the party** the game has ever had.

### 5.7 The economy consequences are real and testable

- `night_inn_cost()` and `meal_cost()` both multiply by `active_party.size()`. A second
  member **doubles the nightly bill overnight**.
- `test_economy.gd` pins affordability against a solo party. It will need to be
  re-reasoned, not just re-baselined.
- Free and already correct: `drops_by_class` is cleared per expedition, so a new member
  starts at zero drops and `next_drop_class()`'s catch-up weighting favours them
  automatically. That is a nice, unearned bit of polish.

### 5.8 Can the recruit be equipped at all?

`Itemizer.ITEM_TYPES` gives every armor and trinket row `classes: [&"warrior"]`, with a
comment saying the other classes get their own rows when they return. Until Phase 1
Step 2 inverts that table into `ClassDef.item_types`, a recruit can only ever hold a
weapon. **This test is blocked on that step, not merely improved by it.**

### 5.9 Authored or generated?

A recruitment quest is a one-off with a unique consequence, which argues for authored.
But it is also the ideal proof that authored and generated quests coexist on one board.
Recommend authoring it and letting it sit beside generated offers.

---

## 6. What "passed" would mean

Draft only. Sharpen when this is actually scheduled.

1. The quest appears, states its goal, and the goal is legible before accepting.
2. Objective progress is visible during the expedition and correct on the result screen.
3. The quest can be failed, and failing it has a defined, intentional outcome for the
   token (§5.2).
4. On success the party is two heroes, in town, in the field, and on the board.
5. The second hero contributes distinct icons to the slot bag and is not a warrior
   reskin.
6. Quit and relaunch: the recruit, their level, their gear and the quest's completed
   state all survive.
7. Every pre-existing headless test still passes, with `test_economy.gd` deliberately
   re-reasoned rather than silently re-baselined.
8. **No code was edited to add the recruit — only resources and scenes.** If that is
   false, Phase 0 was not finished.
