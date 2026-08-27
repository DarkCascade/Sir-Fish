# Town Spec — Step 1 Implementation Questions

Raised while implementing §14 step 1 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("split `reset_run()` into `new_profile()` /
`start_expedition()`, with `active_party` still `PARTY_ORDER` and nothing else
changed"). These are gaps or contradictions found in the spec text itself while
making it real.

**All five are answered below, and every answer has been folded back into the
spec.** Four questions were resolved as implemented; **Q4 was reversed**, and
that reversal is the only code change any of these answers produced. Two gaps
the questions did not raise are recorded at the bottom as Q6 and Q7 — Q6 in
particular would have quietly cost step 4 its entire point.

---

## 1. §2.3 and §13.3 contradict each other on `reset_run()`

§2.3 says *"`reset_run()` is deleted and replaced by two functions."* §13.3
lists `test_endless_level_gen.gd` as a test that **must pass with no edits**,
and that test calls `GameState.reset_run()` directly at line 11 — the only
place in the whole test suite that does.

Both cannot be true. **Resolved for step 1 by keeping `reset_run()` as a thin
compatibility shim** — `new_profile(); start_expedition()` in sequence.

**Question:** is this the intended resolution, or should
`test_endless_level_gen.gd` instead be added to the "tests that need editing"
list in §0.3?

### Answer — the wrapper is correct, and it is **permanent, not a shim**

Keep it. §13.3 is a hard constraint over the whole pass, not just step 1, and
it is argued rather than incidental: it goes out of its way to say endless mode
"is still there, still default-`true` on `GameState`, and only bypassed when
`quest != null`." Moving that test to §0.3's edit list would contradict the
position §13.3 explicitly takes. §2.3's "deleted" was end-state shorthand for
"the body is replaced"; §13.3 is the stronger statement, so §2.3 yields.

The consequence worth stating plainly, because the implementation comment had
it backwards: **`reset_run()` never gets deleted.** It is endless mode's entry
point for the rest of this pass. What changes at step 8 is that quest accept
calls `start_expedition()` *alone* — and that lone call, not the deletion of
anything, is where gold, scrap and inventory start surviving a retry.

The source comment said "Delete this function ... the moment that pass wires up
SceneRouter and QuestDef", which would have forced exactly the test edit §13.3
forbids. **Rewritten.**

§2.3 now states the wrapper explicitly and shows its two-line body; §13.3 now
names `reset_run()` as the reason the test stays unedited. Neither section
silently overrides the other any more.

On the second half of the question — yes, "the seam exists" is the right scope
for step 1. But it no longer has to be taken on faith; see Q5.

---

## 2. §2.2's `start_expedition()` body omits `endless_level_number = 1`

**Question:** please fold `endless_level_number = 1` into §2.2's
`start_expedition()` listing.

### Answer — agreed, and it needed an ordering constraint alongside it

Correct on both counts: depth is run progress, not profile state, and the
listing was wrong to omit it. **Folded in.**

One thing the question understated. It is not just a missing line, it is a
missing line *with a position*: `_build_endless_level()` takes
`endless_level_number` as its argument, so the assignment has to land **before**
`build_level()`. §2.3's listing puts `level = build_level()` near the bottom, so
a reader adding the missing line by intuition — at the end, with the other
resets — would produce code that passes review and regenerates every retry at
the depth the party just died on. The spec now carries the ordering constraint
inline (`# MUST precede build_level(), which reads it`), and so does the source.

The implementation already had the order right.

---

## 3. Which of §2.2's new fields are actually in scope for step 1?

**Resolved for step 1** by adding all of them as inert data now.

**Question:** is inert-now the right call, or would you rather each later step
introduce its own field alongside the system that uses it?

### Answer — inert-now is right

Declare them once. The deciding argument is not churn, it is that
`start_expedition()`'s body is a **contract**, and §2.3 says so in as many
words: *"Note what is absent: gold, scrap and inventory. That absence is the
whole point of this function existing separately."* A function whose value is
what it does *not* touch should be readable in full from day one. Growing it one
line per step means nobody ever reads the whole contract at once, and the
absence — the part that matters — is the easiest thing to erode a line at a
time.

The stated risk (a field sitting unused with only a comment vouching for it) is
real but small, and it is now smaller: `test_profile_expedition.gd` asserts
`_expedition_inventory_mark`, `expedition_gold`, `expedition_scrap`,
`street_sleep_used` and `scrap` are actually maintained by the two functions, so
they are inert but no longer unobserved.

`quest` staying untyped is correct and unavoidable. Leave the comment.

Two things this question surfaced that needed spec fixes rather than a decision:

- `_expedition_inventory_mark` is now **named in §2.2's field listing** instead
  of appearing only in §8.5's prose. A field the spec never declares is a field
  the next implementer has to infer.
- The underscore is worth keeping, with a note: §8.5's failure flow needs to
  *read* it, so the intended access path is a discard helper on `GameState`, not
  a reach-in from `RunController`. That is now written down in both places.

---

## 4. `_reset_hero_runtime()` was introduced now but still reads `PARTY_ORDER`

**Question:** confirming this split is right — the helper's *existence* is step
1's business, but its *source of truth* stays step 4's business, per §4.5's own
call-site list.

### Answer — reversed. It should read `active_party` now, and now it does

This is the one place the implementation was talked out of the right thing by a
careful-sounding argument. Three reasons:

1. **§2.3 — step 1's own section — already specifies it.** Its last paragraph
   reads: *"`_reset_hero_runtime(full_heal: bool)` rebuilds `hero_runtime` from
   `active_party` (not `PARTY_ORDER`)"*. The parenthetical exists precisely to
   pre-empt this. Step 1 introduces the helper, so step 1 should introduce it as
   written, rather than ship a body that contradicts the section defining it and
   paper over the gap with a comment.

2. **It is a provable no-op.** `active_party` is initialised to
   `PARTY_ORDER.duplicate()` and nothing in the codebase writes it. Iterating
   one is byte-for-byte iterating the other. §14's "nothing else changed" is a
   constraint on *behaviour*, and this changes none.

3. **The coupling §4.5 protects is created by the value flip, not by the
   reads.** The hazard §4.5 names — drops targeting a mage who is not on the
   field — only exists once `active_party` stops equalling `PARTY_ORDER`. Which
   name each of the three sites reads is irrelevant until that moment, and
   irrelevant simultaneously at that moment. Moving one read early decouples
   nothing; it just means step 4 has one fewer edit to remember.

The reading the question worried about ("the helper is new, might as well wire
it up") reached the right destination for a slightly wrong reason, and the
worry inverted it. §4.5's list is a statement of the end state, not a quarantine.

**Changed:** the loop reads `active_party`. §4.5 now marks this site as already
done and explains why doing it early was free. All eleven tests pass unchanged.

---

## 5. `_reset_hero_runtime(full_heal: bool)`'s dead-hero path is unreachable

**Question:** should step 1 add a test asserting `start_expedition()` preserves
a wounded hero's HP, or is that adequately covered later?

### Answer — yes, add it now. Added, and it grew

Write it today. §14's own justification for step 1 is *"This is the riskiest
step and it is first, alone, so a regression here is unambiguous"* — a step that
buys isolation and then ships no assertion of its own has spent the isolation
and not collected. And the diagnosis is right: the first caller of standalone
`start_expedition()` will be somewhere in step 8's quest-accept flow, three
scene changes and a router away from this branch, which is a bad place to
discover that HP does not survive.

`tests/test_profile_expedition.gd` (28 checks, added to §13.1) covers more than
the question asked for, because writing it made a bigger gap obvious: **nothing
anywhere pinned the actual point of the split.** The wounded-hero branch is a
detail; the invariant is §2.3's *"the one thing a future edit here must not
undo"*, and that had no test at all. So:

- `start_expedition()` alone leaves `gold`, `scrap` and `inventory` untouched —
  the assertion that fires if anyone ever "tidies" that absence away;
- it still resets everything expedition-scoped, mark included;
- a hero at 3 hp keeps 3 hp; a hero at 0 hp is **not** resurrected, proving
  `alive` is derived rather than assumed;
- `new_profile()` full-heals that same hero;
- `reset_run()` still equals both halves in sequence — Q1's contract, asserted
  rather than assumed.

The dead-hero case turned out to be worth having on its own: `alive: hp > 0`
reads as obviously right, and is the kind of line a later refactor sets back to
`true` without thinking.

---

## 6. Not raised: §4.5 never names the edit that makes the party solo

This one is worth more than any of the five above, and it was missed by the
questions doc *and* by §4.5 itself.

§4.5 lists three call sites that switch from `PARTY_ORDER` to `active_party`.
Doing all three **changes nothing**, because all three would be reading a
variable that still equals `PARTY_ORDER`. The edit that actually makes the party
solo is not a call site at all — it is the **value flip**: `active_party`'s
initialiser and `new_profile()`'s matching assignment both go from
`PARTY_ORDER.duplicate()` to `[&"warrior"]`. §2.2's listing shows `[&"warrior"]`
and §0.4 settled solo-warrior as a fork, so the end state was never in doubt;
§4.5, the section that implements it, just never says to do it.

Failure mode: step 4 is implemented exactly as §4.5 reads, every test passes,
`droppable_classes()` still returns three classes, three heroes still spawn, and
the pass's headline decision silently does not happen.

§4.5 now leads with the flip and marks it as a fourth edit. `active_party`'s
source comment carries the same warning, and
`test_profile_expedition.gd`'s last check asserts the step-1 value so the flip
has to be a deliberate edit to a named assertion rather than an oversight.

---

## 7. Not raised: `new_profile()` ships two step-1 placeholder values

§2.3's `new_profile()` is written against `Tuning.PROFILE_STARTING_GOLD` (150),
`Tuning.PROFILE_STARTING_SCRAP`, and `SaveGame.save_profile()`. None exist at
step 1, so the implementation correctly used `Tuning.STARTING_GOLD` (75), a
literal `0`, and no save call — but nothing said so anywhere.

That matters because §11 is emphatic that `STARTING_GOLD` and
`PROFILE_STARTING_GOLD` are *deliberately different numbers with different
meanings*, and step 2 is where `new_profile()` stops being reachable only
through `reset_run()` and becomes the genuine no-save fallback. A placeholder
that is invisible at exactly the moment it stops being correct ships a 75-gold
profile forever.

All three are now marked inline in the source (`# -> PROFILE_STARTING_GOLD
(spec 11)`), and §2.3 carries a **Step-1 placeholders** paragraph naming step 2
as the deadline.

---

## What step 1 ships

- `scripts/autoload/game_state.gd`: `scrap`, `active_party`, `quest`,
  `expedition_gold`, `expedition_scrap`, `street_sleep_used`,
  `_expedition_inventory_mark` (all inert, Q3); `new_profile()`,
  `start_expedition(q = null)`, `_reset_hero_runtime(full_heal: bool)` reading
  `active_party` (Q4), and `reset_run()` as a permanent two-line wrapper (Q1).
  Placeholder values and the step-4 flip marked inline (Q6, Q7).
- `scripts/autoload/upgrades.gd`: one doc comment updated.
- `tests/test_profile_expedition.gd` + `.tscn`: new, 28 checks (Q5).
- `design documents/Sir Fish - Town, Quests & Forging Implementation Spec.md`:
  §2.2, §2.3, §4.5, §13.1, §13.3, §14 amended per the answers above.
- `run_controller.gd`, `bonus_strip.gd` and every pre-existing test file are
  untouched.

**Verified** (headless, `Godot.exe --headless --path . res://tests/<name>.tscn`):
all ten §13.3 tests pass with **zero edits to any of them** —
`test_endless_level_gen` (60), `test_economy` (13), `test_drops` (19),
`test_upgrades` (53), `test_autoload_safety` (8), `test_item_distribution` (5),
`test_slot_odds` (11), `test_retarget` (8), `test_parallax_seam` (11),
`test_damage_chunk` (26) — plus `test_profile_expedition` (28). 242 checks, 0
failures. A full `--headless --quit-after` boot produces output byte-identical
to the pre-change baseline (one pre-existing `bonus_panel.tscn` UID warning and
the usual forced-quit leak notices, present on `main` too).

**Step 1 is complete. No further work.**
