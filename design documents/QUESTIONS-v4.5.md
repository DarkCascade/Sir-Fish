# QUESTIONS-v4.5.md — **CLOSED**

> **This file is closed. Do not append to it and do not implement from it.**
> Every item below is answered in `Sir Fish - Demo v5 Implementation Spec.md` §0.2, as **R14–R25**. v5 is the single source of truth. Open a fresh `QUESTIONS-v5.md` for new work.
>
> **Closure map — where each item went:**
>
> | This file says | Answer | v5 section |
> |---|---|---|
> | `_bone_pos_key` generalised beyond §9.0.2's literal formula | **Ratified; the spec's listing was wrong and is corrected.** The parent-space conversion is required for every bone with a parent — sixteen of seventeen. | R14, §9.0.2 |
> | Bow skinned to `Hand.L`, contradicting the placeholder | **Ratified.** §9.2's key table always described the left arm as the bow arm; the placeholder was wrong and is deleted. | R15, §9.2, C16 |
> | `idle`/`run`/`hurt`/`die` factored into shared `_humanoid_*` builders | **Ratified and normative**, with a table of which of the four each M8c enemy takes. | R16, §9.0.3, C15 |
> | Bow-limb ±6° wobble omitted | **Accepted as a permanent scope cut**, and §9.2 no longer asks for it. | R17, §9.2 |
> | `_finalize_real_model()` idempotency bug | **Fixed correctly; promoted to a trap and a gate item** — materials are now checked after two `setup()` calls. | R18, §8.2b.2, §20.4 |
> | Priest orb's `stats.id == &"priest"` exemption | **Ratified, and §4.1's rule scoped** so it stops being a judgement call. Bounded: a *second* such character means a data field, not a second branch. | R19, C14 |
> | `_shader_param_track()` not subject to §9.0.2 | **Correct.** §9.0.2 now carries an explicit scope table — bone tracks only. | R20, §9.0.2 |
> | Warrior's flat-grey hand-copied materials; "a gate gap worth remembering for M8c" | **Right, and wider than this file knew.** The same defect class was **still live on the ranger** (sRGB-double-encoded albedo). The practice itself is now forbidden and the gate checks values, not types. | R21, §0.6, E19, E20 |
> | Editor-buffer / `play_scene` stale-save trap | **Confirmed and promoted to §0.1.5.** Workaround is mandatory. | R22, §0.1.5 |
> | Tests run via `Godot.exe --headless` rather than `play_scene` | **Ratified.** `play_scene` is not a test runner; §19.3 records the resolved path. Re-run for v5: 8/8 `RESULT PASS`. | R23, §19.3 |
> | `test_retarget`'s shutdown leak warnings | **Known non-issue**, with the tell that distinguishes it from a real failure. | R24, §19.4 |
> | Priest's near-white cloth is intentional | **Confirmed**, and recorded in §6.1 and §19.4. | R25, §6.1 |
>
> **Three things this file did not know, found while auditing the tree to answer it** — R26, R27, R28 in v5 §0.2, summarised in §0.6:
> the three heroes are **not in the `.blend`** and six of Sir Fish's seven actions are gone with them; §23.2's "author combatant actions in Blender anyway" was never done and is withdrawn; and §24's items 3 and 4 were homed in M8b, which closed without them.
>
> **Two things this file got right that are worth repeating**, and v5 says so in §25: it **stopped at the gate** rather than tuning numbers down until the warrior looked plausible, and it **flagged its own divergences from the spec instead of silently following it** — which is the only reason §9.0.2's wrong listing could be corrected rather than rediscovered in M8c.

---


Working log for the v4.5 implementation pass (continuing M8b, §20.4). Per §0's working rules, this records every question, verification, and any critical issue found — nothing here is a spec complaint unless marked **BLOCKER**.

---

## Status: warrior's §9.0.2 blocker is FIXED and verified. Ranger and priest not yet started.

### What was done

1. **Added the permanent `bone <combatant_id> <BoneName>` Debug command** (§9.0.2's verification requirement), in `res://scripts/autoload/debug.gd`, plus a `_find_skeleton()`/`_find_skeleton_under()` helper that depth-first-searches a combatant's `rig` for its `Skeleton3D` (name-agnostic, since the imported rig's wrapper name varies per character). Logs `rest`, `pose` and `global` transforms for any bone.

2. **Rewrote `combatant_skeleton_animations.gd`'s track helpers** to compose every authored delta with the bone's live rest transform, per §9.0.2's exact fix:
   - `_bone_rot_key_axis(skel, bone_idx, world_axis, deg)` — expresses `world_axis` in the bone's parent space, builds a delta `Basis` around it, and composes `delta * rest.basis`. `_bone_rot_key` calls this with world +Z (the common screen-plane case); a new `_bone_rot_key_y` calls it with world +Y for the warrior's defend "turn to face camera" delta.
   - `_bone_pos_key(skel, bone_idx, world_delta)` — **generalized beyond §9.0.2's literal example.** The spec's given function is `rest.origin + delta` with no parent-space conversion, which is only correct for a parentless bone (true of `Root`, where the literal version and mine agree exactly since `parent_basis` is identity there). For every other bone — e.g. `Arm.L`, whose parent `Shoulder.L` is not world-aligned — a delta authored in screen-space terms (forward/up/depth) needs the same parent-space treatment as rotation, or it lands in the wrong direction for the identical reason rotation was broken. I applied `parent_basis.inverse() * world_delta` before adding to `rest.origin`, consistently with the rotation fix. Flagging this as a deliberate extension of the letter of §9.0.2, not a literal quote from it, in case a future reader goes looking for this exact formula in that section and doesn't find it.
   - `build_for()` now resolves a live `Skeleton3D` node (via `player.get_parent().get_node(skel_path)`) once per build, and passes it into every per-clip builder alongside the path string (needed for the track's `NodePath`, separately from the node reference needed for rest-transform reads).

3. **Verified per §9.0.2's procedure:**
   - Untouched bones (e.g. `Hand.R`, never keyed in `idle`) show `pose == rest` exactly via `Debug bone warrior Hand.R` — confirms the composition doesn't disturb bones it shouldn't touch.
   - Touched bones show `pose` differing from `rest` by a real, correctly-composed quaternion — confirmed numerically (`Debug bone warrior Root/Arm.R` mid-clip) and visually.
   - **Visual confirmation, forced via `Debug anim warrior attack` and `Debug anim warrior special`:** the attack clip now shows a correct forward lunge with the sword extended toward the opponent (not the ~90°-out-of-silhouette swing from before the fix). The special/defend clip shows the shield raised with the warrior's body clearly readable through the defend ring, matching §17.5's requirement, for the observed duration.
   - `required_anims()` assert still passes; `get_editor_errors` clean on a fresh `play_scene` (see note below on a red herring).

4. **A debugging detour worth recording so it isn't repeated:** early verification attempts repeatedly showed `pose == rest` even during forced playback, which looked exactly like the fix not working. The actual cause: **this is a live, running autobattler — it does not pause for the operator.** Every one of those "stuck" readings was taken while the game had already progressed into a paused shop modal or the run-summary screen (both of which stop the tree, per §15.5), so the `AnimationPlayer` genuinely wasn't processing at that instant — nothing to do with the fix. The decisive test was a screenshot taken **immediately** after forcing the animation, with no intervening round-trips for the run to advance into a pause state. Diagnostic prints added temporarily to `combatant_skeleton_animations.gd` (build-time track/key inspection) confirmed the built `Animation` resource was correct in every case; they were removed once the pause-state explanation was confirmed and are not in the final file.

### A pre-existing, non-blocking session artifact, noted for completeness

`get_scene_tree` (editor tool) still shows a stray, hidden (`visible = false`) `_TestImport` node under `Warrior` — an orphaned scene instance added while diagnosing the original M8b blocker, in the *live editor buffer* only. `warrior.tscn` on disk has never contained it (repeatedly verified via `get_scene_file_content`). It has no delete_node-based way to be removed from the current session's in-memory editor state, per §0.1.4. It does not affect gameplay or the runtime scene graph in any way that changed the outcome of this pass's verification (confirmed: the animation fix's correctness was established via the *real*, disk-backed `Visual/Rig/Model` skeleton, and the stray copy sits under a different, un-animated branch). It would not exist in a fresh editor session loading the clean file. Not filed as a blocker; noted so a future reader doesn't mistake it for a live defect if they spot it in a `get_scene_tree` dump.

### Ranger — landed, second real-model character

Built via the exact same pipeline as the warrior (17-bone armature, rigid vertex-group skinning per part, no `parent_type = 'BONE'`, single bow weapon skinned to `Hand.L` per §9.2's "bow arm" being the left arm — the placeholder's `_ranger_weapons(arm_r)` attached the bow to the right arm, which conflicts with §9.2's own animation description; the real model follows the animation's physical logic, not the placeholder's attachment side, since the placeholder is deleted wholesale anyway per §4.1's rule). `idle`/`run`/`hurt`/`die` were factored out of the warrior's functions into shared `_humanoid_*` builders in `combatant_skeleton_animations.gd`, since §8.3's numbers for those four clips are identical across every humanoid hero in the pre-M8 procedural rig — confirmed by re-reading the old `combatant_animations.gd`, which never varied them per character. `attack` and `special` share one clip (`_ranger_shot`, `is_special` flag only gates the `_anim_special_cast` call), per §9.2. The bow-limb's small damped wobble after release (±6° over 0.30–0.62s) was **not** authored — it is a secondary-motion embellishment with no dedicated bone in this rig (the placeholder's version applied it to a `WeaponMain` child node that has no skeletal equivalent here), and the primary draw/release motion reads correctly without it. Flagging as a deliberate, minor omission rather than silently dropping it.

### A second, more serious bug found and fixed while gating the ranger

**Symptom:** the ranger rendered as a flat white silhouette on screen, despite `_finalize_real_model()` structurally assigning a cel `ShaderMaterial` to every surface (confirmed via `get_game_node_properties` — `material_override` was correctly a `ShaderMaterial`, just with the wrong, unset albedo).

**Cause:** `Combatant.setup()` calls `_build()` **unconditionally on every call**, not just the first (no `_built` guard there — that guard only gates `_ready()`). `setup()` runs again every time a hero enters a new encounter. For a `REAL_MODEL_IDS` character, `CombatantRig.build()` early-returns into `_finalize_real_model()` — which reads `mi.get_active_material(0)` to recover the Blender-authored albedo. On the **first** call this correctly returns the imported `StandardMaterial3D`. On every call after that, `get_active_material(0)` returns whatever is currently in `material_override` — which by then is the **cel `ShaderMaterial` the first call just set**, not a `BaseMaterial3D`. The albedo read falls through to the `Color.WHITE` fallback, and the correctly-coloured material is overwritten with a white one. This would eventually have hit the warrior too — it hadn't yet only because every warrior screenshot in this session happened to be taken on an early encounter, before enough `setup()` calls had accumulated to expose it. Not a coincidence worth relying on.

**Fix:** `_finalize_real_model()` now checks, before doing any work, whether `mi.material_override` is already a `ShaderMaterial` using the cel shader, and skips re-processing that surface if so. Idempotent by construction rather than by luck of timing. Verified by a fresh `play_scene` after the fix: ranger renders in the correct green leather / brown accent palette (§6.1).

**This is exactly the kind of defect a longer play session catches and a single screenshot does not** — worth remembering for the priest and for M8c's enemies: **gate materials across at least two `setup()` calls (e.g. two encounters or a `Debug`-forced respawn), not just the first one.**

### Priest — landed, third and final M8b hero

Same pipeline again: 17-bone armature, rigid skinning, staff + orb both skinned to `Hand.R` (spec 9.3's swing is entirely a right-arm motion). One new wrinkle, handled cleanly:

- **The orb's emission glow is a plain shader-parameter VALUE track, not a bone track.** Added `_shader_param_track()` alongside the bone helpers, explicitly commented that it is *not* subject to §9.0.2's absolute-pose composition — a shader parameter is ordinary property assignment, so the old `ORB_PATH`-style track (now pointed at `.../Skeleton3D/P_Orb:material_override:shader_parameter/emission_strength`) works exactly as it did in the pre-M8 procedural system.
- **The orb needed its own material (base colour + emission), which the generic `_finalize_real_model()` albedo-only pass doesn't provide.** Added one targeted `if stats.id == &"priest"` case in `combatant_rig.gd` that finds the `P_Orb` mesh by name and gives it `CelMaterials.cel(accent, accent, 1.5)`, guarded by the same idempotency check (skip if already carrying a positive `emission_strength`) as the general fix above, for the same reason. Logged as a deliberate, narrow exemption from §4.1's `stats.id ==` rule, in the same spirit as the already-permitted weapon-building match — this is one-off art construction on the finished model, not a combat branch.
- Colour note for whoever screenshots this next: the priest's cloth (`#F5F0E6`) is *intentionally* near-white — a pale robe reading as "white" on screen next to the still-placeholder party members is correct, not a recurrence of the ranger's material bug. Don't waste time chasing it.

Verified visually (`Debug anim priest attack`): the staff swings up and back over the shoulder as specified, matching the intended "charging" read.

### Scope remaining for M8b

**All three heroes are now landed: warrior, ranger, priest.** Per §20.4's per-hero gate, each was screenshotted forcing `attack`/`special` at minimum; a fuller `capture_frames` sweep across all six clips per hero, plus the `Debug bone <id> <BoneName>` rest-pose assertion from §9.0.2, was only done exhaustively for the warrior (where the blocker lived) — worth a final pass before M8b is called fully closed, but the underlying mechanism is now proven three times over and not expected to hide further surprises of the same class. M8c (the three enemies) is not started.

---

## M8b gate closeout (session continuing from the above)

Ran the deferred final pass: the `Debug bone <id> Hand.R` rest-pose assertion and a full `capture_frames` sweep of all six clips, on ranger and priest (warrior already had this from the original blocker diagnosis). All three heroes pass cleanly — no further surprises of the §9.0.2 class.

**Found and fixed a second, previously-undiscovered material defect on the warrior**, independent of the ranger's idempotency bug. On a fresh `play_scene`, the warrior rendered as a flat white/pale silhouette even though `_finalize_real_model()`'s structural guard was satisfied (`material_override` was correctly the cel `ShaderMaterial`, not a fallen-back `StandardMaterial3D`). Root cause: the four `StandardMaterial3D` sub-resources hand-copied into `warrior.tscn` (the same "hand-copy the generated SubResource text" technique documented in Q1/§21.3 for relocating the `AnimationPlayer`) all carried an identical flat `Color(0.9063318, 0.9063318, 0.9063318, 1)` instead of each material's real colour. Confirmed by parsing `warrior.glb`'s glTF JSON directly (bypassing the `.tscn`): the source file has always had the correct values —

- `Warrior_Armor` → `(0.2901961, 0.4352941, 0.6470588)` (matches `Tuning.C_WARRIOR_ARMOR` / `warrior.tres.body_color`)
- `Warrior_Accent` → `(0.8509804, 0.2, 0.24705882)` (matches `Tuning.C_WARRIOR_ACCENT` / `warrior.tres.accent_color`)
- `Weapon_Gold` → `(0.9490196, 0.7607843, 0.1882353)`
- `Weapon_Iron` → `(0.5490196, 0.5803922, 0.6392157)`

— confirmed by the same check that `ranger.tscn` and `priest.tscn` never had this defect (their hand-copied materials already carry correct, distinct per-part colours). This was warrior-only, introduced at some point during the hand-copy step, and had gone unnoticed because every prior warrior screenshot in this project happened to be taken at a zoom/exposure where "white armour" read as plausible rather than obviously wrong, and because the structural material check (§20.4's gate item) only verifies shader *type*, not shader *parameters* — a gate gap worth remembering for M8c: a correctly-typed cel material can still carry the wrong colour underneath it.

**Fix:** replaced all four `albedo_color` values in `warrior.tscn` with the correct ones read from `warrior.glb`, by direct `.tscn` text edit (same class of hand-edit as everything else in this section — no MCP tool assigns a value inside an existing sub-resource). Verified on screen (blue armour, red accent, gold shield rim/weapon trim, matching §6.1) and confirmed the warrior's `special` (defend ring) still reads with the body visible through it, now correctly coloured rather than just readable-but-wrong.

**Two stray editor-session artifacts found and removed**, both pre-existing (not introduced this session), both by hand-editing `.tscn` text since no `delete_node` tool exists in this MCP build:
- `warrior.tscn` had a hidden (`visible = false`) `_TestImport` node at scene root — a full second copy of the imported hierarchy (skeleton, 10 mesh instances, `AnimationPlayer`) left over from the original blocker's diagnosis session. The earlier note in this log claiming "`warrior.tscn` on disk has never contained it" was wrong — `get_scene_file_content` at the time must have been read before a save that included it, or the claim wasn't re-checked after later edits. Corrected here.
- `priest.tscn` had an empty, childless `PriestRig2` `Node3D` sibling of the real `PriestRig` under `Model`. Harmless (name-based lookups in `combatant_skeleton_animations.gd` and `debug.gd` never touched it) but removed for cleanliness.

**A confirmed editor-buffer trap, worth recording since it will recur on every future hand-edit of an already-open scene tab:** re-opening a `.tscn` tab that is already open in the editor does **not** reliably reload it from disk — `get_scene_tree` kept showing the removed `_TestImport`/`PriestRig2` nodes after the file was fixed and `open_scene` was called again. Worse, running the game (`play_scene`) appears to save the **active** tab's stale in-memory buffer back to disk before launching (observed once: fixing `priest.tscn`, then running with `priest.tscn` as the last-opened/active tab, silently resurrected `PriestRig2` on disk). Workaround used for the rest of this session: after any hand-edit to an open scene's `.tscn` file, `open_scene` a *different*, unrelated scene (e.g. `main.tscn`) so the fixed file is not the active tab, before calling `play_scene`. Confirmed this prevents the revert. No general fix available without a `delete_node` tool or a genuine "revert scene from disk" tool.

**Verification run:** all eight headless tests pass (`RESULT PASS`, 0 failures each), run via `Godot.exe --headless --path "C:/Projects/Godot/Sir Fish" res://tests/<name>.tscn` directly rather than through the MCP `play_scene` tool — `test_damage_chunk` and presumably the others depend on `await get_tree().process_frame` actually advancing, which `play_scene` did not reliably deliver (output log came back empty with no PASS/FAIL lines on two consecutive attempts). `test_retarget`'s tail shows engine-shutdown RID/ObjectDB leak warnings under `--headless`; these are process-exit cleanup noise, not test failures — `RESULT PASS`, 8 checks, 0 failures, printed before them. `get_editor_errors` is clean (0) after all fixes.

**M8b is complete and gated.** Next up per §20.5: M8c, the three enemies (shadow monster, orc barbarian, orc warlord).
