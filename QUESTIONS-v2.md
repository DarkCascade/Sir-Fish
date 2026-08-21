# QUESTIONS — Demo v2

Open questions and recorded deviations arising while implementing
`design documents/Sir Fish - Demo v2 Implementation Spec.md`.

`QUESTIONS.md` (v1, Q0–Q24) is **closed** — every question in it is answered by the
v2 spec. This is the fresh file the v2 spec's closing paragraph asks for. Nothing
here is appended to the old one.

**Severity key**

| Level | Meaning |
|---|---|
| **BLOCKER** | Implementation stopped. Needs a design decision before it can continue. |
| **OPEN** | Raised before implementing. Nothing has been built or changed; awaiting your decision. |
| **DECISION** | I made a defensible call and proceeded. Confirm or overrule. |
| **TOOLING** | A Godot MCP limitation forced a route the spec did not anticipate. No design impact. |
| **NOTE** | Minor, recorded for completeness. |

---

## V0 — Status

**No BLOCKER was hit. Implementation was not stopped by a question.**

- **M6 — Ratification pass: COMPLETE and gated.**
- **M7 — Core-loop slice: COMPLETE and gated.**
- **M8 — Blender assets: STARTED, far from complete.** See V14.
- **One OPEN question awaits a decision before more M8 work: V15** (parallax tiles).

All six headless tests pass. A full hands-off run plays from encounter 0 to the
run summary with **zero errors and zero warnings**. Every item below is either a
tooling limitation with a recorded workaround, or an ambiguity I resolved and
flagged rather than changed silently.

The one entry that most wants your attention is **V11** — a real rendering bug
created by §6.3, which required changing a line §6.2 said to write verbatim.

---

## V1 — `add_autoload` cannot control autoload order — **TOOLING**

§3.2 mandates the registration order Tuning, RNG, EventBus, Itemizer, **Upgrades**,
GameState, Debug, with the stated reason "`Upgrades` before anything that reads a
payout."

The MCP's `add_autoload` only **appends**, and this build exposes no tool to
reorder or remove an autoload. The resulting order is:

```
Tuning, RNG, EventBus, Itemizer, GameState, MCPScreenshot, MCPInputService,
MCPGameInspector, Upgrades, Debug
```

so `Upgrades` sits *after* `GameState` rather than before it.

**Why I proceeded:** the ordering constraint is about load-time reads, and nothing
reads a payout at `_ready()`. `Upgrades` touches `GameState` only inside `buy()`;
`GameState` touches `Upgrades` only inside `reset_run()`, which `RunController`
calls long after every autoload exists. The declared order therefore differs from
§3.2 but the behaviour does not.

**What I need:** confirmation that behavioural equivalence is acceptable, or an
instruction to hand-edit `project.godot`'s `[autoload]` block (which §0.1.1's
"never edit project.godot by hand" rule otherwise forbids).

---

## V2 — This MCP build has no `delete_node`, so C22 had no tool route — **TOOLING**

`CLAUDE.md` lists `delete_node` among the editor tools. **It is not exposed by
this build.** Neither is any scene-node removal tool. Confirmed by name lookup and
by keyword search.

C22 requires `ModalLayer` to change type from `CanvasLayer` to `Control`. Changing
a node's *type* needs delete-and-recreate; `rename_node` / `move_node` /
`add_node` cannot do it. The only alternatives were:

1. Leave the dead `CanvasLayer` in the scene beside a new `Control` — a permanent
   orphan node in the root scene.
2. Hand-edit `scenes/main.tscn`.

**I took (2)**, editing exactly the `ModalLayer` node header and removing the two
per-modal `theme =` lines that C22 also calls for. §0.3 permits "use the nearest
equivalent and append a note"; §0.1.1's no-hand-edit rule is scoped to working
around *resource assignment*, which is not what this is. Recorded in §21.5.

**What I need:** confirmation. If hand-editing `.tscn` is absolutely forbidden,
the fallback is option (1) and the spec should say so.

---

## V3 — `set_project_setting` writes `msaa_3d` as a float — **TOOLING**

§2 requires `rendering/anti_aliasing/quality/msaa_3d = 2` (the enum value for 4×
MSAA). The MCP tool coerces every numeric argument to a float, so `project.godot`
now reads:

```
anti_aliasing/quality/msaa_3d=2.0
```

and `get_project_settings` reports `"type": 3` (TYPE_FLOAT) rather than TYPE_INT.
Passing the value as an integer and as a string both produce `2.0`.

Godot casts the float to `2` when the rendering server reads it, so 4× MSAA is
what is actually applied. But the setting is stored with the wrong Variant type,
which is untidy and could confuse a later reader.

**Decision:** left as `2.0`. **What I need:** either an accepted deviation, or
permission to hand-edit that one line in `project.godot`.

---

## V4 — `resources/levels/` could not be deleted — **TOOLING / needs a manual step**

C7 and §12.1 require deleting `res://resources/levels/demo_level.tres` and the
`levels/` folder. Nothing in the game code loads it (verified by search — the only
references are in the two spec documents and the old `QUESTIONS.md`), so
`build_level()` is already the sole source of truth in behaviour.

The deletion itself was **blocked by this session's command permissions**, and the
MCP exposes no `delete_scene`/`delete_resource` for `.tres`.

**Action required from you:** delete `C:\Projects\Godot\Sir Fish\resources\levels\`
manually, or grant permission and I will do it. Until then C7 is functionally
satisfied but not literally satisfied.

---

## V5 — §3.3's tree and its prose disagree about what is last under `Main` — **DECISION**

§3.3 draws the tree with `RunController` **after** `ModalLayer`:

```
├── ModalLayer (Control)
└── RunController (Node)
```

but the paragraph below it says `ModalLayer` is "declared **last** among `Main`'s
children" and states the standing rule "nothing may be added to `Main` after
`ModalLayer`."

**Decision:** I kept the tree's order — `ModalLayer` then `RunController`. The
prose's purpose is draw order ("last child = on top"), and `RunController` is a
plain `Node` that draws nothing, so it cannot occlude a modal. Moving it above
`ModalLayer` would satisfy the letter of the prose and change nothing.

**What I need:** confirmation, or a restatement of the rule as "last among `Main`'s
*Control* children."

---

## V6 — The priest skip rule's pseudocode is written generically — **DECISION**

§10.2 step 3 is headed "**Priest skip rule**" but its code has no caster check:

```gdscript
# if use_special and every living hero is at full HP:
use_special = false
c.special_pending = true
```

Read literally this also suppresses the **warrior's Defend** whenever the party is
at full HP — which is wrong: Defend is a pre-emptive damage reduction and is at its
most useful *before* anyone is hurt. It would also mean the warrior banks a
`special_pending` that fires on the first scratch, which is exactly the reactive
twitch Q9 set out to remove.

**Decision:** kept v1's `c.stats.id == &"priest"` guard, matching the rule's own
heading and §9.3's "Skip rule". Only the priest's heal is skipped and banked.

**What I need:** confirmation that the guard is intended.

---

## V7 — Limb translations are ambiguous between absolute and relative — **DECISION**

§9.2 asks for `ArmR.position.x` → **−0.18** during the ranger's draw. `ArmR`'s home
position is `(0.34, 1.38, 0.12)`, so an *absolute* −0.18 would throw the draw hand
across to the far side of the body. Body translations elsewhere in §9 (`Visual.position.x`
→ +0.14, +0.20, +0.22) are on a node whose home is the origin, so absolute and
relative coincide there and the document never has to disambiguate.

**Decision:** limb translations are treated as **deltas from the limb's home
position** — `ARM_R_HOME + (−0.18, 0, 0)`. The same reading is already applied to
§9.1's `ArmL.position.z` → +0.20, which v1 built as a delta and which §9.1
ratifies.

---

## V8 — `Debug` depends on M7 systems, so §20's milestone split cannot hold — **DECISION**

§20 puts `Debug` (§19.2) in **M6** and `Upgrades` (§17.6) plus `party_bonuses()`
(§13.5) in **M7**. But §19.2's command table gives `Debug` three commands that
cannot compile without the M7 systems:

- `upgrade <id> <level>` → `Upgrades.DEFS`, `Upgrades.levels`
- `additem [rarity]` → a rarity-forcing Itemizer entry point
- `state` → dumps "upgrade levels and party bonuses"

**Decision:** built the `Upgrades` autoload, `GameState.party_bonuses()`,
`Itemizer.generate_item_with_rarity()` and the `roll` modifier key during M6, since
M6 cannot compile otherwise. The *user-facing* M7 work — the upgrade tray, the
bonus strip, Sir Fish, the slot counter — stays in M7 as specified. The milestone
gates are unaffected.

---

## V9 — §17.6 says "six glyphs" but lists five — **NOTE**

§17.6's bonus strip: "Six procedurally drawn 20 px glyphs with values beside them,
omitting any that are zero: sword (`dmg_flat`), chevron (`dmg_pct`), §16.7 `BOLT`
(`slot_bolt`), coin (`slot_purse`), §16.7 `PLUS` (`slot_mend`)." That is **five**
glyphs for five numeric bonuses.

The sixth key in §13.5's dictionary is `element`, which is a `StringName`, not a
number — it has no value to put beside a glyph, and §13.5 calls it cosmetic.

**Decision:** implementing five glyphs. If `element` should also appear (e.g. a
small flame/snowflake/bolt tint chip), say so and I will add a sixth.

---

## V10 — `test_economy`'s gold assertion is stochastic as written — **DECISION**

§19.3 asks `test_economy` to assert that "14 pre-shop spins at §5.4's payouts puts
gold on hand ∈ [150, 260]".

The expected value works out exactly as §5.4 predicts — `75 + 14 × 6.80 ≈ 170` — but
**a single 14-spin sample has enormous variance**. Gold payouts land on roughly
16.7% of spins, so a run with zero gold wins is entirely ordinary and finishes on
75 gold, well below the floor. A literal implementation would fail the gate at
random, which makes the test worse than useless.

**Decision:** the test asserts the **mean over 1,000 simulated 14-spin runs** falls
in [150, 260], and separately reports the single-run distribution so the spread is
visible. The affordability half of the assertion ("at least one card affordable in
≥95% of 1,000 trials") is already framed over 1,000 trials and is implemented
literally.

---

---

## V11 — §6.3's outline change breaks §6.2's cel shader — **DECISION (real bug, found on screen)**

**This one was a genuine regression and it is worth reading in full.**

§6.3 / Q16 adds `blend_mix` to `outline.gdshader` so the inverted hull can fade.
§6.2 says of `cel_shade.gdshader` "write exactly this", and its render mode is
`depth_draw_opaque`. Those two instructions are incompatible, and the result is
that **every character renders as a solid black silhouette.**

Why:

1. In v1 the outline was opaque (`unshaded`, no `blend_mix`), so it rendered in
   Godot's **opaque pass**, which runs before all transparent geometry, and it
   wrote depth.
2. The cel body is transparent (`blend_mix`), so it rendered afterwards in the
   transparent pass and drew on top of the hull. Correct outline.
3. Adding `blend_mix` moves the hull into the **transparent pass**. Within one
   object, `next_pass` renders *after* the base material — so the hull now draws
   on top of the body.
4. A transparent material with `depth_draw_opaque` writes **no depth at all**, so
   the body left nothing for the hull to be depth-tested against. The hull
   covered it completely.

I confirmed this on screen before and after: `user://battle_before.png` shows the
black silhouettes.

**Fix:** `cel_shade.gdshader`'s render mode becomes `depth_draw_always` instead of
`depth_draw_opaque`. The body writes depth, so the hull is rejected everywhere
except the silhouette rim — which is exactly what an inverted-hull outline is for
— and §6.3's alpha fade still works, because the hull is still transparent.

This is a one-word change to a shader §6.2 said to write verbatim, so it needs
your ratification. The alternative (reverting §6.3 to an opaque outline) would
re-open Q16.

---

## V12 — Sir Fish's tank needs `own_world_3d` and its own environment — **NOTE**

§17.7's `sir_fish_tank.tscn` listing sets `transparent_bg = true` but does not set
`own_world_3d`. Without it a `SubViewport` **shares the parent's `World3D`**, so
the fish camera rendered the *battlefield* — sky, hills and all — inside the tank.
Set `own_world_3d = true`.

That in turn gives the tank a world with no `WorldEnvironment`, hence no ambient
light, so the cel shader had only the key light and the whole bowl read as a dark
blob. Added a small `WorldEnvironment` to the fish viewport mirroring §6.4's
ambient values.

Third: with `transparent_bg`, the glass sphere tints straight onto the console's
`#231F2E` panel, so the tank interior was still dark. Added an unshaded water-blue
backdrop disc behind the fish. All three are additive to §17.7's listing and none
of them change the design.

---

## V13 — `apply_shop_override` cannot hit every price exactly — **NOTE (fixed)**

§19.2's `shop <p0> <p1> <p2>` says to rewrite each item's `value` to
`price / SHOP_BUY_MARKUP`. Because `value` is an int and `buy_price()` rounds,
that does not round-trip: `250 / 1.5 = 166.67 -> 167`, and `167 x 1.5` rounds back
to **251**. The first run of §15.2's worked example showed 200 / 251 / 300.

Fixed by trying `base`, `base - 1` and `base + 1` and keeping whichever reproduces
the requested price exactly. Behaviour is unchanged; the gate's numbers are now
literal.

---

---

## V14 — M8 is a much larger milestone than M6 and M7 combined — **NOTE / scope**

M8 is started, not finished. What exists:

- The fifth collection, `Console`, has been added (§23.1).
- **Sir Fish is modelled** — 13 low-poly, flat-shaded objects, per-material flat
  palette colours, no textures, 0.35 units long, feet-equivalent at the origin,
  facing +X, symmetric across Y (§23.1, §23.5).
- **§23.5's specific gate has passed:** rendered at 164 x 164 with
  `render_thumbnail_to_path`, he reads as an armoured fish — a deep-bellied blue
  body, a barbute helm with a gold circlet and crest, a visor slit and an eye.
  It took three iterations; the first two are recorded above in the transcript
  and are exactly why that gate exists.
- The blend file is saved. Render settings borrowed for the gate render were
  restored to what they were.

What remains, and it is a lot:

| Work | Rough size |
|---|---|
| Sir Fish's 2-bone rig + 7 actions (§17.7's table) | 1 rig, 7 actions |
| His tank: bowl, gold base ring, gravel, plaque | 4 objects |
| 5 character meshes (the barbarian and warlord share one) | 5 models |
| 5 armatures at §23.2's exact 17 bones | 5 rigs |
| Character actions, only the names `required_anims()` demands | ~26 actions |
| Shadow monster via shape keys, no armature | 1 special case |
| 5 parallax tile meshes, each exactly 12.0 units wide and seamless (§23.4) | 5 tile sets |
| glTF export, Godot import, `Rig` swap, material reassignment | 6 swaps |
| Re-run the M6 gate after **each** character swap (§23.3) | 6 gate passes |

That is substantially more work than M6 and M7 together, and every action has to
be checked from a −Z orthographic view before export (§23.2) because a limb that
swings toward the lens is invisible in game.

**Nothing about it is blocked or ambiguous** — §23 is clear and the pipeline is
proven by Sir Fish. It simply has not been done yet, and I would rather say so
plainly than leave half-rigged characters in the file.

---

## V15 — Is Blender the right tool for §23.4's parallax tiles? — **OPEN**

**Nothing has been built or changed for this. No parallax code was touched.**
Raised for a decision before §23.4 is attempted.

### The question

§23.4 asks for the five parallax layers to be replaced with "tiling meshes",
modelled in Blender per §23.1. Is that the right tool for all five layers?

### What the current build actually does

Three facts from `parallax_background.gd` and §7.2 bear on it:

1. **The camera is orthographic and dead-on** — `PROJECTION_ORTHOGONAL`,
   `rotation = (0, 0, 0)`. Under orthographic projection, Z depth contributes
   nothing to size or apparent motion. §7.4 states this outright: "Orthographic
   projection gives no free parallax, so it is faked by scroll speed."
2. **Layers 1-3 are already flat, unshaded silhouettes.** Every tile is built
   through `_add_mesh()`, which assigns `CelMaterials.flat()` — the *unshaded*
   `parallax_layer.gdshader` — and sets `cast_shadow = OFF`. Those layers receive
   no lighting and cast no shadows, and §6.1 gives each exactly one flat colour.
3. So for layers 1-3, 3D geometry buys nothing that a flat profile would not.
   Modelling them in Blender is 2D work done in a 3D tool.

### A genuinely 2D tool is ruled out by the spec, not by preference

An SVG/raster workflow (Inkscape, or any image-based tool) is excluded twice
over: §0.1.2 forbids importing any third-party asset, and §23.1 forbids textures
outright — "no normal maps, no textures — vertex colours or per-material flat
colours only". So the 2D-ness has to be expressed as **flat geometry generated
from a 2D profile**, not as an image.

That points at procedural mesh generation in GDScript, which §0.1.2 already
blesses as a first-class route: "generated — procedurally in Godot, or modelled
in Blender via MCP." `_build_hills()` already works this way, via `SurfaceTool`
and a sum of sines.

### Evidence: there is a seam bug in the hills layer today

This is pre-existing v1 placeholder code, not a v2 regression, but it is exactly
the failure mode §23.4's "seamless at its edges" rule exists to prevent, and it
argues for a route where seamlessness is *provable*.

The hill profile is periodic within a tile, but the phase differs per tile
(`phase = float(variant) * 2.3`):

```
y(t, phase) = 1.5 + 0.75*sin(t*TAU + phase) + 0.35*sin(t*TAU*3 + phase)

tile 0, right edge (t = 1, phase 0.0)  ->  y = 1.5000
tile 1, left  edge (t = 0, phase 2.3)  ->  y = 2.3203
```

A **0.82-world-unit step in the horizon** at every tile boundary. At §7.2's
figures (camera `size` 6.5 over a 640 px viewport = 98.5 px per unit) that is a
**~81 px vertical jump**.

It is not visible at rest, because tile 1 spans the whole visible width. But the
boundary at world x = +6 sits only `6 - 5.484 = 0.52` units outside the right edge
of frame, and the hills scroll at `TRAVEL_SPEED x 0.10 = 0.4` units/sec — so the
seam enters view after about **1.3 seconds of travel** and is on screen for most
of the demo's travel time.

Hand-modelled in Blender, a seam like this is invisible in the viewport and only
appears in game after a wrap. Generated from a periodic function, it is seamless
by construction and can be covered by a headless test.

### Three options

| # | Approach | Trade-off |
|---|---|---|
| **A** | **Split it.** Layers 1-3 procedural in GDScript from a periodic 2D profile; layers 4-5 modelled in Blender. | My recommendation. Layer 4 (Ground, Z 0, speed 1.00) sits at character depth and §23.4 wants rocks and grass tufts on it; layer 5 (Brush, Z +3) renders *in front* of the characters and most wants the cel + inverted-hull treatment so it reads as the same world rather than an overlay. Those two have real form; layers 1-3 do not. Stays inside §0.1.2 and needs no change to §7.4's architecture. |
| **B** | **All five in Blender**, as §23.4 currently reads. | One tool, one pipeline. But it is 2D work in a 3D tool for three of the five layers, and seamlessness becomes a hand-vertex-snapping exercise that cannot be tested. |
| **C** | **Shader silhouettes.** Drop tiles for layers 1-3 entirely; draw each silhouette in a fragment shader on one full-width quad, offset by scroll distance. | Technically the strongest for flat scrolling silhouettes under an ortho camera: seams become impossible by construction and the wrap logic disappears for those layers. **But it contradicts §7.4's three-copies-that-wrap architecture and §23.4's "tiling meshes"**, so it is a real specification change, not an implementation choice. Flagged rather than taken. |

### What I need

A decision between A, B and C. If A or C, §23.4 and (for C) §7.4 need rewording.
Whichever way it goes, the hills phase seam above should be fixed as part of it.

---

*(End of current entries.)*
