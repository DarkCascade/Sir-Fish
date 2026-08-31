# Sir Fish — Web Performance Acceptance Testing Spec

Companion to *Sir Fish — Web Delivery & Render Performance Spec* (referred to
throughout as **the spec**; all bare `§` references are to it) and to
`QUESTIONS-web-perf.md` (**the questions doc**).

This is the acceptance pass over the implementation pass: what the spec asked
for, what the questions doc claims was done and deferred, and the gap between
those two and the tree as it actually stands. It follows the conventions of
*Sir Fish — Town Initiative Acceptance Testing Spec*.

The pass found one materially wrong call in the questions doc (**A1** — a
blocker that was not a blocker), one large opportunity **neither** document
identified (**E1** — 16.5 MB, now the single biggest remaining item), and one
spec section that was quietly skipped rather than deferred (**B1**).

---

## 0. How to use this

### 0.1 Scope

This document does not re-open the spec's sequencing or its Phase 4 deferral.
Every finding is either a place the implementation contradicts the spec, a
place the spec asked for something never built, a place the spec itself is
wrong, or a decision nothing records.

**A1 and E1 were acted on during this pass** — A1 because the questions doc's
blocker turned out to be false and the fix was small and testable, E1 because
finding it *is* the acceptance result even though fixing it is not. Everything
else is filed, not fixed.

**Nothing here is release-blocking.** The suite is green at 20/20, a real
quest runs to combat cleanly, and the imported-asset payload is already down
54%.

### 0.2 Severity classes

| class | meaning | implementer's obligation |
|---|---|---|
| **A** | the questions doc records something as true/blocked that is not | correct it, and pin with a test |
| **B** | the spec asked for something that was never built and never deferred | build it, or file it as deferred on purpose |
| **C** | test coverage this pass's own conventions require | add it |
| **D** | hygiene, dead files, uncommitted churn | fix opportunistically |
| **E** | a decision nothing records — needs a ruling, not a patch | **ask; do not guess** |
| **F** | the spec document is behind, or wrong about, the code | amend the spec |

### 0.3 Findings index

| ID | finding | authority | confirmed by |
|---|---|---|---|
| **A1** | Q6 declared §2.2.2 blocked; it was not — **resolved this pass** | §2.2.2 | empirical reimport |
| **B1** | §3.2's `adjustment` fold was skipped, not deferred | §3.2 | doc read |
| **B2** | §5's entire measurement plan is unaddressed | §5 | doc read |
| **C1** | No test pinned the animation strip — **added this pass** | §2.2.2 | new test |
| **C2** | Nothing pins `import_script/path`; the editor UI silently resets it | A1 | mechanism |
| **C3** | Nothing pins the web-only render overrides | §3.2 | absence |
| **D1** | Eight icon `.import` files carry line-ending-only uncommitted diffs | — | `git diff --numstat` |
| **D2** | Two `_scratch_*` scenes are tracked in `tests/` | town spec C2 precedent | `git ls-files` |
| **E1** | **16.51 MB of 1024×1024 UI icons, displayed at ~104 px** | unrecorded | measured |
| **E2** | Q7 (glow) still unverified against a battle scene | §3.2 | questions doc |
| **E3** | Q3 (fold two directional lights) still needs an art ruling | §3.3 | questions doc |
| **E4** | Q2 (which fonts get MSDF) still needs a ruling | §3.5 | questions doc |
| **F1** | §3.1 is wrong: `rendering_method.web` **is** already set | §3.1 | settings read |
| **F2** | §2.2.2's stated mechanism does not exist in Godot 4.7 | §2.2.2 | empirical |
| **F3** | §2.4's budget table is superseded by measured actuals | §2.4 | measurement |

### 0.4 The green bar

Every fix here must leave the following passing. `test_animation_clips` is new
in this pass and joins the suite; the §13.3 no-edit list is untouched.

```bash
for t in test_economy test_slot_odds test_upgrades test_autoload_safety test_endless_level_gen test_retarget test_parallax_seam test_damage_chunk test_enhanced_rarity test_profile_save test_profile_expedition test_drops test_item_distribution test_scene_router test_quest_gen test_quest_flow test_forge test_forge_stock test_loot_pickup test_animation_clips; do printf '%-28s ' "$t"; "C:/Projects/Godot/Godot/Godot.exe" --headless --path . "res://tests/$t.tscn" 2>&1 | tr -d '\r' | grep -E "RESULT (PASS|FAIL)" | head -1; done
```

Current baseline: **20 scenes, all `RESULT PASS`**, re-verified after every
change in this pass.

---

## 1. Method

Findings were produced by reading the spec and the questions doc against the
tree, then confirming every behavioural claim rather than inferring it:

- **Payload numbers** come from resolving each `.import` file's `dest_files` to
  bytes actually on disk — the same script before and after, so the deltas are
  like-for-like. Reading `.import` text alone would not have caught A1, where
  the text changed and the output did not.
- **A1** was settled by running the experiment, not by reasoning about the
  importer.
- **Runtime behaviour** was confirmed with `play_scene` driven through
  Town → Mayor → *The Deep Wood* to a live combat encounter, then
  `capture_frames` to prove animations still deform the mesh rather than
  freezing in a rest pose. A still screenshot could not have shown that.

Where a finding is argued from code rather than observed, it says so.

---

## 2. A-series — the questions doc is wrong

### A1. Q6 declared §2.2.2 blocked. It was not. (resolved this pass)

**The claim.** `QUESTIONS-web-perf.md` Q6 filed the ~10 MB animation strip as a
blocker, on the grounds that Godot's per-clip inclusion is controlled by
`_subresources` entries whose schema could not be safely hand-written, and that
no `execute_editor_script`-equivalent tool exists to drive the import dialog.

**Half of that is right, and it is the half that matters least.** The schema
guess was correct to distrust — but the conclusion ("therefore blocked") skipped
a mechanism that was visible in every one of these `.import` files the whole
time: `import_script/path`.

**What the experiment showed.**

*First*, the `_subresources` route was tested directly. Writing 90 entries of
the form `"ClipName": { "settings/import": false }` into
`skeleton_mage.glb.import` and reimporting produced a `.scn` of **exactly
1,801,721 bytes — byte-identical to the baseline.** The importer parsed the
block without complaint and silently ignored it. Godot 4.7's `ANIMATION`
internal-import category exposes only `loop_mode`, `save_to_file/*`, `slices/*`,
`optimizer/*` and `compression/*`; there is **no per-animation skip**. The one
adjacent lever, `import/skip_import` on the `ANIMATION_NODE` category, removes
the entire `AnimationPlayer` and with it the five clips the game needs.

So Q6 was right that hand-writing subresource entries would not work. It was
wrong that this made the item blocked.

*Second*, the post-import route was tested. `res://tools/strip_unused_animations.gd`
(`@tool extends EditorScenePostImport`) walks the imported scene's
`AnimationPlayer` and removes every clip outside a per-character keep-list,
wired up via `import_script/path` in each `.glb.import`. Result on the same file:

```
[strip_unused_animations] skeleton_mage: removed 90, kept 5
1,801,721 bytes  ->  194,121 bytes      (-89.2%)
```

Applied to all seven characters:

| model | clips before | after | `.scn` before | `.scn` after |
|---|---|---|---|---|
| `knight` | 76 | 6 | 1,296,401 | 293,213 |
| `mage` | 76 | 5 | 1,243,233 | 228,258 |
| `rogue` | 76 | 5 | 1,268,121 | 253,562 |
| `skeleton_mage` | 95 | 5 | 1,801,721 | 194,121 |
| `skeleton_minion` | 95 | 5 | 1,819,366 | 212,500 |
| `skeleton_rogue` | 95 | 5 | 1,828,365 | 222,874 |
| `skeleton_warrior` | 95 | 5 | 1,848,390 | 249,723 |

**Total `.glb` imported payload: 11.09 MB → 2.08 MB.**

**Verified not broken.** The risk here is a silent missing animation on one
character in one state, which no existing test would catch. Three checks:

1. `tests/test_animation_clips.gd` (new, **C1**) — 64 checks, 0 failures.
2. Full suite — 20/20 `RESULT PASS`.
3. Live run — Town → Mayor → *The Deep Wood*, driven to a combat encounter.
   `capture_frames` shows the knight's run cycle deforming across frames, a
   skeleton rendering with correct palette colours, an attack blink, damage
   numbers (`72`), death VFX and gold ticking up. Output log clean.

**Why this matters beyond the 9 MB.** Q6 offered "do it by hand in the editor"
and "strip it in Blender" as the only paths, both of which are manual and
neither of which survives a reimport. The post-import script is applied
automatically on every reimport, is version-controlled, and is pinned by a test.

---

## 3. B-series — asked for, never built

### B1. §3.2's `adjustment` fold was skipped silently

The spec's §3.2 lists four actions. Three are accounted for in the questions
doc (glow → done, MSAA → done, fog → explicitly keep). The fourth is not
mentioned anywhere in the questions doc — not as done, not as a question, not
as deferred:

> **Fold `adjustment` into the materials.** Contrast 1.08 / saturation 1.3 is a
> full-screen colour pass; the same result can be baked into `Tuning`'s palette
> constants once. Minor, but free — *except* that
> `BattleWorld.tween_brightness()` drives `adjustment_brightness` for the
> mage's darkening pass, so `adjustment_enabled` has to stay available. Enable
> it only while that tween is running.

This is a genuine omission rather than a judgment call, and it is the one §3.2
item with a stated subtlety attached, which makes silently dropping it the
worst of the four to drop. `battle_world.tscn` still carries
`adjustment_enabled = true`, `adjustment_contrast = 1.08`,
`adjustment_saturation = 1.3`, and `battle_world.gd:tween_brightness()` still
drives `adjustment_brightness` unconditionally.

**Obligation.** Either implement the gate (enable `adjustment` only for the
duration of `tween_brightness`, bake contrast/saturation into `Tuning`), or
file it as a deliberate deferral with a reason. Do not leave it unrecorded.

Note this is **not** free of visual risk despite the spec calling it "minor":
baking saturation 1.3 into palette constants changes every colour in the game,
including the 2D UI, which does not go through this Environment at all. That
asymmetry is probably why it deserves its own ruling rather than a quick edit —
see **E5**.

### B2. §5's measurement plan is entirely unaddressed

§5 asks for three things before Phase 3 is trusted:

1. Chrome remote debugging against the phone, Performance panel, one encounter
   recorded — to separate GPU wait from main-thread block.
2. `Performance.get_monitor()` for `RENDER_TOTAL_OBJECTS_IN_FRAME`,
   `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `TIME_PROCESS` vs `TIME_PHYSICS_PROCESS`
   surfaced in a debug overlay in the web build.
3. Re-record the same 30-second run after each phase and re-run the frame-delta
   analysis for a like-for-like comparison.

None exist. The questions doc's "Method note" describes how the *changes* were
verified (reimport output, editor errors, screenshots) — which is sound, and
better than the spec asked for on that axis — but it is verification that the
edits landed, not measurement that they helped.

**The practical consequence.** Every §3 GPU item (glow, MSAA, lights,
transparent pass) is currently justified by reasoning about mobile tilers, not
by a number from the device. §2's payload items are safe — bytes are bytes, and
they are measured — but the render items are not, and **the spec itself
sequenced Phase 2 measurement ahead of Phase 3 for exactly this reason.** The
implementation pass did Phase 3 anyway.

That is defensible for MSAA and glow (both trivially reversible, both `.web`-
gated) and it is *not* defensible for E3's light-fold, which is why leaving E3
open was the right call even though it was made for a different reason.

**Obligation.** Item 2 is the cheap one and unblocks the rest: a debug overlay
reading `Performance.get_monitor()` is contained, ships behind the existing
`sir_fish/debug/harness` flag, and turns every later claim into a number.
Recommend building that before any further §3 work.

---

## 4. C-series — test coverage

### C1. `tests/test_animation_clips.gd` (added this pass)

The strip in A1 introduces a new silent-failure mode: `KEEP` in
`strip_unused_animations.gd` is a second copy of what
`CombatantBakedAnimations.CLIPS` references, and the two can drift. Retarget a
hero onto a different clip in `CLIPS` and the strip deletes the clip the game
now needs — a missing animation, on one character, in one state, that no other
test would catch.

The test walks `CLIPS` itself (the source of truth) and asserts every clip it
names survives in the **imported** scene, plus a ceiling check that the strip
still ran at all. 64 checks across seven characters.

Deliberately reads the imported scene, not the `.glb` on disk: the imported
scene is what the strip produces and what the game loads.

### C2. Nothing pins `import_script/path`, and the editor UI resets it

**This is the most likely way A1's fix silently regresses.** Reimporting a
`.glb` through Godot's Import dock — a normal thing to do when adjusting mesh or
material settings — can rewrite the `.import` file and drop
`import_script/path`. The clips come back, the payload quietly grows by 9 MB,
and nothing fails.

`test_animation_clips`'s `MAX_CLIPS_AFTER_STRIP = 12` ceiling catches exactly
this, which is why that assertion is in the test rather than only the
keep-list check. Recorded here so the ceiling is not "simplified away" later as
redundant — it is the regression detector, not a sanity check.

### C3. Nothing pins the web-only render overrides

`msaa_3d.web = 0.0`, `rendering_method.web`, the `OS.has_feature("web")` glow
gate and the export preset's `extensions_support=false` /
`vram_texture_compression/for_desktop=false` are all single values that a
future edit could flip with no visible local effect — they only manifest on a
web export, which nothing in the suite builds.

**Obligation.** A small `test_web_export_settings.gd` asserting the
`ProjectSettings` keys and parsing `export_presets.cfg` for the two preset flags
would pin the lot. Cheap, and it is the only mechanism that would catch a
regression that by definition cannot be seen in the editor.

---

## 5. D-series — hygiene

### D1. Eight icon `.import` files carry line-ending-only uncommitted diffs

`assets/icons/{ui_backpack,weapon_amulet,weapon_helm,weapon_idol,weapon_mail,weapon_ring,weapon_shield}.png.import`
and `assets/blacksmith-bg.png.import` were already modified in the working tree
at the start of this initiative — they are **not** from this work.
`git diff --numstat` reports zero changed lines for them; the only output is
git's CRLF advisory. They are pure line-ending churn.

Harmless, but they make `git status` noisy enough to hide a real change, and
they were briefly mistaken for part of this pass. Either commit or check them
out. Confirmed the edits from *this* pass are genuine content diffs (e.g.
`town-with-purple-mist.png.import` is exactly two lines: `compress/mode` and
`compress/lossy_quality`).

### D2. Two `_scratch_*` scenes are tracked in `tests/`

`tests/_scratch_mage_inspect.tscn` and `tests/_scratch_rogue_inspect.tscn` are
committed. This is the identical finding to the town acceptance spec's C2
(`tests/_scratch_shop_touch.gd`), and the identical convention applies —
CLAUDE.md's own verification recipe says to *delete the scratch files* after
use. Delete both.

---

## 6. E-series — needs a ruling

### E1. 16.51 MB of 1024×1024 UI icons, displayed at ~104 px

**Neither the spec nor the questions doc identified this.** §2.2.3 addressed
only the full-screen background plates. After that fix landed, the plates are
down to 1.04 MB total — and the icon set is now the single largest remaining
category in the build by a factor of sixteen.

Measured PNG payload by folder, current tree:

| folder | shipped | files |
|---|---|---|
| `assets/icons` | **11.88 MB** | 22 |
| `assets/ui/reliquary` | **4.63 MB** | 10 |
| `assets` (backgrounds, post-fix) | 1.04 MB | 7 |
| `assets/meshes` (atlases, post-fix) | 0.01 MB | 7 |

All 32 are **1024×1024**, all lossless (`compress/mode=0`). The largest:
`slot_lightning.png` 0.77 MB, `glyph_shield.png` 0.75 MB, `slot_gold.png`
0.69 MB, `glyph_heal.png` 0.66 MB, `glyph_bow.png` 0.64 MB.

**What they render at.** `hud.tscn`'s backpack icon occupies
`offset_left 24 → offset_right 128` — **104 × 104 px** in the project's
1080-wide design space. The source is 1024 × 1024. That is ~10× oversampled
linearly and ~97× by area. The reliquary chips and slot symbols are smaller
still on screen.

Even taking the worst case on device — `html/canvas_resize_policy=2` with the
canvas backing store at full 1080 physical width, so design space is roughly
1:1 with physical pixels — a 256×256 source carries 2.5× headroom over the
largest of these.

**Estimated win:** 16.51 MB → **~1.5 MB** at 256×256, or ~0.4 MB at 128×128.
That is larger than the animation strip and larger than the atlas fix, and it
is the last big item in the build.

**Why this is E and not B.** Unlike the character atlases (flat palette maps
where 64×64 was provably lossless in effect), these are authored art with
gradients, outlines and fine ornament — `frame_corner.png` and `fleuron.png`
are decorative filigree where downsampling is a visible quality decision, not
a free win. And `item_glyph.gd` draws some of these into a procedurally-sized
rect, so the maximum on-screen size is not a single fixed number I can read off
one scene.

**Ask:** what target size? My recommendation is **256×256 lossless** for the
icon set (safe, ~10× saving, keeps ornament crisp at any plausible display
size), with `frame_corner.png` and `fleuron.png` held at 512 if you want
margin on the filigree. I did not apply this because it is a visual-quality
call across 32 authored assets, which is exactly the class of decision the
questions-doc discipline says to ask about rather than guess.

### E2. Q7 — glow-disabled look still unverified

Unchanged from the questions doc. The `OS.has_feature("web")` gate is in, but
nothing has looked at a battle with glow off. **This pass could have closed it**
— a live combat encounter was driven for A1's verification, and forcing the
flag would have made that screenshot answer Q7 too. It did not, because the
run was scoped to proving animations survived. Cheap to close next time
something drives to combat.

### E3. Q3 — folding `FillLight`/`RimLight` still needs an art ruling

Unchanged, and **B2 strengthens the case for leaving it open**: with no
on-device measurement, there is no number saying how much the two extra lights
actually cost on the target GPU, so the visual risk would be taken blind.
Recommend it stays blocked until B2's overlay exists.

### E4. Q2 — which fonts get MSDF

Unchanged. Still needs either the two-font ruling or a pointer to the specific
damage-number / name-chip labels.

### E5. Does baking §3.2's `adjustment` into `Tuning` change the 2D UI too?

Raised by B1. `adjustment_contrast`/`adjustment_saturation` live on the battle
`WorldEnvironment` and therefore apply to the 3D battle viewport **only** — the
console, modals and HUD never pass through it. Baking those values into
`Tuning`'s palette constants would push the same shift onto every 2D element
that reads those constants, changing screens the post-process never touched.

**Ask:** is the intent to (a) bake only into the constants the 3D materials
read, leaving 2D alone, or (b) accept a global palette shift? This determines
whether B1 is a small contained edit or a full art pass, and it is why B1 is
worth a ruling rather than just an implementation.

---

## 7. F-series — the spec is wrong

### F1. §3.1 is factually wrong about the renderer

§3.1 states:

> `project.godot` contains **no `rendering/renderer/rendering_method` key at
> all**, and `config/features` declares `"Forward Plus"`. There is no `.web`
> override […]

and makes "confirm the web renderer" a whole gated phase ahead of §3.2–3.6.

Read via `get_project_settings(section: "rendering/renderer")`:

```
rendering/renderer/rendering_method         = forward_plus
rendering/renderer/rendering_method.mobile  = mobile
rendering/renderer/rendering_method.web     = gl_compatibility
```

All three are present. The spec's observation came from grepping the
`project.godot` *file*, which only stores non-default values — the `.web` and
`.mobile` entries are Godot 4.7 platform defaults and resolve correctly whether
or not they appear in the file. **Phase 2 was never a real gate.**

Amend §3.1 to record the resolved values and drop the phase, keeping only its
genuinely useful half: that `Vulkan 1.4.341 - Forward+` in the output log is
the *editor's* desktop renderer and must not be read as what the web export
uses.

### F2. §2.2.2's stated mechanism does not exist

§2.2.2 says:

> Godot's Advanced Import Settings dialog writes this as per-animation
> `settings/…/save_to_file` / removal entries under `_subresources`.

There is no per-animation removal entry in Godot 4.7. `save_to_file` extracts a
clip to its own `.tres`; it does not exclude it. See A1 for the experiment.
Amend §2.2.2 to describe the `import_script` / `EditorScenePostImport` route
that actually works, and record the negative result so it is not re-attempted.

### F3. §2.4's budget table is superseded

Measured, same method before and after:

| | spec estimate | **measured actual** |
|---|---|---|
| Character atlases | 18.6 → 0.2 MB | 18.6 → **0.01 MB** |
| Unused animation | 11.1 → 2 MB | 11.09 → **2.08 MB** |
| Background plates | ~8 → ~2 MB | ~8 → **1.04 MB** |
| **Imported assets total** | — | **45.62 → 20.96 MB** (−54%) |

Ahead of projection on every line. The `.pck` itself has **not** been
re-measured — that needs an actual `export_project` run, still open as the
questions doc's Q8. Amend §2.4 to carry actuals and to state plainly that the
pck number remains unverified.

---

## 8. Suggested order

1. **E1** — biggest remaining win in the build, needs only a size ruling.
2. **B2 item 2** (the `Performance.get_monitor()` overlay) — unblocks E3 and
   turns every remaining §3 claim into a number.
3. **C3** then **C2 review** — cheap pins on settings that can only regress
   invisibly.
4. **D1, D2** — hygiene, minutes.
5. **B1/E5** — once E5 is ruled on.
6. **E2** — fold into whatever next drives to combat; near-zero marginal cost.
7. **E3, E4** — after B2.
8. **F1–F3** — amend the spec so the next reader is not misled.

Phase 4 (§3.4, the transparent-pass rework) stays deferred, unchanged.

---

## 9. Changeset from this pass

| file | change |
|---|---|
| `tools/strip_unused_animations.gd` | **new** — A1's post-import strip |
| `tests/test_animation_clips.gd` / `.tscn` | **new** — C1, 64 checks |
| `assets/meshes/{knight,mage,rogue,skeleton_*}.glb.import` | `import_script/path` wired (7 files) |
| `assets/meshes/*_texture.png.import` | 64 px / lossless / no mipmaps (7 files, prior pass) |
| `assets/{blacksmith,inn,mayor}-bg`, `town-*`, `world-map` `.import` | lossy 0.85 (6 files, prior pass) |
| `export_presets.cfg` | `extensions_support=false`, `for_desktop=false`, `exclude_filter` |
| `project.godot` | `msaa_3d.web = 0.0` |
| `scripts/battle/battle_world.gd` | web-only glow gate |

Suite: **20/20 PASS**. Live run: Town → Mayor → *The Deep Wood* → combat,
animations and materials confirmed intact, output log clean.
