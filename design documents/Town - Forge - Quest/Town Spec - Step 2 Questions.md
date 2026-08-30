# Town Spec — Step 2 Implementation Questions

Raised while implementing §14 step 2 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("`SaveGame` plus `Item.to_dict()` / `from_dict()`, and
`test_profile_save.gd`. Still no town.").

**All nine are answered below, and every answer has been folded back into the
spec.** Seven were resolved as implemented. **Q4 was reversed**, and that
reversal is the only code change these answers produced — it also resolves Q8,
which could not have been fixed any other way without violating §13.3. One gap
the questions did not raise is recorded at the bottom as **Q10**; it is the most
destructive bug in the document and it was three steps away from landing.

---

## 1. §2.4's `save_profile()` serializes `GameState.forge_stock`, which does not exist until step 10

**Question:** should `forge_stock` be omitted from the step-2 save dict, or
declared inert on `GameState` now for dict parity?

### Answer — omit it, and the reason generalises into a rule

Omitting is correct, but the argument given for it ("an inert `forge_stock`
invites step 10 to skip thinking about the schema") is a guess about a future
implementer's psychology. There is a better reason, and it is about truth:

**An empty `forge_stock` is not "the blacksmith's stock is empty". It is "there
is no blacksmith."** Serializing it now writes a statement the profile is not
entitled to make. `forge_count = 0`, by contrast (Q2), is simply *true* — this
item has been through the forge zero times.

That is the rule, and it is now in §2.4:

> A field whose zero value is a true statement about the profile may be declared
> early; a field whose zero value is meaningless may not.

It also settles the step-1 precedent cleanly. Q3 of the step-1 doc declared
`scrap`, `expedition_gold` and friends inert, and was right to: every one of
their zero values is true. The precedent was never "declare all future fields
early" — it was "`start_expedition()`'s body is a contract whose value is what it
does not touch", which is specific to that function and does not transfer to a
serialization schema.

The claim about `VERSION` is correct and now written down as policy: adding a
key needs no bump, because `load_profile()` reads through `d.get(key, default)`.
Changing what an existing key *means* does. §2.4 records the one instance of the
latter (`active_party` across §4.5's flip) and notes the build order makes it
moot — nothing writes a save until step 5, which is after step 4.

---

## 2. `to_dict()` / `from_dict()` must cover `forge_count` and the `enhanced` flag, both of which land in step 3

**Question:** pull `forge_count` forward as an inert `@export`, or omit it from
`to_dict()` this step and extend both functions in step 3?

### Answer — pull it forward, as implemented

§2.4 names `forge_count` explicitly as part of the serializer, and a save format
that changes shape between two consecutive steps is worse than one inert field.
Its zero value is true (Q1's rule), so it qualifies.

`enhanced` needs nothing, for the reason given: `duplicate(true)` carries
whatever keys a modifier dictionary holds, so the flag round-trips the day
§10.3 starts setting it, and `test_profile_save.gd`'s assertion on it goes from
vacuous to real with no test edit. That is the right shape for a test to have.

One spec wording fix folded in: §2.4 said the serializer covers *"exactly the
`@export`ed fields **plus** `forge_count`"*, which implies `forge_count` is not
an `@export`. §10.4's own listing shows `@export var forge_count: int = 0`, so
it is one. Reworded to "the `@export`ed fields, `forge_count` among them."

---

## 3. Step 2 forces an edit to `test_profile_expedition.gd`, which §13 does not list as editable

**Question:** is the edit intended, and should the file join §13.2's "Edited"
list?

### Answer — yes to both, and the file is expected to be edited *again*

§2.3 mandates the constant swap and the test pins the old constant; there is no
third option. Added to §13.2 — with the note that this file gets edited **twice**
in this pass (step 2's constants, step 4's `active_party`), because it is the
file that pins whichever seam each step moves. That is the job it was created to
do in step 1, so an edit to it is the visible cost of moving a seam, not churn.

The guard that keeps this honest is now written into §13.2: **an edit to this
file must always be traceable to a named section.** One that is not is a
regression wearing a test's clothes.

---

## 4. `new_profile()` now writes a save from step 2 on, but nothing reads it until step 5

**Question, offered explicitly as a fork:** keep `SaveGame.save_profile()` in
`new_profile()`, or defer it out until step 5?

### Answer — **reversed. Defer it, permanently.** `new_profile()` must never persist

This is the one place the implementation followed §2.3's listing past the point
where it stopped being right, and the questions doc's own framing — "accepted;
this is persistence beginning to work" — reads the situation exactly backwards.
It is not persistence beginning to work. It is **every launch of the game
overwriting the player's save with a fresh profile before anything has had a
chance to load it.**

The chain is short and entirely present in the code today:

```
RunController._ready() → _start_run() → GameState.reset_run()
                                          → new_profile()      # wipes everything
                                          → start_expedition()
```

Three reasons the save call comes out:

1. **§2.4's own "When to save" list never names `new_profile()`.** It names
   town mutations, `start_expedition()`, result banking, and the two
   notifications. §2.3's code listing was the only thing asserting otherwise,
   and §2.4 is the section actually *about* saving. §2.3 yields, exactly as it
   yielded to §13.3 in step-1 Q1.

2. **A new profile is deterministic.** 150 gold, empty inventory, full HP. There
   is no rolled or accumulated state to lose, so re-deriving it after a crash
   costs nothing. Eager persistence buys literally zero here, and the thing it
   costs is in reason 3.

3. **It makes a destructive function persistent.** `new_profile()` wipes; it is
   called unconditionally by `reset_run()`; `reset_run()` is on the boot path.
   A save inside it turns every spurious call into a permanent, irreversible
   wipe. Moving the save to the caller means the one place that *decides* a new
   profile is real — `boot.tscn`, on `load_profile()` returning `false` — is the
   one place that writes it.

**Changed in code**, and pinned: `test_profile_save.gd` now asserts
`new_profile()` writes no file, so re-adding the call fails a test rather than
quietly costing every player their profile.

This does **not** on its own make step 5 safe — see Q10, which is the other half
and the more dangerous one. It makes steps 2–4 safe, which is what buys the time
to fix Q10 properly.

---

## 5. Is `SaveGame._notification()` in scope for step 2?

### Answer — yes, as implemented

§2.4's prose is emphatic and the code has no dependency on a later step. §2.4
now says so explicitly rather than leaving it inferable from a bullet in a list
that the adjacent code listing omits.

---

## 6. "Registered **after** `GameState`" — how strictly?

### Answer — anywhere after is sufficient, and last is actively better

Left as-is. The stated reasoning is right — `SaveGame` has no `_ready()` or
`_init()`, so ordering only has to guarantee `GameState` exists by the time a
save or load is *called*, which is always long after boot.

There is a second reason the questions doc did not find, and it favours where it
landed: **autoloads are freed in reverse registration order.** Registered last,
`SaveGame` is freed *first*, so it can never outlive the `GameState` its
`_notification()` handler reads. Registering it immediately after `GameState` —
the literal reading of §2.4 — would put it later in teardown, which is the
strictly worse direction. §14 step 2 now records this.

Hand-editing `project.godot` to reorder would also violate CLAUDE.md for no gain.

---

## 7. The running editor needs a project reload to see the new autoload

### Answer — correct, and not a code issue

Expected for any autoload added by writing `project.godot`: a filesystem rescan
does not re-register autoloads in the editor's script parser, so **Project →
Reload Current Project** is required. Every headless test process resolves
`SaveGame` correctly, which is the authoritative signal.

The `Class "Item" hides a global script class` line is a `validate_script`
artifact of validating a `class_name` script against itself, present before this
pass. Ignore both.

---

## 8. `test_profile_save.gd` reads and writes the real `user://profile.save`

**Question:** accept, or make `SaveGame.PATH` injectable?

### Answer — the concern is right and was scoped **too narrowly**; fixed without touching `SaveGame`

Do not make `PATH` injectable — a test seam in production code is not worth it
for a dev-only file. But "only the save test clobbers it" is wrong. **Three**
test files reached the profile save:

| test | how | may I edit it? |
|---|---|---|
| `test_profile_save.gd` | directly | yes |
| `test_profile_expedition.gd` | `new_profile()` ×3, `reset_run()` | yes (§13.2) |
| `test_endless_level_gen.gd` | `reset_run()` | **no — §13.3** |

That third row is what makes this interesting: the obvious fix (back up and
restore inside the test) is **unavailable** for the one test that most needs it,
because §13.3 forbids editing it. Any solution living in test files could not
have been complete.

Q4's reversal is what actually solves it. With `new_profile()` no longer saving,
rows 2 and 3 touch no file at all — **with zero edits to either**. Only row 1
still does, deliberately, and that one is guarded:

- `test_support.gd` gains `guard_user_file(path)`, which snapshots the file and
  restores it byte-for-byte in `finish()` — including when the test fails
  partway, since `finish()` is the universal exit point.

**Verified** rather than assumed: a sentinel written to `user://profile.save`
survives `test_profile_save`, `test_profile_expedition` and
`test_endless_level_gen` with an identical MD5.

Two problems, one fix, and the fix was in production code rather than in the
tests — which is usually the sign it was the real problem.

---

## 9. §13.1's round-trip test wants "three equipped items of different **slots**", but slots arrive in step 4

### Answer — the stand-in is correct, as implemented

Distinct `weapon_type` + `rarity` + `equipped_by` exercises every serialized
field without depending on an enum that does not exist. §13.1 now says so, so
step 4 can tighten it to three real `Item.Slot` values without wondering whether
the looser version was an oversight.

---

## 10. Not raised: step 5 destroys the profile the moment it starts loading one

This is worth more than the nine above combined, and it is invisible until the
exact moment persistence starts working — which is the worst possible property
for a data-loss bug.

`RunController._ready()` calls `_start_run()`, whose first line is
`GameState.reset_run()` → `new_profile()` (wipes gold, scrap, inventory) →
`start_expedition()` (which, per §2.4, **saves**).

Today that is harmless: `main.tscn` *is* the game, so the wipe happens before
anything could have been loaded. At step 5, `main.tscn` becomes
`SceneRouter.Place.QUEST` — a destination the player *routes into* from town,
after `boot.tscn` has loaded their profile. So entering a quest wipes the
profile that was just loaded, and `start_expedition()` writes the wipe to disk.
**The player loses everything the first time they accept a quest, and the file
is already overwritten by the time anyone notices.**

Q4's fix keeps this survivable through steps 2–4 — the wipe is memory-only and
a relaunch restores nothing because nothing was ever stored — but it is not a
fix. The fix is that expedition start belongs to the mayor's office (§7.5) and
the router, not to `RunController._ready()`:

- `_start_run()` drops its `reset_run()` call and assumes `GameState.level` is
  already built, which it is: §7.5 calls `start_expedition(quest)` *before*
  routing to `Place.QUEST`.
- `reset_run()` survives exactly as §13.3 requires, as endless mode's dev entry
  point. From step 5 on it is explicitly **a dev path that wipes the profile** —
  which is also precisely what §13.4's `wipe` verb wants, so it gains a second
  legitimate caller rather than becoming vestigial.

Written into §3.1 as a blocking warning, cross-referenced from §14 step 5, and
from §2.3 as the bug the no-persist rule exists to defuse.

---

## What step 2 ships

- **`scripts/autoload/save_game.gd`** — new autoload. `save_profile()`
  (`var_to_str` of an explicit primitive dict at `user://profile.save`,
  `VERSION = 1`), `load_profile()` (returns `false` and mutates nothing on
  missing / unreadable / non-Dictionary / wrong-version input), `_notification()`
  saving on `APPLICATION_PAUSED` / `WM_CLOSE_REQUEST` (Q5).
- **`scripts/data/item.gd`** — `@export var forge_count: int = 0` (Q2);
  `to_dict()` and `static from_dict()`, `modifiers` deep-copied both ways so a
  loaded item never aliases `Itemizer.MODIFIERS`.
- **`scripts/autoload/tuning.gd`** — `PROFILE_STARTING_GOLD := 150`,
  `PROFILE_STARTING_SCRAP := 0`. `STARTING_GOLD` (75) untouched.
- **`scripts/autoload/game_state.gd`** — `new_profile()` uses the §11 constants
  and **does not save** (Q4).
- **`project.godot`** — `SaveGame` autoload registered last (Q6).
- **`tests/test_support.gd`** — `guard_user_file()` + byte-exact restore in
  `finish()` (Q8).
- **`tests/test_profile_save.gd` + `.tscn`** — new, 17 checks.
- **`tests/test_profile_expedition.gd`** — P1/P5 re-pointed to the
  `PROFILE_STARTING_*` constants (Q3). Still 28 checks.
- **Spec amended**: §2.3, §2.4, §3.1, §13.1, §13.2, §14 steps 2 and 5.

**Verified** (headless, `Godot_console.exe --headless --path . res://tests/<name>.tscn`):
all twelve suites `RESULT PASS` — `test_profile_save` (17),
`test_profile_expedition` (28), `test_autoload_safety` (9), `test_economy` (13),
`test_slot_odds` (11), `test_upgrades` (53), `test_item_distribution` (5),
`test_drops` (19), `test_endless_level_gen` (60), `test_retarget` (8),
`test_parallax_seam` (11), `test_damage_chunk` (26). **260 checks, 0 failures**,
zero edits to any test on §13.3's no-edit list, and a sentinel `profile.save`
survives the suite MD5-identical.

**Step 2 is complete. No further work.**
