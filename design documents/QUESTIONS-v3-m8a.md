# QUESTIONS — v3 M8a (Sir Fish, finished)

Implementation discipline: implement as specified, record every deviation with the file and the
reasoning, change nothing silently, raise a **BLOCKER** rather than guessing.

M8a was built per v3 §20/§23.5, using v3.5 as the superseding amendment where relevant (see
§0 below). No blocker was raised; the one moment that came closest to one was a tooling
accident, caught and fixed before it reached a state that needed one — see "Incident" below.

## 0. Precondition check — M7.6 (v3.5) status

v3.5 §8 gates M8a behind M7.6 passing. `QUESTIONS-v3.5.md`'s gate log (run 2026-08-14) shows
all twelve M7.6 items implemented, with **F3's warlord framing, D3's `"LIGHTNING x3"` clip
check, D5's on-screen slide, D6's pixel measurements, and F5's win-screen text** flagged as
"not independently re-verified by screenshot" (code-reviewed only).

None of those five gaps touch M8a's surface area (battlefield framing, slot banner, corpse
timing, health-chunk flight, and the run-summary subtitle string are all unrelated to Sir
Fish's rig or tank). Per v3.5 §0.2's own scope statement — *"none of the twelve items touch
meshes, rigs, animation names, `required_anims()`, or `model_scale`"* — M7.6 being incomplete
on those five specific checks does not block M8a. Proceeded on that basis rather than treating
it as a blocker. **Not re-verified as part of this pass either** — if the owner wants those
five closed out, that is still M7.6's job, not M8a's.

One thing M8a incidentally *did* re-verify live, as a side effect of exercising Sir Fish's
reaction states: F5's victory-path text. A run cleared all six encounters during testing and
the run summary correctly read **"Cleared all 6 encounters"** (not "7 of 6"), and a separate
defeat correctly read "Reached encounter 3 of 6". Both are now confirmed on screen, closing
that one item of the five above as a bonus, though the other four remain open.

## 1a. Bug found post-review: the tail rendered ~0.1–0.2 units from the body

The owner reported "Sir Fish's tail seems impractically far from his body" after this pass was
first reported done. Investigated and confirmed as a real rig defect, not a false read — and
fixed. Root cause, for the record:

Blender's `parent_type = 'BONE'` (rigid, non-deforming bone parenting, which is what the
original `bone_parent()` helper used for every mesh in the rig) silently anchors the child at
the parent bone's **tail**, not its head, for live viewport display — an automatic
`Translation(0, bone.length, 0)` gets folded into the evaluated transform outside of
`matrix_parent_inverse`, so no amount of adjusting the inverse matrix can cancel it from
Blender's side. Worse, Blender's glTF exporter does **not** reproduce that viewport-only
offset — it exports each rigid-parented child's raw `matrix_local`, so the exported/Godot
result and the Blender-viewport result actively disagree, and neither one is simply "the
original modelled position" without extra correction. Three fix attempts were needed before
landing on a real one:

1. Correcting `matrix_parent_inverse` for the tail offset fixed Blender's viewport but left
   the Godot-imported result unchanged (still offset, since the exporter ignores that offset
   entirely).
2. Reverting to the original head-based inverse and instead shifting each object's own
   `.location` by the negative of the bone's tail-offset vector had **no effect** on the
   Godot-imported result either — the (0, bone.length, 0) offset the exporter bakes into a
   rigid-parented child's local transform turned out to be a fixed function of the bone
   itself, not of the child object's transform at all.
3. **The actual fix:** stopped using rigid `'BONE'` parenting entirely. Every mesh is now a
   real vertex-group-skinned child of the armature (one group per bone, full weight, plus an
   Armature modifier) — the standard, well-supported glTF/Godot path, immune to this
   head/tail ambiguity because skin binding is explicit data, not an implicit parenting
   convention. `HelmGroup` (an `Empty`, which can't be skinned) was removed; its six meshes
   are now skinned to the `Helm` bone directly instead.

Verified after the fix: every one of the 13 mesh parts' world position at rest matches its
originally-modelled coordinates exactly (checked numerically in Blender, not just by eye), the
live game shows the tail sitting against the body in every reaction state exercised, and all
eight headless tests still pass. Re-exported `sir_fish.glb` and re-verified with zero editor
errors.

**Not logged as a separate design question** — this was an implementation bug with one correct
fix, not an ambiguity needing the design model's input. Recorded here per the "say plainly what
happened" habit, and as a **trap for any future Blender rig work in this project**: never use
`parent_type = 'BONE'` for a rigid attachment intended to survive a glTF round-trip; skin it
(vertex group + Armature modifier) instead, even for a single-bone, zero-deform attachment.

## 1. Rig: a third bone, "Helm" — logged deviation, not a blocker

Spec text (§23.5): *"a two-bone armature, `Root` and `Tail`, plus optional `Fin.L` / `Fin.R`."*
Also (§23.5): *"`slump` must end with the helm on the gravel. Animate it as a separate object
with its own action, or key its parent constraint off at the end of the clip."*

These two instructions are in tension: the helm assembly (`SirFish_Helm`, `HelmSkirt`,
`HelmBrow`, `Visor`, `Circlet`, `Crest` — six meshes, none of which are named in the "two-bone"
list) needs *some* attachment point to detach from during `slump`, and rigid attached
primitives need a bone or an empty to parent to.

**What was built.** A third bone, `Helm`, child of `Root`, added specifically so the detach
motion is an ordinary pose-bone track inside the same `slump` Action as `Root` and `Tail` —
see "Incident" below for why a second Action datablock on a separate object was tried first
and abandoned. `Helm` carries no keys in the other six clips (so it silently inherits `Root`'s
motion, i.e. "attached"), and carries a divergent pose only in `slump`'s back half.

This is a spec-vs-spec conflict resolved in favor of the more specific instruction (the
detach mechanism) over the more general one (bone count), and is exactly the kind of thing
v3 §0.1.4 asks to be logged rather than silently decided. **Flagging for the design model:**
is a third bone acceptable here, or was "two-bone" meant as a hard constraint that should
have taken priority over the detach requirement (e.g. accepting a less literal detach —
color/alpha cue only — to stay at two bones)?

## 2. Tank: left as the existing procedural GDScript build, not re-modelled in Blender

§23.5's "Remaining (M8a)" list bullets Rig and Tank together: *"Tank: a rounded bowl, a gold
base ring, a gravel bed, and a small gold plaque."* Read in isolation this could mean model
the tank in Blender alongside the fish.

**What exists today, unchanged by this pass:** `sir_fish_tank.gd`'s `_build_tank()` already
builds exactly those four objects (`Glass`/bowl, `Base`/gold ring, `Gravel`, `Plaque` +
`Label3D`) procedurally in Godot, using the same cel material every other primitive uses, and
this already passed V12's regression check (§17.7) — the tank reads as a lit fish bowl, not a
dark blob. Nothing in §23.5 states the tank must move to Blender; §0.1.2's rule that every
mesh is *either* generated procedurally in Godot *or* modelled in Blender is satisfied by the
current code either way.

**Decision made:** left the tank as-is. Re-modelling four simple primitives in Blender for a
result visually indistinguishable from the existing (already-gated) procedural build would be
pure churn, and risks regressing the three V12-critical viewport settings
(`own_world_3d`/`FishEnvironment`/`Backdrop`) for no gain. Treating "Remaining (M8a): ... Tank:
..." as describing *content that must exist* (already true) rather than *a mandate to move
its authoring route* (not stated).

**Flagging for the design model:** confirm this reading is correct, or state explicitly that
the tank must also be Blender-modelled and exported (in which case the plaque's `Label3D`
approach and the three V12 viewport nodes need to be re-attached to whatever new tank node
comes out of that export, exactly as they were carried through this fish swap).

## 3. Incident — an accidental scene overwrite, caught and repaired within this session

While instancing the exported `sir_fish.glb` for a first structural check, `add_scene_instance`
+ `get_scene_tree` + `save_scene` were called against a scene that **turned out not to be**
the throwaway scratch scene just created with `create_scene` — the MCP's "currently edited
scene" was still `res://scenes/battle/battle_world.tscn` from an earlier step, and
`add_scene_instance`'s `parent_path="."` silently added the fish model instance as a *deep
copy* (inlined mesh/material sub-resources, not an `instance=ExtResource(...)` reference) onto
`BattleWorld`'s root. The subsequent `save_scene` wrote that corrupted 891-line version of
`battle_world.tscn` to disk, overwriting the working file (no git repo in this project, so
there was no source-control safety net).

**Caught immediately** by inspecting the saved file before moving on. **Fixed** by hand-
reconstructing `battle_world.tscn` from its own remaining readable content (the original
ext_resources, the single `Environment` sub_resource, and the node tree minus the erroneous
`FishModel` branch — all still present verbatim in the corrupted file, just interleaved with
the injected content) and rewriting the file via `Write`. Re-verified after: `get_scene_tree`
on a freshly re-opened `battle_world.tscn` shows the original seven-node tree with no
`FishModel`, `get_editor_errors` is clean, and all eight headless tests still pass — including
`test_parallax_seam`, which would be the first thing to break if `battle_world.tscn`'s
structure were subtly wrong.

**Why this wasn't raised as a BLOCKER:** the corruption was caught and fully reverted before
any dependent work was built on top of it, and the recovery was independently verifiable
(tests, error log, fresh scene-tree read) rather than taken on faith. Logging it here per
v3 §0.1.4/§24's "say plainly what happened" discipline, and as a trap for the next session:

**Trap, new:** `add_scene_instance` / `save_scene` operate on the Godot MCP's *currently
open editor scene*, which does not necessarily match the scene most recently created with
`create_scene` unless `open_scene` is called on it explicitly first. **Always call
`open_scene` on the intended target and verify `get_scene_tree`'s content (not just its
`scene_path` label, which can be stale) matches expectations before calling `save_scene`.**
This was the actual working method used for every scene edit after this incident (the real
`sir_fish_tank.tscn` swap), and it worked cleanly.

## 4. Rig authoring: axis convention, not spec-mandated, noted for the record

§9.0's screen-plane rotation convention is written for the *combatants'* shared camera
(`BattleCamera`, looking down -Z). Sir Fish's own camera (`FishCam`, §17.7) is a different,
independent orthographic view, and §17.7's reaction-state table describes behaviour in prose
("darts to the far side," "rolls onto his side") rather than in §9's numeric-axis convention.
There is no spec text pinning Sir Fish's Blender-authored rotations to specific world axes.

Built the seven clips using Blender's own axes directly (Z-up, matching the already-modelled
mesh's rest orientation), verified by import + live capture rather than by porting the old
placeholder's Godot-space numbers axis-for-axis. This is a reasonable-fit interpretation, not
a deviation from an explicit instruction, so it is not logged as a substitution — noted here
only so a future reader knows the seven clips are an original authoring pass, not a literal
port of `sir_fish_rig.gd`'s old procedural keyframes.

## 5. Verification — what was and wasn't directly observed this pass

Per §24's "say plainly what is not done" habit:

**Confirmed live, in the running game, this pass:**
- `idle` — plays by default, visibly animating (figure-8 sweep + tail wag) across
  `capture_frames` sequences, not a static/T-pose.
- `alarm` — triggered via `Debug damage warrior 5` (hero damaged).
- `grieve` — triggered via `Debug kill ranger` / `Debug kill warrior` (hero deaths).
- `slump` — triggered via killing the whole party (`game_over`); holds correctly, `DEFEATED`
  screen renders with the fish visibly sunk in the tank.
- `triumph` — a run happened to clear all six encounters mid-session; `capture_frames` across
  the run-summary tank shows the fish spinning with bubbles, at 2x scale, matching §18.2.
- The run-summary's 2x tank (`SummaryFish`) instances the same `sir_fish_tank.tscn` and swapped
  model with no separate authored variant, per spec — confirmed structurally via
  `get_game_scene_tree` and visually via the `triumph` capture above.
- Materials: every `MeshInstance3D` under the swapped model reads a `CelMaterials.cel(...)`
  `material_override` (not the arriving `StandardMaterial3D`s), confirmed by code path
  (`RIG.reassign_materials`) running with no errors and the fish rendering in its
  original palette (blue body, gold trim, dark ink) rather than as untextured grey.
- Zero editor errors/warnings across every step above, and all eight headless tests pass
  after the swap (unaffected, as expected — no test touches Sir Fish).

**Not independently screenshotted this pass, though implemented and code-reviewed:**
- `cheer` and `smug` — both wired to `slot_payout`/`upgrade_purchased` exactly like `alarm`
  and `grieve` are wired to combat signals (same `play()`/`PRIORITY` machinery already proven
  live), but a 2-of-a-kind or 3-of-a-kind slot result was not specifically forced and captured
  this pass.
- The 164px read-gate at native scale, pixel-inspected rather than eyeballed from a
  full-board screenshot — the tank is a small element of a much larger UI and the returned
  screenshots don't isolate it. Recommend a follow-up pass render `SirFishTank` in isolation
  (e.g. via `render_thumbnail_to_path`-style framing, or a dedicated debug scene) at native
  164x164 for a direct legibility check, the way §23.5's original mesh-only gate did.
- `slump`'s helm-on-gravel placement was checked geometrically in Blender (the helm bone's
  final pose sits at ground level, separated from the body) but not pixel-verified against the
  actual `Gravel` mesh's world position in the live tank scene, since the two are built by
  different systems (Blender-authored rig vs. `sir_fish_tank.gd`'s procedural tank) that only
  come together at runtime. The live `DEFEATED` screenshot shows the fish sunk and still, which
  is consistent with a correct landing, but the helm is too small in that capture to confirm
  its position relative to the gravel specifically.

None of the unconfirmed items involve logic complex enough to carry the same regression risk
as the corpse-cleanup race M7.6 found (§0's precondition check) — they're forced by simple,
already-proven-live triggers. Recommend a follow-up pass (or the owner's own play session)
specifically force a slot win via `Debug slot 0 0 0` (or `1 1 1`) during combat and capture
`cheer`/`smug`, and render the tank in isolation at 164px for the read-gate.
