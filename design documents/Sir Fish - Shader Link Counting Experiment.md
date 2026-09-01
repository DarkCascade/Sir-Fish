# Sir Fish — Shader Link Counting Experiment

A four-variant experiment to find out which of the ten expensive WebGL shader
program links can actually be eliminated from the town → expedition transition.

Follow-up to `Sir Fish - Web Delivery & Render Performance Spec.md`. That spec
reasoned about GPU cost from reading code; this one measures the single defect
that the 2026-09-01 Firefox profile showed to be dominant, and which no prior
document anticipated.

---

## 0. What the profile established

Captured on desktop Windows Firefox against `darkcascade.github.io/Sir-Fish`,
one town → expedition transition:

| | |
| --- | --- |
| `pointerdown` on the quest button | t = 1731 ms |
| `click` → `_accept()` → `SceneRouter.go(QUEST)` | t = 1877 ms |
| `SaveGame.save_profile()` (14 IndexedDB writes) | ~2.4 ms — negligible |
| Scene swap frame (`change_scene_to_file` + `RunController._ready()` + `spawn_party()`) | 285 ms callback, **273 ms main-thread CPU** |
| **Freeze block 1** — one rAF callback | **8,361 ms** |
| **Freeze block 2** — one rAF callback | **4,409 ms** |
| Expedition renders | t = 15,111 ms |

Inside those two callbacks:

| | events | total |
| --- | --- | --- |
| `PWebGL::Msg_GetLinkResult` (program link) | **61** | **11,715 ms** |
| `PWebGL::Msg_GetCompileResult` (shader compile) | 122 | 729 ms |
| | | **12,444 ms = 97% of the freeze** |

Every one of those 61 links and 122 compiles falls inside the two blocks; zero
occur anywhere else in the 17-second capture. `122 = 61 × 2` — one vertex and
one fragment shader per program.

Two further facts that shape the variants below:

- **Ten links are 9,729 ms — 83% of all link time.** The other 51 together are
  1,986 ms. Only those ten are worth attacking.
- **Those ten arrive in five near-identical-duration pairs**
  (963.5 / 963.5, 627.0 / 631.7, 1217.6 / 1213.9, 1028.5 / 1066.0, 988.5 / 1028.4).
  The project contains **exactly five `shader_type spatial` shaders** —
  `cel_shade`, `outline`, `smoke`, `parallax_layer`, `water`.

The mechanism: Godot's Compatibility backend calls
`glGetProgramiv(GL_LINK_STATUS)` immediately after `glLinkProgram`. In ANGLE a
link is lazy until someone asks for the result, so asking immediately turns each
link into a **blocking IPC wait on the GPU process**. Only 1,442 ms of CPU is
captured across all 59 threads during the 12,773 ms window — the rest is in
unsampled driver compile threads.

### What is *not* the cause

Ruled out directly from the profile, so nobody re-investigates:

- **Asset loading.** Grepping every sampled function for
  `inflate|zlib|zstd|decompress|IDB|FileRead|fetch|blob` returns nothing. The
  whole `.pck` is already in memory by then — Godot's web export downloads it
  before boot — so a runtime `load()` is a memory parse. The entire scene swap
  including `spawn_party()`'s three KayKit hero meshes costs 273 ms.
- **The `web-performance` branch's payload work.** Shrinking the `.pck` from
  55 MB attacks time-to-first-frame. This freeze happens long after everything
  is resident.
- **Light count.** In the Compatibility renderer the directional light count is
  a runtime loop bound, not a compile-time `#define`, so the generated shader
  source is identical for one light or three. Variant A tests this explicitly.

---

## 1. Hypotheses

**H1 — the pairs are `color pass` + `shadow pass`.** Every shadow-casting
material needs a depth-pass program as well as a colour-pass one. `KeyLight`
casts shadows (2048 atlas on web, `directional_shadow_max_distance = 48`).
*Predicts:* turning the shadow off halves the expensive links, 10 → 5.

**H2 — the pairs are `static` + `skinned` vertex variants.** Skinning changes
the vertex stage while the fragment stage stays identical, which would also
produce near-identical durations. *Predicts:* shadow removal changes nothing,
and the split tracks when characters first rasterize.

**H3 — one spatial shader produces one pair, whatever the pairing mechanism.**
Five shaders, five pairs. *Predicts:* removing one spatial shader from the scene
removes exactly two expensive links.

H1 and H2 are mutually exclusive. H3 is compatible with either and is the one
that turns the result into a shopping list.

---

## 2. The primary metric is `links`, not `link_ms`

Link *time* is a property of the GPU driver — this capture is Windows Firefox,
which goes GLSL → ANGLE → HLSL → D3D11, notoriously the slowest path. Android
Chromium talks to a native GLES driver and will produce different milliseconds.

Link *count* is a property of the engine and the scene, and is identical on
every platform. **So the structural question can be answered on desktop**, which
is enormously cheaper to iterate on. Only re-measure absolute milliseconds on
the real target device, and only once the count is settled.

---

## 3. Variants

Each is a single reversible edit from the current working tree. Run them one at
a time — the point is to attribute links to causes, which stacking defeats.

### A — Baseline (control)

No edit. The current tree already carries the lighting change from the
2-light pass: `RimLight.visible = false`, `KeyLight` 0.75, `FillLight` 0.95,
`ambient_light_energy` 0.5.

**Predicts `links = 61`, unchanged from the 3-light reference capture.** If the
count moves, the "light count is a uniform, not a variant" claim in §0 is wrong
and H1/H2 both need rethinking before continuing.

### B — No directional shadow

`scenes/battle/battle_world.tscn`, node `KeyLight`:

```
shadow_enabled = false
```

Discriminates **H1 vs H2**. If `big_links` drops 10 → ~5 and `big_ms` roughly
halves, the pairs are colour+shadow and disabling shadows on web is worth
roughly 5 seconds on its own. If nothing changes, H1 is dead and H2 is the
live explanation.

*Note:* this is a look change — `KeyLight` is the only shadow caster, so the
party loses its ground shadow. Judge that separately; here it is a probe.

### C — No fish tank

`scenes/console/status_panel.tscn`, node `Layout/ResourceRow/SirFishTank`:

```
visible = false
```

`sir_fish_tank.tscn` is the **only** user of `water.gdshader`, and it carries a
`SubViewport` with `own_world_3d = true` — a second 3D world with its own camera
and light. It is also instanced a second time in `scenes/modals/quest_result.tscn`
as `Panel/Layout/SummaryFish`, but that one is inside the hidden `QuestResult`
modal and evidently never rasterizes (the profile shows zero links before the
transition, and `hud.tscn` is an autoload present from boot).

Tests **H3** and simultaneously prices the aquarium: if exactly two expensive
links disappear, a console ornament is costing ~2 seconds of the freeze.

### D — No outline hull

`scripts/battle/cel_materials.gd`, `cel()` signature:

```gdscript
outline_width: float = 0.0    # was 0.018
```

That makes `cel()` skip `mat.next_pass = outline(...)`, so `outline.gdshader`
never reaches a draw. Also tests **H3**, on a shader that is a much bigger part
of the art direction than the fish tank — this is a probe, not a proposal.

*Caveat:* `sir_fish_tank.tscn` authors an outline material inline
(`tank_outline_mat`), so run D together with C, or expect the outline pair to
survive.

---

## 4. Procedure

Identical for each variant. Same machine, same browser, same display — link time
is driver-dependent and comparisons across machines are meaningless.

1. Apply the variant's edit.
2. Export the web build (Godot's Web preset → `builds/web/index.html`).
3. Serve it. It must be over HTTP, not `file://`:
   ```bash
   python -m http.server 8000 --directory builds/web
   ```
4. Open `http://localhost:8000/index.html` in Firefox. **Load the page fully and
   let the town screen settle before recording** — the aim is to capture the
   transition, not startup.
5. Open the Firefox Profiler (`profiler.firefox.com` → "Enable profiler menu
   button"), choose the **Graphics** preset, press record.
6. Click a quest in the Mayor's office. Wait until the expedition is visibly
   rendering and running smoothly.
7. Stop the recording, then **"Save as file"** — that produces a `.json.gz`.
8. Analyse:
   ```bash
   python tools/analyze_web_profile.py path/to/profile.json.gz --label B-no-shadow
   ```
9. Record the `SUMMARY` line in the table below.
10. Revert the edit before starting the next variant.

Add `--list-links` to dump every link in order with a duration bar, which is
what you want once a variant changes the count and you need to see *which* ones
went.

**One caution:** a fresh page load each time. The GL context caches linked
programs, so a second expedition within one session will not re-link them, and
a profile captured after an in-session return to town will show a near-empty
result that means nothing.

---

## 5. Results

Run 2026-09-01 on Windows/Chromium, measured by wrapping
`getProgramParameter(LINK_STATUS)` and `getShaderParameter(COMPILE_STATUS)` in
the page rather than by profiling — see §7 for why, and for what that changed.

| Variant | transition links | link_ms | big links | big_ms | Reading |
| --- | --- | --- | --- | --- | --- |
| *reference (Firefox, 3 lights)* | 61 | 11715 | 10 | 9729 | the capture §0 describes |
| **A — baseline (2 lights), cold cache** | **61** | **11675** | **10** | **9309** | **control passes** |
| A — rerun, warm cache | 55 | 98 | 0 | 0 | cache + RNG confound, see §7 |
| B — no directional shadow | 55 | 626 | 0 | 0 | **inconclusive**, see §7 |

**Variant A passes as a control.** 61 links against the reference's 61, 11,675 ms
against 11,715 ms, 10 expensive links against 10 — from a different browser and
a completely different measurement method. Two things follow:

- The §0 model is confirmed, and confirmed independently of the Firefox profiler.
- **Light count does not change the shader program count.** Removing `RimLight`
  moved a uniform, not a variant, exactly as §0 predicted. The 2-light change is
  worth what it is worth on per-frame fragment cost and nothing at all on this.

**Variant B is inconclusive and must be re-run.** See §7.

### Two findings the Firefox capture could not see

**Boot and town cost another 52 programs / 5,777 ms on a cold cache.** The
reference profile started recording with the town already up, so it saw none of
this. The true cold cost of reaching a first expedition is **113 programs and
~17.5 seconds of shader linking**, not the 12.4 s the transition alone accounts
for.

**The GPU driver's program binary cache removes essentially all of it on a
second run.** Same build, same machine, second page load:

| | cold | warm |
| --- | --- | --- |
| boot + town | 5,777 ms | **63 ms** |
| transition | 11,675 ms | **98 ms** |

That is a ~120× reduction, and it reframes the defect: **this is a first-visit
cost, not a per-session one.** A returning player on the same machine and driver
does not pay it. It still lands squarely on first impressions, on every tester's
first run, and after any driver or browser update that invalidates the cache —
so it is still worth fixing — but it is not the every-time cost the freeze
looked like.

*Measured across page loads within one browser session, on two different origins
(`:8791` and `:8792`). Chromium's program cache is on disk and normally survives
a restart, but that was not tested here — do not quote persistence across
restarts without checking it.*

### The fix: warming at boot (implemented)

`ShaderWarmup` (`scripts/shader_warmup.gd`, run from `boot.gd` behind the
progress bar in `boot.tscn`) draws every spatial material family once at
startup, yielding two frames between each so the bar can actually paint.
`SirFishTank` additionally defers its first render by 0.5 s so a second 3D world
does not land on the transition's heaviest frame.

Measured cold (`--disable-gpu-program-cache --disable-gpu-shader-disk-cache`,
fresh `--user-data-dir`), probe injected into `index.html` so it installs before
Godot's first GL call:

| | boot ms | boot big | transition ms | transition big | total ms |
| --- | --- | --- | --- | --- | --- |
| Baseline | 5,777 | 6 | **11,675** | **10** | 17,452 |
| Warm-up v2 (orc proxy) | 17,093 | 16 | 2,884 | 2 | 19,977 |
| **Warm-up v3 (real families)** | 15,224 | 14 | **2,817** | **2** | **18,041** |

**The transition freeze drops 11,675 ms -> 2,817 ms, a 76% cut, and the
expensive programs there go 10 -> 2.** Total work is near-neutral: +0.6 s, +3%.

The mechanism is not Godot reusing its own programs - the transition still
*creates* a similar number of them (44-60, varying with enemy RNG). It is that
the warm-up compiles the same shader SOURCE, so ANGLE's in-memory program cache
returns each one in ~1 ms. With the disk cache disabled that is a real effect,
not a caching artefact.

Note the totals: 6+10 = 16 expensive programs at baseline, 14+2 = 16 after. The
count never changed, so there was no waste to reclaim - only a question of
*when* the 16 compile. v2's extra 1.9 s was two genuinely redundant programs
from warming with the wrong mesh family, and v3 removes them.

### Variants C and D, re-run with the seed pinned

`RNG.set_seed(20260901)` inserted immediately before `start_expedition()` in
`mayor_office._accept()` - the tightest point, because `start_expedition()`
calls `build_level()`, which is what draws the encounter's enemies. With that
in place the encounter is identical across variants and the counts are
comparable. Counts are cache-independent, so these were taken on a warm cache;
they measure how many programs each variant needs, not how long they take.

| Variant | boot | transition | total |
| --- | --- | --- | --- |
| Baseline (pinned seed) | 87 | 44 | 131 |
| **C** - fish tank hidden | 87 | 44 | 131 |
| **CD** - tank hidden + outline hull removed | **82** | 44 | **126** |

**Variant C changes nothing. H3 is not supported for `water.gdshader`.** The
fish tank was the cheapest thing to cut and the hypothesis said it should be
worth two programs; it is worth zero. The likely reason is that `water` is
`unshaded` - a far simpler shader than the cel/outline pair, cheap enough to
have never been one of the expensive links in the first place. The tank costs a
second render target and a second 3D world, which is a per-frame cost worth
knowing about, but it is not a shader-program cost.

**Variant D removes 5 programs, all of them at boot.** The transition is
unchanged at 44 in all three, which follows: the warm-up already compiles
cel+outline at startup, so removing the outline removes boot work, not
transition work.

**Neither is worth taking.** C buys nothing. D buys 5 boot programs in exchange
for the inverted-hull outline on every character in the game - the single most
identifiable thing about how it looks. D was always a probe, not a proposal
(§3), and the probe's answer is that the outline is not where the money is.

Both variants were reverted after measurement; nothing from them is in the tree.

The conclusion for the transition stands where the warm-up left it: 11,675 ms ->
2,817 ms. Reducing the ~15 s boot further would mean attacking per-program
compile cost (spec §3.3's lighting work, or simplifying `cel_shade`'s custom
`light()`), not removing whole shaders - there are no cheap shaders left to
remove.

#### Why v3 warms what it warms

v2 used `orc_barbarian.glb` for every skinned family on the theory that "skinned
is skinned". Two things were wrong, both visible in `CombatantRig.build()`:

- The KayKit heroes **and all four skeletons keep the `StandardMaterial3D`
  their `.glb` ships**. Only the orc pair is reassigned `CelMaterials.cel()`,
  because they share one asset and are coloured apart at runtime. Warming the
  standard-material variant on the orc's vertex layout warmed a program nothing
  renders.
- The shadow monster **has no armature** (`_finalize_shadow`), so its smoke
  material belongs on a STATIC mesh, not a skinned one.

A program variant keys on the mesh's vertex attribute layout as well as its
material, so v3 warms one representative per layout family with the material it
actually wears. If a new enemy arrives on a third rig family it needs a step
here - the symptom of missing one is expensive links reappearing at the
transition.

---

## 6. How to read the outcome

*(unchanged — see the original criteria below)*

---

## 6. How to read the outcome

- **A ≠ 61 links** → stop; the model in §0 is wrong.
- **B halves `big_links`** → H1. Ship a `.web` shadow override and take ~5 s.
  Then re-ask whether the party's ground shadow is worth re-earning some other
  way (a cheap blob-shadow decal costs no shader variant).
- **B unchanged, C removes exactly 2** → H2 + H3. The lever is then *the number
  of distinct spatial shaders*, and the shopping list writes itself: fold
  `water` into `smoke` or `parallax_layer`, and question whether `smoke`
  (shadow_monster only) earns a whole shader.
- **C removes 2 and B halves as well** → both mechanisms compound; a shader
  removed is worth two links, and shadows are worth half of what remains.
- **Neither B nor C changes anything** → the pairs are something not on this
  list (instancing variants, or Godot compiling a pass this document has not
  accounted for). Fall back to `--list-links` on A and C and diff the ordering
  to see which links moved.

Whatever the result, the fix for the residue is the same and is worth doing
regardless: **the compile has to move off the transition**. Today it lands in
two rAF callbacks, which is why no spinner can animate during it —
`SceneRouter.go()` fades to black in 0.18 s and then the screen is simply frozen
for 12.8 s. Warming the spatial shaders one per frame, behind a progress bar
that can actually draw, is the only version of a loading screen that works here.

---

## 7. Why B is inconclusive, and what the method needs before a re-run

Two defects in the procedure of §4, both found by running it. Neither affects
variant A's result (it was measured first, on a cold cache), and both must be
fixed before B, C or D mean anything.

### 7.1 The encounter is randomised, so the program count is not stable

`RNG.randomize_seed()` runs in `_ready()` (`scripts/autoload/rng.gd`), and the
easy quest draws two enemies at random from
`enemy_pool = [shadow_monster, skeleton_minion]`. **`shadow_monster` is the only
user of `smoke.gdshader`** — `combatant_rig.gd:166` assigns
`CelMaterials.smoke()` to its body, plus a smoke-wisp `GPUParticles3D`. So
whether a shadow monster happens to spawn in the first encounter decides whether
a whole spatial shader gets compiled during the transition.

That is exactly the 61-versus-55 spread observed: variant A measured **61** cold
and **55** on a rerun, *with shadows enabled both times*. The six-program
difference between A and B is therefore not attributable to the shadow setting.

**Fix:** pin the seed before the run. `RNG.set_seed(value)` already exists for
this — spec 8.1's "so a run can be reproduced from a seed". Call it from
`boot.gd` behind a debug flag, or hard-code a seed for the duration of the
experiment, and confirm the same enemy line-up appears in every variant before
trusting any comparison.

### 7.2 The GPU program cache makes every run after the first meaningless

Documented in §5: the second run of the same build linked in 98 ms what the
first took 11,675 ms to link. Any variant measured after another variant has
warmed the cache will report near-zero and look like a spectacular win. Variant
B's 626 ms is exactly this artefact, not a result.

**Fix:** each variant needs a cold program cache. Options, cheapest first:

- Launch Chromium with `--disable-gpu-program-cache`.
- Use a throwaway browser profile per variant (`--user-data-dir=<fresh path>`).
- Clear the GPU cache between runs (`chrome://settings/clearBrowserData` does
  not reliably cover it; deleting `<profile>/GPUCache` does).

Verify the cache really is cold by checking that boot+town reports **~5,800 ms
for 52 links** rather than ~63 ms. That number is a reliable canary and costs
nothing to read.

### 7.3 Measure by instrumentation, not by profiler

The Firefox-profiler procedure in §4 works but is slow and manual. Wrapping the
two WebGL entry points in the page gives the same numbers — verified against the
reference capture to within 0.3% — in any browser, with no recording step:

```js
// paste in the console immediately after the page loads, before the game boots
const stats = { links: [], compiles: [], t0: performance.now() };
window.__shaderStats = stats;
for (const C of [WebGL2RenderingContext, WebGLRenderingContext]) {
  const P = C.prototype, gp = P.getProgramParameter, gs = P.getShaderParameter;
  P.getProgramParameter = function (p, n) {
    if (n !== 0x8B82) return gp.call(this, p, n);           // LINK_STATUS
    const t = performance.now(), r = gp.call(this, p, n);
    stats.links.push([+(t - stats.t0).toFixed(0), +(performance.now() - t).toFixed(1)]);
    return r;
  };
  P.getShaderParameter = function (s, n) {
    if (n !== 0x8B81) return gs.call(this, s, n);           // COMPILE_STATUS
    const t = performance.now(), r = gs.call(this, s, n);
    stats.compiles.push([+(t - stats.t0).toFixed(0), +(performance.now() - t).toFixed(1)]);
    return r;
  };
}
```

Snapshot `stats.links.length` at the Mayor's office, then again once the
expedition renders; the difference is the transition's cost. `tools/analyze_web_profile.py`
remains the tool for Firefox captures and for the frame-health numbers, which
this does not provide.
