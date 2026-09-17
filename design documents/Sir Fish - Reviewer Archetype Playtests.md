# Sir Fish — Reviewer Archetype Playtests

**Date:** 2026-09-16
**Build:** branch `mobile-item-card` @ `5ebbb4c`, Godot 4.7-stable
**Harness:** `tools/sim_reviewers.gd` / `.tscn` (headless, seeded, reproducible)

Three reviewer archetypes played from a brand-new profile to hero level 5, each
trying to pick up one of the two recruitable party members along the way.

---

## How these runs were produced

These are **simulated playthroughs against the real game systems**, not hand-written
fiction and not a human play session.

The harness reuses the shipped code for everything that decides an outcome:
`GameState` for profile / expedition / XP / levelling, `Itemizer` for every generated
item, `Item` for prices, `SlotIcon` + `SlotMachine.draw_nine()` for the real slot bag
and board, `Upgrades` for real costs and multipliers, `QuestGenerator` +
`GameState.quest_board_offers()` for the real mayor's board, and the authored
`QuestDef` / `EncounterDef` resources. Combat is a discrete-event numeric resolver
(the same approach `tools/sim_easy_attempts.gd` established) because a real fight
needs a scene tree, AnimationPlayers and a camera.

**The combat model was validated against the live engine**, not assumed. Every boss
number quoted below was read back out of a running game via `execute_game_script`, and
matches the resolver.

**What is a model, not a measurement:** the town / gear / quest *decisions* are a
stated heuristic per archetype. A real player chooses by eye. Change a policy and that
archetype's numbers change. Treat the three columns as three stated play styles played
consistently — not as three real humans.

**Deliberately unmodelled** (all small, all conservative — they make the party slightly
*weaker* than the real game): BLEED's damage-over-time, CLEAVE / RAIN's cross-spin
buff, and per-target animation timing.

---

## Results at a glance

| | Casual Game Lover | Hardcore Gamer | Non-Gamer |
|---|---|---|---|
| Reached level 5 | yes (L6) | yes (L6) | yes (L9) |
| Recruit obtained | **Ranger**, exp 7 | **Mage**, exp 12 | **none** |
| Expeditions | 7 | 12 | 40 (budget exhausted) |
| **Won / wiped** | **1 / 6** | **1 / 11** | **0 / 40** |
| First win | expedition 7 | expedition 12 | never |
| Playtime to L5 | 21m 09s | 14m 44s | 55m 10s |
| — in expedition | 31% | 54% | 37% |
| — town / menus | 55% | 33% | 50% |
| Slot spins watched | 103 | 102 | 281 |
| Inputs (per min) | 126 (6.0) | 203 (13.8) | 211 (3.8) |
| — available mid-fight | 22 | 36 | 9 |
| Items found / equipped | 21 / 8 | 33 / 10 | 92 / 1 |
| Upgrades bought | 15 | 25 | 0 |
| Gold spent / left over | 1527 / 275 | 1954 / 267 | **0 / 3227** |

The single number that dominates every review below: **every archetype lost the
overwhelming majority of its expeditions.** 1 win in 7, 1 in 12, and 0 in 40.

---

## Review 1 — The Casual Game Lover

> *Plays everything. Phone games, cozy games, the lot. Wants easy gameplay with lots
> of things to watch.*

**Score: 6/10 — "The half I wanted is great. The half I got is a brick wall."**

The first ninety seconds are genuinely lovely, and this is the game's real asset. The
reels turn over by themselves, icons pop, a fish reacts in his tank, numbers float off
the enemies, the background scrolls between fights and the party jogs along it. I did
not have to do anything, and that is exactly what I want on the sofa. There is a lot to
watch here and it is well put together.

And then I lost. And lost. And lost. **Six expeditions out of seven ended in a wipe.**

Here is the thing that made it sting: I could not see it coming and I could not do
anything about it. The regular fights are fine — comfortable, even. My party chewed
through them. Then a boss turns up with roughly *nine times* the health of anything
I'd fought, hits about four times harder, and I watched my warrior get taken apart
over about eight seconds while the reels kept cheerfully spinning. I was not playing
badly. I was not playing at all — there is nothing to play. The slots spin themselves.

That is the part I want to be clear about, because it is a design issue and not a
difficulty preference: **when I lose, I have no idea what I was supposed to do
differently.** In a cozy game I expect to be able to fix a loss by fussing — better
hat, different order, one more upgrade. I did fuss. I bought 15 upgrades, forged an
item, kept my gear current, spent 1527 gold. It did not matter, because the upgrades I
bought were **wiped at the start of the next expedition** — they're run-scoped, so
every trip out I was re-buying the same three upgrades from level zero. I did not
realise that for about half an hour.

I spent **55% of my time in town menus** and only 31% actually out on an expedition. For
a game whose whole appeal is watching the reels, that is backwards. The watching part is
the good part, and it is the smaller part.

The one unambiguous high point: I got the Ranger. A second hero showed up in the party,
a second set of icons went into the reel bag, and the board immediately got busier and
more fun to watch. **That is the best moment in the game and it took me seven
expeditions and twenty minutes to reach it.** It should be the tutorial.

**What would move this to an 8:** let me win the first few bosses. Tell me on the quest
board what I am walking into. And please stop deleting my upgrades every run — that is
the thing that made my effort feel fake.

---

## Review 2 — The Hardcore Gamer

> *Plays competitively. Little time for toys. Expects action and flash the moment they
> pick a game up.*

**Score: 4/10 — "An idle game wearing an action game's clothes."**

Let me get the headline out of the way: **there is no gameplay in the combat.** I went
looking for the spin button for a solid minute before I accepted it does not exist. The
slot machine spins on a timer. The heroes attack on a timer. Damage is dealt by whatever
icons happen to land. I am not making decisions during a fight — I am a spectator with a
shop.

I logged **13.8 inputs per minute**, which sounds respectable until you see that only 36
of my 203 total inputs were even *available* during a fight, and every one of those was
"buy an upgrade from the tray." That is the entire interactive surface of combat. Three
buttons, four levels each, and they **reset to zero every single expedition**. I bought
25 upgrades across 12 runs. I did not accumulate anything. I bought the same upgrade
ladder over and over.

So: no action, no execution, no build. What's left is optimisation, and I'll give the
game this — the gear layer is real. Items feed icons into the reel bag, rarity and level
drive Power, the forge upgrades rarity, and a second party member adds a whole second
set of icons. There is a genuine system in there. I found 33 items and equipped 10, and
I could feel the board getting denser. **That loop is good and it is buried.**

Now the actual problem. **I won 1 of 12 expeditions.** Not because I was bad — because
the boss encounter is not tuned to anything. I pulled the numbers:

- A level-1 party (120 HP, ~12 damage per second) gets offered three quests all reading
  "Lv 1–3". Their bosses are **245 HP, 789 HP and 487 HP**.
- The 245 HP one is a fight. The 789 HP one kills me in under ten seconds and takes over
  a minute to chew through.
- **The quest board does not tell me which is which.** It shows a name, a gold reward, a
  level range and an encounter count. The boss is invisible until I'm standing in front
  of it.

That is not difficulty. That is a coin flip I'm not allowed to see. A competitive player
can accept a hard fight; what I cannot accept is a hard fight I had no information to
prepare for and no inputs to fight with.

And it does not converge. At party level 8 I'd have 414 HP against a 1895 HP boss hitting
for 76. **The boss curve outruns the hero curve at every band**, because boss HP multiplies
both the base *and* the per-level growth by 3.5 and then adds a level on top.

The kicker: **losing is nearly free.** You keep the XP from everything you killed, you
keep your gold and scrap, you get healed to half, and only unequipped loot is lost. So
the optimal strategy — the one I converged on without meaning to — is to **farm the trash
encounters and deliberately eat the boss.** I levelled from 1 to 6 while winning a single
expedition. When suiciding into the boss is the efficient play, the reward structure is
inverted.

**What would move this to a 7:** show me the boss on the quest board. Make upgrades
persist so there's a build. And give me *one* real decision during a fight — hold a reel,
spend a resource, pick a target, anything.

---

## Review 3 — The Non-Gamer

> *Has a phone. Doesn't really play games. Doesn't really get it, and isn't going to put
> significant time into a title.*

**Score: 2/10 — "I played for nearly an hour, never won once, and I still don't know what
I did wrong."**

I want to be fair, because I am not this game's audience and I know it. But I think what
happened to me is worth writing down, because I do not think the game noticed I was
struggling.

**I played 40 expeditions. I won zero.** Not one. I reached level 9 — the game kept
telling me I was levelling up — *entirely by losing*. I would go out, kill some small
monsters, reach the big one at the end, die, and come back a bit stronger. For the better
part of an hour I genuinely believed I was making progress, because the number next to my
character kept going up. I was not making progress. I was on a treadmill and the "level
up" message was lying to me about it.

Here is what I did not do, because nobody told me to:

- I never bought an upgrade. There are apparently three of them on the machine at the
  bottom. I did not know they were buttons. They look like part of the cabinet.
- I never changed my equipment. I picked up **92 items** over the hour. I equipped
  **one**, and only because the game did it for me automatically when a slot was empty.
  I did not know there was a difference between the items. They have names like "Sullen
  Longsword" and a lot of small symbols on them.
- I never went to the blacksmith or the forge. I did not know what scrap was for.
- **I finished with 3227 gold and had spent none of it.** I did not know what gold was
  for either.

So I walked into every boss with the sword the game gave me at the start, an hour
earlier, while the bosses got bigger every time.

The two things I'd genuinely say are nice: the slot machine is pleasant to look at and I
liked that it played itself, and the little fish in the tank is charming. **That's real
— the automatic part is what kept me there for 40 tries.** A game that plays itself is
exactly the kind of thing I'll leave running.

But I never got a party member. I kept taking the quest about the ranger and her bow
because it was the only one with a *story* on it, and I lost it every time, so she never
joined. I was told a second character existed and I never saw one.

And there was **almost nothing to do**. I made 211 inputs in 55 minutes — under four a
minute — and **nine** of those were things I could do while a fight was happening. I
spent half my time in menus I didn't understand and the other half watching a machine
play itself badly on my behalf.

**What would have saved this:** tell me when I'm about to walk into something that will
kill me. Point at the upgrade buttons once. And when I pick up a sword that's better than
mine, just put it on — or at least put a dot on the bag icon so I know to look.

---

## Findings for the team

Ordered by how much they hurt, across all three archetypes.

### 1. Boss encounters are unwinnable at their own advertised level band — **critical**

Verified live, not inferred. `Tuning.BOSS_HP_MULT = 3.5` scales an enemy's base HP *and*
its `hp_per_level` growth, then `BOSS_LEVEL_BONUS` adds a level on top. Measured, with a
starter party at each band:

| Party level | Hero HP | Boss seen | Boss HP | Boss power |
|---|---|---|---|---|
| 1 | 120 | skeleton_minion L4 | 245 | 12 |
| 1 | 120 | skeleton_mage L4 | 487 | 36 |
| 1 | 120 | bandit_officer L4 | **789** | **34** |
| 3 | 204 | bandit_officer L6 | **1105** | 46 |
| 5 | 288 | skeleton_mage L8 | 879 | 60 |
| 8 | 414 | bandit_officer L11 | **1895** | **76** |

The authored `easy.tres` — the first quest a fresh profile can accept — ends in a
**1105 HP, 46-power** skeleton warrior. A fresh warrior has **120 HP, 2 armor and deals
about 12 damage per second.** That is ~92 seconds to kill it and ~8 seconds to die. All
three archetypes wiped on essentially every boss.

**Why CI does not catch this.** `tests/test_level_curves.gd` *does* assert on the boss —
but only on its **health**: `ttk_boss / ttk_regular` must sit in a 3–6x band. The easy
boss lands at 4.09x and passes cleanly. The suite's only survivability assertion,
`ttd_party > 6.0`, is computed against `ENEMY_GROUP_SIZE` **regular** enemies at the
band's own level.

**Nothing anywhere checks the party against a boss's damage output.** That is the exact
hole: a boss's `weapon_power` may grow without limit relative to hero HP and every
assertion stays green. A `ttd` check against the boss unit — parallel to the existing
regular-group one — would have failed on day one and is the single highest-value test to
add.

### 2. The quest board hides the only stat that decides the outcome — **high**

`quest_plaque.gd` shows display name, gold reward, level range and encounter count. At
party level 1, three postings all read "Lv 1–3" while hiding bosses of 245, 487 and 789
HP. The 245 is winnable and the 789 is not, and the player cannot distinguish them before
committing several minutes. Every archetype called this out independently.

### 3. Losing is nearly free, so the efficient strategy is to farm trash and suicide into the boss — **high**

A wipe keeps all banked XP (`apply_expedition_xp()` runs win *or* lose), keeps gold and
scrap, heals the party to 50%, and only discards unequipped loot. The non-gamer reached
**level 9 with a 0–40 record.** Progression is decoupled from success, which destroys the
meaning of a win and, for a confused player, actively conceals that they are failing.

### 4. Upgrades are run-scoped, which reads as lost progress — **medium**

`Upgrades.reset()` is called from `GameState.start_expedition()`, so all three upgrades
return to level 0 every expedition. The casual bought 15 and the hardcore 25 — mostly
re-buying the same ladder. Both read it as their effort being deleted. This may well be
the intended design (`upgrades.gd` says "No meta-progression — spec 5.4 is explicit that
these are NOT the forge"), but nothing in the UI communicates "this is a per-run
consumable," so it lands as a bug.

### 5. Combat has no player input at all — **medium, by design, but worth restating**

The slot machine spins on its own timer from `_on_combat_started`. There is no spin
button. The entire in-combat interactive surface is the three-button upgrade tray, plus
one blocking shop modal per expedition. The casual loved this; the hardcore rejected the
game over it. That split is fine and expected — but it means **the upgrade tray is
carrying the whole weight of in-combat agency**, and the non-gamer never even recognised
it as interactive.

### 6. Fixed during this pass: the Ranger could never be recruited — **was critical**

`resources/reward_extras/recruit_ranger.tres` set three properties that **do not exist on
`RecruitRewardExtra`**:

```
class_id   = &"ranger"     →  should be hero_class
weapon_type = &"bow"       →  should be token_weapon_type
armor_type  = &"helm"      →  no such export; dropped
```

Godot silently accepts unknown properties in a `.tres`, so the resource loaded with
`hero_class = &""` and `grant()` early-returned. **The ranger could never join the party
under any circumstances**, and because `mayor_office._already_recruited()` filters on
`hero_class`, the quest was also re-offered forever after being "completed."

Corrected to the real export names and verified live: `party after grant:
[&"warrior", &"ranger"]`, and the board now correctly hides the quest afterwards. Compare
`recruit_mage.tres`, which was always correct — that asymmetry is what made it findable.

**Still outstanding on that quest** (not fixed here, flagging only):
- `collect_ranger_bow.tres` has no `target_weapon_type`, so its objective can never
  complete; there is no authored bow relic, and `ranger_recruit.tres` has no
  `guaranteed_boss_drop`. The quest is only completable via
  `RunController._next_encounter()`'s "ran out of encounters" fallback, which grants
  victory **without checking objectives at all**. The bow in the quest text is currently
  decorative.
- `mayor_office._load_authored_quests()` computes `var hero := GameState.hero_level()`
  and never uses it, so `ranger_recruit.unlock_level = 3` is not enforced.

### 7. Pre-existing: `tools/sim_easy_attempts.gd` is broken — **low**

It calls `GameState.day_phase`, `GameState.DayPhase`, `meal_eaten_today`,
`resolve_night()` and `night_inn_cost()`, none of which exist on `GameState` any more. It
still exits 0 and prints a confident, meaningless `mean 0.00`. Either update it to the
current API or delete it — as-is it will mislead whoever runs it next.

---

## Reproducing

```bash
godot --headless --path "C:/Projects/Godot/Sir Fish" res://tools/sim_reviewers.tscn
```

Each archetype is seeded (`20260916` / `20260917` / `20260918`), so runs are
reproducible. Policies live in the `ARCHETYPES` constant at the top of
`tools/sim_reviewers.gd` — the three dictionaries are the whole behavioural model and are
meant to be edited.

`tools/sim_probe.gd` / `.tscn` is the throwaway diagnostic used to validate the resolver
against the live engine (fresh-profile stats, per-encounter enemy numbers, mean swing per
spin, recruit-extra binding). Keep or delete as you prefer.
