# Sir Fish — Class Idea: Board Rules

**Status: parked for later consideration. Not a spec.**

Decision D1 (12 Sep 2026) chose the **Executor** model for Content Phase 1. This note
records the road not taken, so it can be picked back up without re-deriving it. Nothing
here is designed, balanced or costed.

---

## The idea in a paragraph

Under Executor, a class **owns** icon kinds on the slot board: the front line swings
the damage icons, the ranger looses the chain, the mage mends. Classes differ by *who
acts*. Under **Board Rules**, a living class also changes *how the board resolves*. A
mage does not just throw the chain bolt; its presence rewrites which icons become chain
bolts. The board stops being a fixed resolution loop with interchangeable actors, and
becomes a loop each party member bends.

---

## Why it was not chosen now

- **Cost.** `SlotMachine._resolve_board()` is one linear pass today: a `MULT` pre-sum,
  then per-cell resolution with the payline repeat, then the aggregated swing and block
  grant. Rules need that loop opened into hook points. That is a refactor of the core
  loop, not an addition to it.
- **Legibility.** The board is the game's primary readout. Every rule is something the
  player must learn to read off nine cells mid-fight. Executor adds no new reading at
  all; every icon still does what it did.
- **Sequencing.** Executor gets three mechanically distinct classes on the loop as it
  stands. Board rules are cheaper to design once those three have been played and it is
  clear what they lack.

---

## Why it will probably come back: the executor ceiling

This is the most important part of this note.

Executor distinguishes classes by which icon kinds they own. `SlotIcon.Kind` has five
non-blank kinds, and one of them, `MULT`, is summed before resolution and has no actor.
That leaves **four executable kinds**.

| Kind | Resolves as | Actor today | Phase 1 executor |
|---|---|---|---|
| `DAMAGE` | summed into one swing | first living hero | warrior |
| `BLOCK` | summed into one temp-armor grant | none | warrior |
| `DAMAGE_ALL` | a chain bolt on every enemy | none (`source` is null) | ranger |
| `HEAL` | a mend on the lowest-HP hero | none | mage |

Three classes take those four. **A fourth class can take one from the warrior. A fifth
has nothing left to own.** Decision D3 expects more classes, so the ceiling is not
hypothetical.

Two ways past it, not mutually exclusive:

1. **Add icon kinds.** A new entry in `Itemizer.MODIFIERS` resolving to a new `Kind`.
   Cheap per kind, but each is one more thing on the board to read.
2. **Board rules.** This note. A fifth class differentiates by what it *changes*, not
   by what it *owns*.

**Revisit trigger.** Either of these:

- A new class is being designed and no unowned executable kind is left.
- Playtesting shows the executor classes read as one class with different animations.

---

## Shape, if it comes back

### Hook points

A resolution pipeline with four stages, each accepting rules from living party members.
The examples show what a stage *can* do; none of them is a proposal.

| Stage | Receives | Can do | Illustration only |
|---|---|---|---|
| Deal | the nine drawn icons | reorder or transform before anything resolves | the top row resolves first |
| Per icon | one icon and its cell | change kind, magnitude or target | a `DAMAGE` icon beside a `HEAL` icon becomes `DAMAGE_ALL` |
| Aggregate | the summed swing and block totals | modify totals | each `BLOCK` icon also adds its roll to the swing |
| After | the resolved spin | trigger follow-ups | overheal converts to temp armor |

### Data

```gdscript
class_name BoardRule extends Resource
enum Stage { DEAL, PER_ICON, AGGREGATE, AFTER }
@export var stage: Stage = Stage.PER_ICON
func apply(ctx: BoardContext) -> void: pass

# ClassDef grows one field. Executor stays the base layer.
@export var board_rules: Array[BoardRule] = []
```

Compatible with Executor by construction: `ClassDef.executes` still says who acts, and
`board_rules` layers on top. Phase 1 ships without the field; adding it later is purely
additive and touches no shipped class resource.

### Hazards to design around

- **Rule interaction.** Two classes transforming the same icon need a defined order.
  Roster order is the natural tie-break, and after D3 it is already authored data.
- **The payline bonus.** A centre-row triple resolves twice today. Decide whether a
  Deal-stage rule may create or break a triple, or whether triples are judged on the
  board as dealt.
- **The Debug slot override.** `Debug.take_slot_override()` forces a whole board. Rules
  must run after it, or forced boards stop being useful for testing rules.
- **Determinism.** `test_slot_odds.gd` exercises the real draw through the seeded
  `RNG`. Any rule that rolls must use `RNG`, never the global generator.
- **Dead members.** A rule belongs to a living hero. Decide whether it drops out on the
  spin its hero dies, matching how `_living_hero_classes()` already drops a dead hero's
  innate icon on the next spin.

---

## What would have to be true to start

1. Executor has shipped, and three classes have been played.
2. There is a concrete class that cannot be differentiated by ownership alone.
3. `_resolve_board()` has a test pinning today's resolution order, so opening it up is
   measurable rather than a matter of feel.
