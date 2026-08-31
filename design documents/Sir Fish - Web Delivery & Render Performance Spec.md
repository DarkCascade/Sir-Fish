# Sir Fish — Web Delivery & Render Performance Spec

Follow-up to `Sir Fish - Gameplay Smoothness Analysis.md`. That document
attacked the **CPU/runtime** axis — synchronous loads, VFX allocation churn,
ungated `_process`. Most of it has since landed (see *What already shipped*
below), and the recording confirms it worked: the sustained combat band is
better than it was.

This spec covers the two axes that document left open and could not measure:
**what the browser has to download and compile before the game starts**, and
**what the GPU is asked to do per frame once it does**. Both are now measured
against the shipped build rather than inferred.

---

## 0. Correction to the brief: this is a phone, not a desktop

The recording is **Opera on Android**, portrait, not a desktop browser:

- Frame geometry is 1080×2410 — a phone aspect, not a desktop window.
- The capture shows an Android status bar, the Opera bottom tab/`+`/`O` bar,
  and an Opera site menu whose **"Desktop site" toggle is off**.
- The prior analysis assumed iOS Safari. It is Android/Chromium.

This matters for everything below. A desktop GPU eats glow chains, MSAA and a
2048 shadow atlas without noticing. A mobile tile-based GPU does not, and a
mobile browser's memory ceiling makes a ~100 MB download a genuinely different
proposition. **Every recommendation here is sized for mobile.** If desktop is
also a target, these should become `.web` overrides plus a runtime quality
switch, not unconditional downgrades.

---

## 1. What the recording actually shows

994 frames over 30.62 s, variable-frame-rate. The recorder emits a frame when
the composited screen changes, so gaps mean either *the game stalled* or *the
screen was genuinely static* — the two have to be told apart by looking at the
frame content, which I did.

| Window | Screen content | Frames delivered/s | Reading |
| --- | --- | --- | --- |
| 0:00 – 0:02 | Browser chrome, blank page | 2–3 | Page/asset download |
| 0:03 – 0:07 | Opera site menu open over blank page | 58–102 | Browser UI only, game not up |
| **0:08 – 0:13** | **Godot splash, progress bar frozen** | **1** | **~6 s hard stall** |
| 0:14 – 0:16 | Game appears, first render | 14–43 | Startup + first-draw compiles |
| **0:17 – 0:28** | **Combat: attacks, lightning, damage numbers** | **9–33** | **The complaint** |
| 0:29 – 0:30 | Enemy dead, VFX stopped | 62–76 | Recovers immediately |

Two separate defects, not one:

**(a) ~15 seconds to interactive.** The 0:08–0:13 stretch is a *real* stall, not
a static screen — the Godot splash is up with a progress bar that does not
advance, then the game appears at ~0:14. That is the engine WASM compiling and
the `.pck` being parsed. Section 2 is about this.

**(b) Combat still runs at 9–33 fps with 170–400 ms hitches.** Recovery to
62–76 fps within one second of the last VFX ending is the key signal: the
*baseline* scene is fine, and since the CPU-side churn from the prior spec is
largely fixed, what remains is disproportionately **GPU and first-use compile**
cost. Section 3 is about this.

Worst gaps, all inside combat: 402 ms, 377 ms, 352 ms, 259 ms, 242 ms, 225 ms,
209 ms, 202 ms. These are still one-off costs landing on the frame that needs
them, not uniform overdraw.

### What already shipped (do not redo)

Verified present in the current tree:

- `BattleDirector.preload_encounter()` / `_pump_threaded_loads()` —
  `ResourceLoader.load_threaded_request` is in place (`battle_director.gd:135–181`).
- `BattleVfx` now has `_mesh_cache`, `_pool_root`, `_pool_free`, `_acquire()` /
  `_release()` — the per-hit `GPUParticles3D` churn is pooled.
- `SlotReel` calls `set_process(false)` when idle, and halves attract-drift
  `_layout()` via `_drift_layout_pending`.
- `SirFishTank` uses `UPDATE_ONCE`, not `UPDATE_ALWAYS`.
- `MainLayout.set_world_rendering()` disables the battle SubViewport while the
  shop is open.

**Still outstanding from the prior spec:** the font work. All nine fonts remain
`multichannel_signed_distance_field=false` with `subpixel_positioning=4` and
empty `preload`. Carried forward as item 3.5 below.

---

## 2. Startup: the ~15-second cold open

### 2.1 The measured payload

```
builds/web/index.pck        55.5 MB     <-- dominant
builds/web/index.side.wasm  44.1 MB
builds/web/index.js          2.9 MB
builds/web/index.wasm        1.5 MB     (loader stub)
                           ---------
                            ~104 MB uncompressed
```

GitHub Pages applies gzip but **not** Brotli, and offers no way to set custom
headers or serve pre-compressed variants. The WASM gzips well (~4:1). The
`.pck` largely does not — its contents are already-compressed `.ctex` and
`.scn` blobs. **So the 55 MB `.pck` is the real transfer bottleneck, and it is
also the thing being parsed during the 6-second splash freeze.** Fix the pck
first; the WASM is second.

### 2.2 Where the 55 MB pck goes

Computed by resolving every `.import` file to its actual `dest_files` on disk:

```
PNG   33.21 MB
GLB   11.09 MB
TTF    1.32 MB
      --------
      45.62 MB of imported assets
```

#### 2.2.1 Character texture atlases — ~18.6 MB for 13–38 KB of source art

This is the single largest and most clearly wrong item in the build.

| Source PNG | Dimensions | Source size | Ships as |
| --- | --- | --- | --- |
| `knight_knight_texture.png` | 1024×1024 | **13 KB** | 1.33 MB **× 2** |
| `rogue_rogue_texture.png` | 1024×1024 | **16 KB** | 1.33 MB × 2 |
| `mage_mage_texture.png` | 1024×1024 | **38 KB** | 1.33 MB × 2 |
| `skeleton_warrior_skeleton_texture.png` | 1024×1024 | **16 KB** | 1.33 MB × 2 |
| `skeleton_rogue_…` / `skeleton_minion_…` / `skeleton_mage_…` | 1024×1024 | 16 KB each | 1.33 MB × 2 each |

Seven textures × 1.33 MB × 2 formats = **~18.6 MB, a third of the entire pck.**

Two independent causes, both fixable:

1. **`compress/mode=2` (VRAM Compressed) with `mipmaps/generate=true` at
   1024×1024.** VRAM compression is fixed-rate: a 1024×1024 block-compressed
   texture is ~1.3 MB *regardless of how simple the image is*. A 13 KB PNG
   compresses to 13 KB precisely because it is a flat palette atlas — a handful
   of solid colour patches. Block compression throws that entire saving away
   and is, on top of that, the wrong codec for hard-edged flat colour (it
   blocks and rings on the patch boundaries).

2. **`vram_texture_compression/for_desktop=true` *and* `for_mobile=true` in
   `export_presets.cfg`** ships both an `.s3tc.ctex` and an `.etc2.ctex` of
   every VRAM-compressed texture — hence the `× 2`. Confirmed by two `.ctex`
   files per source in `.godot/imported/`.

**Actions**

- **Downscale the character atlases.** These are flat palette maps in the style
  CLAUDE.md §Meshy prescribes ("flat palette materials, no textures"). Set
  `process/size_limit=64` (or re-export the atlases at 64×64). A palette atlas
  carries no spatial detail; at 64×64 with nearest filtering it is visually
  identical. Expected: ~18.6 MB → **< 0.2 MB**.
- **Set `compress/mode=0` (Lossless) on them** once they are small. At 64×64,
  lossless is smaller than block-compressed *and* removes the flat-colour
  ringing artefacts.
- **Set `vram_texture_compression/for_desktop=false`** in the Web preset. Even
  for textures that legitimately want VRAM compression, ETC2 covers every
  WebGL2 target that matters; shipping S3TC alongside doubles the cost for a
  case a mobile browser will never select. Expected: halves whatever VRAM-
  compressed payload survives the change above.
- **Then reconsider whether they are needed at all.** CLAUDE.md's own pipeline
  note says to delete Meshy's baked texture and assign one flat material per
  part. If the seven character models can take `CelMaterials.cel()` per part
  the way the sporecap does, the atlases and their UVs leave the build
  entirely.

#### 2.2.2 Unused animation data — ~10 MB

Every character `.glb` embeds a full KayKit/Meshy action library:

| File | Source | Imported `.scn` | Embedded clips |
| --- | --- | --- | --- |
| `skeleton_warrior.glb` | 4.75 MB | 1.76 MB | **95** |
| `skeleton_rogue.glb` | 4.71 MB | 1.74 MB | **95** |
| `skeleton_minion.glb` | 4.70 MB | 1.74 MB | **95** |
| `skeleton_mage.glb` | 4.65 MB | 1.72 MB | **95** |
| `knight.glb` | 3.57 MB | 1.24 MB | **76** |
| `rogue.glb` | 3.53 MB | 1.24 MB | 76 |
| `mage.glb` | 3.51 MB | 1.21 MB | 76 |

Byte breakdown of `skeleton_warrior.glb`: geometry is **~320 KB total**
(POSITION 71 KB, NORMAL 71 KB, WEIGHTS 78 KB, TEXCOORD 47 KB, INDICES 34 KB,
JOINTS 19 KB) across 5,934 triangles. Everything else — 10,941 accessors,
10,942 bufferViews — is animation.

`CombatantBakedAnimations` references exactly **nine** clip names:
`Idle`, `Running_A`, `Hit_A`, `Death_A`, `Block`, `1H_Melee_Attack_Chop`,
`1H_Ranged_Shoot`, `Spellcast_Shoot`, `Unarmed_Melee_Attack_Punch_A`
(plus `Unarmed_Melee_Attack_Kick`). The other ~86 are imported, packed, shipped
and parsed at load for nothing.

`animation/import=true` in every `.glb.import` keeps all of them.

**Actions**

- Add an **import subresource filter** to each character `.glb.import`, keeping
  only the ~10 referenced clips. Godot's Advanced Import Settings dialog writes
  this as per-animation `settings/…/save_to_file` / removal entries under
  `_subresources`. Expected: ~11.1 MB of `.scn` → **~2 MB**, and a
  correspondingly shorter parse during the splash freeze.
- Alternatively, and more durably: strip the unused actions in Blender before
  export, so the source `.glb`s shrink from ~4.7 MB to ~400 KB and the repo
  stops carrying ~29 MB of dead animation.

*Note:* the orc, sporecap and in-house rigs are unaffected — their clips are
GDScript-authored by `CombatantSkeletonAnimations`, which is why
`sporecap.glb` is 601 KB with zero embedded animations. This item is only about
the seven imported KayKit-style models.

#### 2.2.3 Background plates — ~8 MB

`town-with-purple-mist.png` (864×1536, 1.69 MB shipped), `town_overview.png`
(1.46 MB), `world-map.png` (1.22 MB), `inn-bg.png`, `mayor-bg.png`,
`blacksmith-bg.png`, plus icon plates like `glyph_shield.png` (1024×1024,
1.13 MB source). All are `compress/mode=0` — **Lossless**.

These are painted, photographic-ish backdrops shown behind UI. Lossless PNG is
the wrong storage class for them.

**Action:** set `compress/mode=1` (Lossy / WebP) with
`compress/lossy_quality≈0.85` on every full-screen background plate. VRAM cost
is unchanged (they decompress to the same RAM image); the *download* drops by
roughly 4–6×. Expected: ~8 MB → **~1.5–2 MB**. Leave crisp UI glyphs and
anything with hard edges on lossless.

#### 2.2.4 Export filter

`export_filter="all_resources"` exports everything under the project, including
the entire `addons/godot_mcp/` tree (1.1 MB, seven `skills.*.md` localisations,
editor-only UI and command scripts) and any orphaned art.

**Action:** switch to `export_filter="scenes"` (resources reachable from the
main scene) plus an explicit `include_filter` for anything loaded by path
string, or keep `all_resources` and add
`exclude_filter="addons/godot_mcp/*,*.md,*.blend"`. Smaller win than the
above — low single-digit MB — but free.

### 2.3 The 44 MB side module

`variant/extensions_support=true` in the Web preset makes Godot emit the engine
as an Emscripten **main module + side module** pair for dynamic linking
(`index.wasm` 1.5 MB loader + `index.side.wasm` 44.1 MB engine) instead of one
statically-linked binary.

This project ships **no GDExtensions** — `addons/godot_mcp` and
`addons/script-ide` are both pure GDScript.

**Action:** set `variant/extensions_support=false` and re-export.

The download saving is modest (a monolithic build lands around 40–45 MB, so
call it a few MB after the loader stub goes away). The reason to do it is
**compile and startup time**: side modules are built `-fPIC` with all
cross-module calls going through an indirection table, which blocks
whole-program optimisation and inlining, and the browser has to instantiate and
link two modules instead of one. This is a prime suspect for the 6-second
splash freeze.

*Measure this one specifically* — export both ways, compare time-to-first-frame
on the same device. It is a one-line change and a full re-export, so the
experiment is cheap.

### 2.4 Startup budget

| Item | Now | After | Saving |
| --- | --- | --- | --- |
| Character atlases (2.2.1) | 18.6 MB | ~0.2 MB | **18.4 MB** |
| Unused animation (2.2.2) | 11.1 MB | ~2 MB | **9.1 MB** |
| Background plates (2.2.3) | ~8 MB | ~2 MB | **6 MB** |
| Export filter (2.2.4) | — | — | ~1–3 MB |
| **`.pck` total** | **55.5 MB** | **~20 MB** | **~35 MB** |
| Side module (2.3) | 45.6 MB | ~42 MB | ~3 MB + link time |

A ~64 % smaller pck, on a payload that gzip cannot help with, on a phone.

---

## 3. Render pipeline: the combat frame

The 3D world renders into a SubViewport at a fixed **1080×764** (`main.tscn`
`BattleView` → `BattleViewport`, sized by the stretch container). That is
0.83 MP per frame — bounded, but not cheap given what is stacked on it.

### 3.1 Confirm the web renderer — do this before anything else in §3

`project.godot` contains **no `rendering/renderer/rendering_method` key at all**,
and `config/features` declares `"Forward Plus"`. There is no `.web` override,
though the project already uses that mechanism elsewhere
(`lights_and_shadows/directional_shadow/size.web=2048`).

Every other item in this section behaves differently between Forward+ and
Compatibility — light-count shader variants, glow blit chains, MSAA resolve
cost, and whether transparent-pass objects get clustered light culling at all.

**Action:** set `rendering/renderer/rendering_method.web="gl_compatibility"`
explicitly and confirm on-device via `RenderingServer.get_video_adapter_name()`
/ `OS.get_video_adapter_driver_info()` logged at boot. Do not tune §3.2–3.6
against a guess.

### 3.2 Post-processing stack

`scenes/battle/battle_world.tscn` `Environment`:

```
glow_enabled = true          glow_intensity 0.7, bloom 0.12, hdr_threshold 1.15
fog_enabled = true           fog_mode 1 (depth), density 1.0
adjustment_enabled = true    contrast 1.08, saturation 1.3
tonemap_mode = 2             (Filmic)
```

plus `project.godot` `anti_aliasing/quality/msaa_3d=1.0` (2× MSAA).

**Glow is the expensive one.** It is a downsample/upsample blit chain — several
extra full-viewport passes per frame. On a tile-based mobile GPU each pass is a
separate render target bind and tile flush, which is exactly the class of cost
that does not show up on the desktop editor preview the art was tuned in.

MSAA 2× on a tiler costs bandwidth and a resolve on every tile.

**Actions**, in descending expected value, each as a `.web` override or a
runtime quality tier:

- **Disable glow on web** and see whether the look survives. The cel shader's
  banding, the emissive crystal materials and `Tuning`'s palette carry most of
  the visual identity; glow at intensity 0.7 / bloom 0.12 is a light touch that
  may not be worth several full-screen passes. If it is needed, compensate by
  raising `emission_strength` on the crystals and the VFX.
- **`anti_aliasing/quality/msaa_3d.web = 0`.** The art is flat-shaded chunky
  geometry with an inverted-hull outline — the outline already does the job
  MSAA would, and at 1080 px wide on a ~400 px-wide CSS viewport the canvas is
  supersampled by the device pixel ratio anyway.
- **Keep fog.** It is a cheap per-fragment blend and it is doing real work in
  the composition (the horizon fade in the recording).
- **Fold `adjustment` into the materials.** Contrast 1.08 / saturation 1.3 is a
  full-screen colour pass; the same result can be baked into `Tuning`'s palette
  constants once. Minor, but free — *except* that
  `BattleWorld.tween_brightness()` drives `adjustment_brightness` for the
  mage's darkening pass, so `adjustment_enabled` has to stay available. Enable
  it only while that tween is running.

### 3.3 Three directional lights against a custom `light()` function

`battle_world.tscn` carries `KeyLight` (shadows on, 2048 atlas, 48-unit range),
`FillLight` and `RimLight`.

`cel_shade.gdshader` declares a custom `void light()`. A custom light function
runs **once per light per fragment**, and it is not a trivial one — two
normalizes, a `round`, a `mix`, a `smoothstep` and a second `dot` against VIEW
for the rim term. Three directional lights triples all of that on every cel-
shaded pixel.

**Action:** fold `FillLight` and `RimLight` into `ambient_light_energy` and the
shader's existing `shadow_tint` / `rim_color` uniforms. The cel shader already
computes its own rim term from `NORMAL·VIEW` — it does not need a light for it.
Expected: roughly a 3× reduction in cel-shader fragment cost, for a look that
should be recoverable by tuning `shadow_tint` and `ambient_light_energy`.

### 3.4 Everything cel-shaded is in the transparent pass

`cel_shade.gdshader` declares `render_mode blend_mix, …, depth_draw_always`,
and `cel_materials.gd`'s header records why: `blend_mix` on the outline shader
moved the inverted hull into the transparent pass, and `depth_draw_always` is
what keeps the hull from swallowing the body.

The consequence is that **every character and every cel-shaded prop renders in
the transparent pass**, which means no early-Z rejection, back-to-front sorting,
and — on a tiler — no benefit from hidden-surface removal. Each character also
draws twice (body + `next_pass` outline hull).

`cel_materials.gd`'s own comment says "The scene has far fewer than 40 meshes,
so the sorting cost is irrelevant." That is true of *sorting*. It is not true of
**overdraw and lost early-Z**, which is the actual cost on a mobile tiler and
was not what that note was assessing.

**Action — investigate, do not blind-fix.** The load-bearing constraint is only
that the body writes depth *before* the hull tests against it. That is
achievable in the opaque pass, where it is the default:

- Try `render_mode blend_mix` → **removed** on `cel_shade.gdshader`, keeping
  `depth_draw_opaque`, and route the fade-out path through
  `CelMaterials.fade()` swapping to a separate transparent variant only while
  a character is actually fading. Both shaders stay; only the common case moves
  to opaque.
- The blocker is `CelMaterials.fade()`, which currently relies on a single
  always-transparent material so a fade needs no swap. A two-material scheme
  costs one swap at the start and end of a fade — a rare event — in exchange
  for early-Z on every frame.
- The smoke shader (`depth_draw_never`) and the ground plane's deliberate
  `StandardMaterial3D` opacity must both keep working; `overworld_field.gd`'s
  header documents exactly what breaks if the ground moves passes.

This is the highest-risk item in the spec and the one with the largest
potential GPU win. It should be prototyped behind a flag and screenshot-diffed
before it is committed.

### 3.5 Font rasterization (carried over from the prior spec)

All nine fonts: `multichannel_signed_distance_field=false`,
`subpixel_positioning=4`, `preload=[]`. Every new glyph at every new size is
rasterized on the main thread on first draw, with up to four sub-pixel variants
each. Damage numbers and the enemy name chip are first drawn mid-combat — which
lines up with the 200–400 ms hitches that persist after the VFX pooling landed.

**Action:** set `multichannel_signed_distance_field=true` on the UI fonts.
MSDF rasterizes once and scales, which also removes the per-size cost the
responsive layout keeps triggering. Where MSDF is unacceptable (small serif
body text can soften), fill in `preload` with the actual glyph ranges and sizes
instead.

### 3.6 Shader warm-up

Still absent. `CelMaterials` builds fresh `ShaderMaterial`s per spawn and
`BattleVfx._unshaded()` builds materials per effect flavour. Each distinct
feature combination compiles on the frame that first needs it.

**Action:** at load, behind the loading screen, render one throwaway frame
containing a 1-pixel instance of every material variant the game uses — cel,
cel+outline, smoke, flat, unshaded, unshaded+billboard, unshaded+additive, and
each particle process material. `ResourceLoader` will not do this; it needs an
actual draw. This is the standard fix for first-use compile hitches and it
directly targets the residual 200–400 ms combat gaps.

---

## 4. Sequencing

**Phase 1 — build hygiene.** No code changes, no visual risk, largest measured
win. Items 2.2.1 (atlases), 2.2.2 (animation filter), 2.2.3 (background
compression), 2.2.4 (export filter), 2.3 (extensions off). Re-export, measure
time-to-first-frame on the same device.

**Phase 2 — confirm the renderer.** Item 3.1. One line, but §3 cannot be tuned
without it.

**Phase 3 — cheap GPU wins.** Items 3.2 (glow/MSAA `.web` overrides), 3.3
(fold two directional lights), 3.5 (MSDF fonts), 3.6 (shader warm-up). All
reversible, all measurable independently.

**Phase 4 — the transparent-pass rework.** Item 3.4, only once Phases 1–3 are
measured, and only behind a flag with screenshot diffs.

## 5. How to measure

The prior spec's caveat stands and is worth repeating: frame timing extracted
from a VFR screen capture shows **when** the main thread stalled, not **what**
it stalled on. Everything above is attribution from reading code and measuring
build artefacts, not from an on-device profile.

Before Phase 3, get a real trace:

- Chrome remote debugging (`chrome://inspect`) against the phone, Performance
  panel, record one encounter. This separates GPU wait from main-thread block —
  which is the exact ambiguity §3 is currently reasoning around.
- Log `Performance.get_monitor()` for `RENDER_TOTAL_OBJECTS_IN_FRAME`,
  `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `TIME_PROCESS` vs `TIME_PHYSICS_PROCESS`
  to a debug overlay in the web build, so the split between engine render time
  and GDScript time is visible on the device rather than inferred.
- For Phase 1, the metric is simply artefact size and time-to-first-frame; no
  profiler needed.

Re-record the same 30-second run after each phase, on the same device and
browser, and re-run the frame-delta analysis for a like-for-like comparison.
