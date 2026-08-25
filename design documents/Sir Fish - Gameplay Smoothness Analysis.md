# Sir Fish — Gameplay Smoothness Analysis

Three suggestions for smoothing out the choppiness that starts when combat
begins, drawn from a screen recording of the live web build
(`darkcascade.github.io/Sir-Fish`, iOS Safari, portrait) plus a read of the
combat, VFX and console code paths.

Each suggestion names the specific code that causes the cost, so the fixes can
be scoped and sequenced rather than taken as general advice.

---

## What the recording actually shows

The capture is variable-frame-rate: the recorder emits a frame when the
composited screen changes, so delivered frames per second tracks the game's
real output closely here — the reels are animating continuously, so every game
frame is a screen change.

| Window | What is happening | Delivered frames/sec |
| --- | --- | --- |
| 0:03 – 0:07 | Party running, field scrolling, reels drifting | **88 – 102** |
| 0:14 – 0:16 | Encounter approaching | **42 – 43** |
| 0:17 – 0:28 | Combat: attacks, slot lightning, damage numbers | **9 – 33** |
| 0:29 – 0:30 | Enemy dying, VFX stop, reels still moving | **62 – 76** |

(The 0:08 – 0:13 stretch reads as ~1 fps because the screen is static there —
nothing for the recorder to capture. It is not a stall.)

Two things stand out:

1. **The drop is combat-shaped.** Frame delivery recovers to 62–76/sec within a
   second of the last VFX finishing, while the field, the reels, the 3D scene
   and the whole UI are all still running. Nothing about the *baseline* scene is
   too heavy. The cost arrives with combat and leaves with it.

2. **The stalls are long and discrete, not a uniform slowdown.** Frames arrive
   in ~10 ms bursts separated by long gaps — the signature of the main thread
   blocking and the compositor then flushing a backlog. The worst gaps:

   | Time | Gap | Coincides with |
   | --- | --- | --- |
   | 0:17.57 | **783 ms** | Encounter start — enemies spawning |
   | 0:20.08 | **402 ms** | First slot-lightning strike |
   | 0:17.19 | **386 ms** | Encounter start |
   | 0:19.73 | **352 ms** | First melee blink + damage numbers |
   | 0:21.31 | **259 ms** | Combat exchange |
   | 0:23.03 | **242 ms** | Combat exchange |

   A ~780 ms freeze is not a frame-budget overrun. That is a synchronous
   one-time cost — loading, compiling, or rasterizing something — happening on
   the frame that needs it.

The three suggestions below map onto that shape: **(1)** the discrete freezes at
encounter start and first-use of each effect, **(2)** the sustained cost of the
combat loop itself, **(3)** the constant background cost that eats the headroom
the other two need.

One environmental note that colours all three: `export_presets.cfg` sets
`variant/thread_support=false`, so this is a single-threaded web build.
*Everything* — resource loading, shader compilation, GDScript, physics, glyph
rasterization — runs on the browser main thread. There is no worker to hide a
stall behind. Anything that blocks, blocks the frame.

Godot also ships web builds on the **Compatibility (WebGL2)** backend by
default, not the Forward+ path the editor previews with, and `project.godot`
carries no explicit `rendering/renderer/rendering_method.web` override. Worth
confirming, because several costs below (light-count shader variants, glow
blit chains) behave quite differently between the two.

---

## Suggestion 1 — Move loading and shader work off the encounter frame

**The 783 ms freeze at 0:17.57 is almost certainly this line:**

```gdscript
# scripts/battle/battle_director.gd:116
var packed: PackedScene = load(stats.scene_path)
var c := packed.instantiate() as Combatant
```

A synchronous `load()` at the moment an enemy spawns. The scenes it pulls in
reference the skeleton models, which are the largest assets in the project:

```
4.9 MB  assets/meshes/skeleton_warrior.glb
4.8 MB  assets/meshes/skeleton_rogue.glb
4.8 MB  assets/meshes/skeleton_minion.glb
4.8 MB  assets/meshes/skeleton_mage.glb
3.7 MB  assets/meshes/knight.glb
```

On the first encounter with a given enemy type, that call blocks the main
thread while Godot parses the scene, decompresses the mesh and its textures,
and uploads them to the GPU. Single-threaded, nothing else runs. There is no
`load_threaded_request` anywhere in `scripts/`, and no preload cache — this is
the only spawn path, so the cost lands the first time every enemy type appears.

Three further one-time costs stack onto the same frames:

- **Shader variant compilation.** `CelMaterials` builds fresh `ShaderMaterial`
  instances per spawn (`scripts/battle/cel_materials.gd:18, 33, 40, 50`), and
  `BattleVfx._unshaded()` (`battle_vfx.gd:23`) builds a fresh
  `StandardMaterial3D` for every effect. Each distinct feature combination —
  unshaded + alpha + cull-disabled, plus billboard, plus additive blend —
  compiles its shader on first use, on the frame that first needs it. That maps
  neatly onto the 402 ms and 352 ms gaps: the first lightning strike, the first
  blink.

- **Runtime lights.** `lightning_bolt`, `magic_burst` and `explosion` each add
  an `OmniLight3D` to the scene at fire time (`battle_vfx.gd:383, 466, 501`).
  On the Compatibility backend, changing the set of lights affecting an object
  can pull in a different shader variant — a compile, mid-combat, on the frame
  the spell lands. The scene already carries three `DirectionalLight3D`s
  (`scenes/battle/battle_world.tscn`), so these arrive on top of a light setup
  that is not cheap to begin with.

- **Glyph rasterization.** Every font is imported with
  `multichannel_signed_distance_field=false`, `preload=[]` and
  `subpixel_positioning=4`. No glyphs are cached at import, so each new glyph at
  each new size is rasterized on the main thread the first time it is drawn —
  and with subpixel positioning, up to four sub-pixel variants per glyph. Damage
  numbers and the enemy name chip are the first text drawn at their sizes.

**What to do**

- Warm the encounter before it starts. The party runs toward the fight for
  several seconds — that is the budget. Kick off
  `ResourceLoader.load_threaded_request()` for the upcoming encounter's
  combatant scenes when the run-in begins, and `load_threaded_get()` at spawn.
  Even single-threaded, moving the parse off the spawn frame turns one 780 ms
  freeze into work spread across frames that have slack.
- Warm the shaders too. Render one throwaway frame containing one instance of
  every material variant the game uses — off-screen, tiny, at load — so the
  compiles happen behind the loading screen instead of behind the first
  fireball. Godot's `ResourceLoader` will not do this for you; it needs an
  actual draw.
- Set `multichannel_signed_distance_field=true` on the UI fonts, or fill in
  `preload` with the glyph ranges and sizes actually used. MSDF rasterizes once
  and scales, which also removes the per-size cost when the responsive layout
  changes font sizes.
- Consider whether the skeleton `.glb`s need to be 4.8 MB. They are four
  variants of the same silhouette; if they share a skeleton, sharing the mesh
  and recolouring at runtime (which `CombatantRig` already does for the orc
  pair, `combatant_rig.gd`) would cut both load time and VRAM by roughly 4×.

---

## Suggestion 2 — Stop rebuilding every effect from scratch on every hit

`BattleVfx` constructs each effect out of brand-new nodes and brand-new
resources, then frees them. Nothing is shared and nothing is pooled.

Count one melee attack. `Combatant._attack_sequence` (`combatant.gd:272–302`)
runs `blink_out` → `blink_trail` → `slash_arc` → `blink_in`, then blinks home,
which runs `blink_out` → `blink_trail` → `blink_in` again. Adding up what those
allocate:

| | Nodes | Resources | Tweens | Timers |
| --- | --- | --- | --- | --- |
| Attack leg | 13 | 32 | 11 | 2 |
| Return leg | 12 | 30 | 10 | 2 |
| **Round trip** | **25** | **62** | **21** | **4** |

Plus the overlay's own `instantiate()` calls for the damage number, the
detaching health chunk and any status icon (`battle_overlay.gd:115, 148, 165`).

The single worst offender is `_burst()` (`battle_vfx.gd:78`), called four times
in that round trip. Every call builds:

```gdscript
var p := GPUParticles3D.new()
var pm := ParticleProcessMaterial.new()   # a particle shader
var grad := Gradient.new()
var gt := GradientTexture1D.new()         # a texture upload
var bm := BoxMesh.new()
p.material_override = _unshaded(Color.WHITE)   # another material
```

A fresh particle process material, a fresh gradient texture uploaded to the
GPU, and a fresh draw mesh — for a dust puff. `blink_trail` is similar: five
afterimages, each with its own `CylinderMesh` and its own material, all
identical apart from position. `lightning_bolt` builds a new `ImmediateMesh`
per strike (`_ribbon`, `battle_vfx.gd:416`), which means a new GPU buffer
allocation every time the slot pays lightning — which, in the recording, is
often.

At the pace visible from 0:19 onward — three heroes plus enemies, attacks
overlapping — this is hundreds of node and resource create/destroy cycles per
second, every one of them on the browser main thread, every one of them
producing garbage for the engine to reclaim. That is the sustained 9–33 fps
band, as distinct from the discrete freezes in Suggestion 1.

**What to do**

- **Share the immutable resources.** The meshes and materials in `BattleVfx`
  are per-effect-type constants wearing a per-call disguise. Hoist them to
  `static var`s built once: one `TorusMesh` for rings, one `CylinderMesh` for
  ghosts, one `QuadMesh`, one `BoxMesh` for burst particles, and one material
  per feature combination. Where an effect tweens colour or alpha, drive it
  through `set_instance_shader_parameter()` on the `MeshInstance3D` instead of
  mutating a private material — that keeps the material shared *and* keeps the
  instances batchable, which they currently are not.
- **Pool the nodes.** Effects have short, bounded lifetimes and a small set of
  shapes. A free-list keyed by effect type, with nodes hidden and reset rather
  than freed, removes the allocation churn entirely. The blink ghosts are the
  obvious first candidate: always exactly `TELEPORT_GHOSTS` (5), always the
  same mesh, twice per attack.
- **Pool the particle systems hardest.** Four `GPUParticles3D` per attack, each
  with a freshly compiled process material and a freshly uploaded gradient
  texture, is the most expensive thing in this file per unit of visual payoff.
  Pre-build one emitter per burst *flavour* (dust, motes, gold, death), keep
  them parented and idle, and `restart()` them at a new position. The gradient
  and process material then compile once, at load, instead of per hit.
- **Reuse the bolt mesh.** Keep one `ImmediateMesh` for the lightning ribbon
  and rewrite its surface per strike rather than allocating a new one.
- **Reconsider the runtime `OmniLight3D`s.** Three of them across
  `lightning_bolt`, `magic_burst` and `explosion`. If the flash reads
  acceptably as emissive geometry plus the existing glow, dropping the lights
  removes both the variant-compile risk and a per-frame lighting cost during
  exactly the busiest moments.

None of this changes how anything looks. It is the same effects, built once
instead of every time.

---

## Suggestion 3 — Run processes on demand

There is not a single `set_process(false)` call in `scripts/`. Ten scripts
define `_process`, and most of them do real work every frame whether or not
anything changed. This is the headroom that Suggestions 1 and 2 need in order
to show up as smoothness rather than as a slightly less bad stall.

The codebase already has the right pattern — `OverworldField._process`
(`overworld_field.gd:61`) opens with `if is_zero_approx(scroll_speed): return`,
and `BattleWorld._process` early-outs when there is no camera shake. The
following do not:

- **`BattleOverlay._process` (`battle_overlay.gd:37`).** For every tracked
  combatant, every frame: `cam.unproject_position()`, a `Control.position`
  write, a visibility check and a `refresh()`. Setting `position` and `size` on
  a `Control` dirties its layout, which propagates through the container chain.
  This runs at full rate for every combatant on screen even when nobody's
  health or cooldown has changed.

- **`PartyBars._process` (`party_bars.gd:31`).** Calls `bars.refresh()` for
  every hero, unconditionally. `HeroBars.refresh` (`hero_bars.gd:110`) then
  formats `"%d / %d" % [current_hp, max_hp]` every frame per hero — a fresh
  `String` and a fresh `Array` allocated 3× per frame purely to compare equal
  to what is already there. `Label.set_text` does early-out on an unchanged
  string, so this does not re-shape text, but the allocation is pure waste, and
  `cooldown_fill.size.x = ...` in `CombatantBars.refresh` dirties layout every
  frame regardless.

- **`SlotReel._process` (`slot_reel.gd:64`).** Calls `_layout()` on every frame
  forever — the reels never stop, they only slow to attract drift
  (`slot_machine.gd:107`). `_layout()` touches all five cells: `set_symbol()`,
  a `position` write and a `modulate.a` write each. While spinning at 26 stops
  per second, each cell's symbol changes ~26×/sec, so across three reels that
  is roughly **390 `_draw_gem()` calls per second**. Each one
  (`slot_symbol.gd:103`) allocates three `PackedVector2Array`s and issues two
  filled polygons plus four `draw_polyline`s — and width-ed polylines are
  tessellated to triangle strips on the CPU. Call it ~2,300 canvas draw
  commands per second, running through the whole fight.

- **The fish tank viewport.** `sir_fish_tank.tscn:313` sets
  `render_target_update_mode = 4` (`UPDATE_ALWAYS`) on a `SubViewport` with
  `own_world_3d = true` and its own camera and directional light. It is only
  164×164, so the pixel cost is trivial — but it is a **second 3D world
  rendered every frame**, with its own render-target bind and state setup. On a
  tile-based mobile GPU each extra render target is a tile flush. It renders at
  full rate whether or not the fish is doing anything.

**What to do**

- Give `BattleOverlay` and `PartyBars` a dirty flag. They are already fed by
  `EventBus` signals for damage and healing; let the signals drive `refresh()`
  and let `_process` handle only the screen-position tracking — and even that
  only while the camera or a combatant is actually moving.
- In `HeroBars.refresh`, cache the last-formatted HP string and skip the
  `%` formatting when the numbers have not changed. Same for the cooldown fill
  width: compare before assigning, so an unchanged bar does not dirty layout.
- `set_process(false)` on `SlotReel` when it is neither spinning nor drifting,
  and skip the redundant writes in `_layout()` — `cell.position` and
  `cell.modulate.a` only need writing when they change. If the reels stay
  visually acceptable, consider dropping attract-drift `_layout()` to every
  other frame; at 15% of spin speed nobody will read the difference.
- Cheapen `_draw_gem`. The three glow polylines are three CPU-tessellated
  strips per symbol per redraw. Either precompute the mapped point arrays once
  per cell size (they only change when `size` changes) instead of rebuilding
  three `PackedVector2Array`s per draw, or render the glyphs to a small
  `ImageTexture` atlas once at startup and `draw_texture_rect` them — a reel
  symbol is a fixed shape at a fixed size, so redrawing its geometry 390 times
  a second is buying nothing.
- Switch the fish tank to `UPDATE_WHEN_VISIBLE`, and consider dropping it to
  `UPDATE_ONCE` driven by a timer at ~20 Hz while the fish idles.

---

## Worth checking, lower confidence

These are cheap to test and plausible contributors, but the recording does not
isolate them the way it does the three above.

- **Post-processing on a mobile GPU.** `battle_world.tscn` enables `glow`,
  depth `fog`, and colour `adjustment`, and `project.godot` sets
  `msaa_3d = 1.0` (2×). Glow in particular is a downsample/upsample blit chain
  — several extra full-viewport passes over the 1080×640 battle viewport, every
  frame. Try disabling glow on web specifically (`.web` project-setting
  overrides already exist here for shadow size) and measure. The art may not
  need it: the cel shader and the emissive materials carry a lot of the look on
  their own.
- **Three directional lights, one with shadows.** `KeyLight` casts shadows over
  a 48-unit range into a 2048 atlas. The scatter is ~1,580 near props across
  three field copies plus 210 backdrop trees; shadow casters render a second
  time. `overworld_field.gd` already turns `cast_shadow` off for most of it —
  worth confirming nothing large is still casting, and worth testing whether
  `FillLight` and `RimLight` can fold into ambient.
- **Device pixel ratio.** The battle viewport is a fixed 1080×640, so the 3D
  cost is bounded, but the 2D console and overlay render at the canvas
  resolution, which on a modern iPhone can be 3× CSS pixels. Check what
  `html/canvas_resize_policy=2` resolves to on device; capping the backing
  store is a large, cheap win if it is currently rendering at 3×.
- **MCP autoloads.** `MCPScreenshot`, `MCPInputService` and `MCPGameInspector`
  ship in the web build. They are correctly gated —
  `set_process(OS.has_feature("editor"))` — so they are inert at runtime and
  are **not** a per-frame cost. Noted only so nobody re-investigates them.

---

## Suggested order

1. **Suggestion 1** first. The 783 ms encounter-start freeze is the single most
   visible defect and threaded preloading is a contained change to one call
   site in `battle_director.gd`.
2. **Suggestion 3** next. Mechanical, low-risk, no visual change, and it frees
   the headroom the rest needs.
3. **Suggestion 2** last. The biggest win and the biggest diff — but with 1 and
   3 done, the combat loop has room to breathe while `BattleVfx` is reworked
   effect by effect.

## Method

Frame timing was extracted from the recording with
`ffmpeg -vf showinfo`, taking `pts_time` deltas across all 994 frames of the
30.6 s capture. Because the source is variable-frame-rate screen capture, the
numbers measure *delivered/composited* frames, not a profiler trace — they show
when the main thread stalled, not what it stalled on. The attribution to
specific code is from reading the call paths, not from an on-device profile.
Confirming with Godot's own frame profiler on a debug web build (or Safari's
Web Inspector timeline against the release build) before committing to the
larger reworks would be worth the hour.
