# Sir Fish — Demo Scope

> **Status: in progress (opened 2026-11-02).** This is the scope lock for the Steam Next
> Fest demo, [#226](https://github.com/DarkCascade/Sir-Fish/issues/226), due 2026-11-20.
> When it is done it lists which quests, areas, heroes and systems ship, and everything
> else is cut. Today it settles the demo's last act, the mist, and where the demo ends
> ([#249](https://github.com/DarkCascade/Sir-Fish/issues/249)). The rest is listed under
> "Still to lock".
>
> The roadmap is the plan and the GitHub board is the status. This doc says what is in the
> demo. The reasons for each call are recorded here and in the backlog doc (§11, and
> decisions 11.5 to 11.7 in the §8 table).

---

## 1. The demo

A new profile plays from a solo warrior arriving in Mossmere to the gate of the castle on
the ridge:

1. **The bandit-camps tutorial** (backlog §9, roadmap M4). A solo warrior in a town with
   no services ends with a three-hero party in a staffed town. The captain is its final
   boss.
2. **The mist expedition.** The captain's defeat points the party up the violet trail
   toward the castle. That trail is one Rune Floor expedition, ending in a boss.
3. **The castle gate.** Beating the boss reaches the gate. The ending card and the
   wishlist screen follow ([#250](https://github.com/DarkCascade/Sir-Fish/issues/250)).

Before 2026-11-02 the bandit-camps arc was the whole of the demo. The mist gives the
tutorial somewhere to lead, and it is already on the screen players see most. The town
painting (`assets/town-with-purple-mist.png`) shows a dark castle on the ridge, a violet
trail of mist winding down from it to Mossmere's gate, and violet crystals in the woods on
both sides. Nothing in the game explains any of it yet.

---

## 2. Decided

### 11.5 The mist is wild slot magic (2026-11-02)

The violet mist is raw slot magic. It is the same magic the Gilded Guppy runs on and that
Sir Fish's amulet focuses into the Rune Floor (decision 10.1). Something in the castle is
spilling it unchecked. It runs down the trail toward Mossmere, crystallises in the woods,
and turns the creatures it soaks into shadow.

- **Why:** it is the only choice where the setting, the Rune Floor and the slot machine
  tell one story. The board is made of this magic, so the place where it runs wild is the
  natural place for the board itself to misbehave (the stretch goal, §4). The game already
  uses this violet for magic: the reliquary modals sit in violet mist
  (`reliquary_mist.gdshader`).
- **What it explains along the way:**
  - **The shadow monster:** what the mist makes of a creature. Its rework
    ([#91](https://github.com/DarkCascade/Sir-Fish/issues/91), M7) becomes the mist's
    native enemy.
  - **The violet crystals** in the painting: mist that has set.
  - **Floating islands, at least in the mist:** in the mist the board's own magic hangs in
    the air, which gives Q1's option A a reason there
    ([#218](https://github.com/DarkCascade/Sir-Fish/issues/218) still decides the other
    biomes).
- **Not chosen:**
  - **A curse spreading from the castle.** Simpler, but it gives the slot nothing to do
    with the mist. Its best piece, the mist turning creatures to shadow, is kept above.
  - **Something personal to Sir Fish** as the mist's explanation. A short demo can't
    explain it, and it is a stronger pull toward the full game. It is kept as a story
    beat instead (§3).

### 11.6 One expedition and a boss (2026-11-02)

The mist part of the demo is one Rune Floor expedition up the trail, ending in a boss. It
is not a second region with its own quest board.

- **Why:** the schedule. The tutorial is due 2027-02-26 (M4) and the demo has to be
  feature-complete by 2027-04-15. Loot and holds (M5), audio (M6), the art pass (M7) and
  the ending screen (M8) already sit between the two. A short final act fits there. A
  second region does not.
- **Built from what exists wherever possible:**
  - **Fights:** the Rune Floor's encounter, loot, shop and boss islands (M1).
  - **The backdrop:** a mist surround on the per-biome hook (`rune_floor_surround.gd`,
    [#216](https://github.com/DarkCascade/Sir-Fish/issues/216)). The Rune Floor already
    plays in a dark void with fog and floating motes, so violet fog and crystal islets
    are the cheapest second backdrop the game can have.
  - **Enemies:** the reworked shadow monster, plus mist-touched versions of enemies the
    game already has, made with a tint shader rather than new models. The only new model
    is the boss, which costs Meshy credits.
- **Tracked as** [#256](https://github.com/DarkCascade/Sir-Fish/issues/256) (the
  expedition), [#257](https://github.com/DarkCascade/Sir-Fish/issues/257) (the surround),
  [#258](https://github.com/DarkCascade/Sir-Fish/issues/258) (the boss) and
  [#259](https://github.com/DarkCascade/Sir-Fish/issues/259) (the enemies), all in M8.
- **Left open:** the fight count and the level band. They are set against the captain's
  band when the tutorial structure is decided
  ([#198](https://github.com/DarkCascade/Sir-Fish/issues/198)). Also open: what the boss
  is, and the trail's name.

### 11.7 The demo ends at the castle gate (2026-11-02)

Answers [#249](https://github.com/DarkCascade/Sir-Fish/issues/249) ("the end of the
bandit-camps arc, or the first area boss"). The answer is the first area boss: the mist
boss guards the gate, and beating it ends the demo.

- **Why:** an ending in front of a closed gate, with the source of the mist on the other
  side, is the strongest moment to ask for a wishlist. Ending on the captain would wrap the
  bandit story up and leave the mist as background.
- **Then:** the ending card and the wishlist screen
  ([#250](https://github.com/DarkCascade/Sir-Fish/issues/250)).

---

## 3. Story beat to keep: the castle is personal to Sir Fish

Not locked. This was considered as the mist's explanation and kept as a beat instead
(11.5). The idea is that the castle is tied to Sir Fish himself: perhaps the castle that
knighted him, and where his amulet came from.

It fits wild slot magic rather than competing with it. The amulet is the lens that focuses
the mist's magic into the board (10.1), so a link between the amulet and the castle is
already half there.

Where it could land:

- **At the gate, as the demo's last shot.** The amulet glows in answer to the gate, or the
  gate opens a crack for it. Then the ending card. It hints at the link without
  explaining it, and the full game pays it off.
- **In the hand-off from the captain.** Someone recognises the amulet's crest from the
  castle's banners.

To decide with the tutorial dialogue
([#242](https://github.com/DarkCascade/Sir-Fish/issues/242)), once the dialogue system is
chosen ([#120](https://github.com/DarkCascade/Sir-Fish/issues/120)).

---

## 4. Stretch goal: a mist-affected reel

[#260](https://github.com/DarkCascade/Sir-Fish/issues/260). Not in the demo's committed
scope. It ships only if the committed work is on schedule, most likely paid for by a
shorter bandit arc ([#198](https://github.com/DarkCascade/Sir-Fish/issues/198)).

**The idea:** in the mist expedition, the mist reaches the board. Some cells fog over each
spin and land a mist rune instead of a party icon. This makes the slot itself the mist
act's new thing to deal with. It also gives the store page a hook for the last act, and a
clip of the board fogging over shows it in a few silent seconds.

**Candidate rules**, none chosen:

- **A wild that picks no side.** A mist rune completes a payline for any category, like a
  slot wild, but whatever its line triggers also does something for the mist, such as
  charging the enemies or healing them. Wild slot magic makes the pun literal.
- **A dead cell the enemies own.** A misted cell pays out to the enemies when a line runs
  through it.
- **A swing either way.** A mist rune resolves at random to a jackpot-sized effect or a
  backfire.

**It pairs with hold-and-respin** (decision 7.6,
[#101](https://github.com/DarkCascade/Sir-Fish/issues/101), M5). Holding a clean reel
against the mist, or holding a mist rune that is about to complete a line, is the kind of
decision hold-and-respin needs. Build it after holds, not before.

**Cost:** a new board icon and its glyph, its resolution in the slot and payline code, its
balance against the mist band, and a sim and tests to match. It is the only new mechanic in
the demo's last act, which is why it is a stretch goal.

---

## 5. Already settled for the demo

Settled before this doc, recorded here so the scope is in one place:

- **The Slotworks ships Upgrades and Holds only** (decision 11.2). Tuning
  ([#173](https://github.com/DarkCascade/Sir-Fish/issues/173)) and Charms
  ([#174](https://github.com/DarkCascade/Sir-Fish/issues/174)) wait for after the fest.
- **The board's choice between spins is hold-and-respin** (decisions 7.6 and 11.4,
  [#101](https://github.com/DarkCascade/Sir-Fish/issues/101)).
- **The Rune Floor is the default expedition style** (decision 10.2).
- **The heroes:** the warrior, then the ranger and the mage, freed in the tutorial (backlog
  §9).

---

## 6. Still to lock for #226

- **The tutorial's structure:** camps, order, gates, and which services start closed
  ([#198](https://github.com/DarkCascade/Sir-Fish/issues/198)). The mist expedition's
  level band hangs off the captain's.
- **The regular quests.** The Shallow, Deep and Heart of the Wood
  (`resources/quests/easy`, `medium`, `hard`): in the demo, reworked into the arc, or cut.
- **Endless mode:** in the demo or cut.
- **The console expedition style:** selectable or not
  ([#220](https://github.com/DarkCascade/Sir-Fish/issues/220), Q3).
- **Areas:** Mossmere, wherever the bandit camps sit (the Endless Wood), and the mist
  trail. Whether anything else is reachable.
- **A level cap** for the demo, which follows from the two above.
