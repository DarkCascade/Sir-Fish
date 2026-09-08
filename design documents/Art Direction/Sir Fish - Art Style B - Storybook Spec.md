# Sir Fish — Art Style B: Storybook (Flat Illustrated) Spec

Target: replace atmospheric rendering with flat poster colour and heavy ink
outlines, so legibility comes from the construction of the image rather than
from tuning it.

Written against `main`, on top of Phase 0 (`Sir Fish - Art Style Exploration
Plan.md` §1). §-references in the form §6.1 point at
`scripts/autoload/tuning.gd`; bare §2 points at this document.

**This is a presentation spec. It changes no gameplay, no odds, no balance.**

---

## 0. Before you start

### 0.1 Phase 0 is a hard prerequisite

Same as Art Style A: the type ramp, the body-weight bump and the 7 px border
floor land first. Storybook leans harder on borders than Lantern does — the ink
outline *is* the style — so thin borders sabotage it completely.

### 0.2 Verify with the audit, continuously

```bash
python3 tools/palette_audit.py --profile storybook --strict
```

The `storybook` profile is stricter than `lantern`: chrome edges must clear
**3.0:1** (not 2.0), chrome tiers must be **0.08** apart (not 0.045), and **no
chrome surface may sit below 0.05 luminance** (Lantern allows one). Every value
in §2 is solved against those floors.

Note what the profile does *not* gate: `C_PANEL_BORDER` at 0.0175 luminance is
near-black and that is correct here — the audit classifies borders as EDGE and
exempts them from the dark-surface rule, precisely so a poster style is not
punished for having ink outlines.

### 0.3 The one idea

Stop asking the renderer to communicate depth and structure through subtle
tonal differences, because a phone at 25% brightness in a dark room does not
transmit subtle tonal differences.

Instead, build the image the way a printed picture book does: every element is a
**flat area of one colour**, bounded by a **heavy dark outline**, and depth is
carried by **discrete, measured luminance steps** rather than by haze. Nothing
in the image depends on a gradient surviving. There is no subtlety to lose.

This also inverts the UI's text polarity. The console becomes pale paper with
dark ink on it, which is the single most legible arrangement available and the
one every physical book uses.

### 0.4 Non-goals

- No re-modelling, re-rigging, re-animating. Every `.glb`, armature and clip
  is untouched — only materials change. The Meshy/Blender investment survives
  this style completely.
- No hand-authored textures. §0.1.2 / §23.1 still stand. Flat materials only.
- Do not outline the scatter multimeshes. See §4.2 — this is the one place the
  style can wreck web performance.

---

## 1. The look in one paragraph

A page from a printed storybook. A pale blue sky sits flat behind a treeline
that is a solid shape, not a gradient; the canopy in front of it is a darker
solid green, and the trunks in front of *that* are darker still — four plates,
each a measured step apart, no haze between them. The path is bright warm green.
Every character, prop and crystal carries a thick dark-brown outline, the same
weight everywhere, as if inked. The console is not a stone cabinet any more: it
is a cream card laid on the page, edged in that same ink, carrying dark brown
type. Sir Fish and the heroes keep their shapes exactly, rendered in flat blocks
of their existing colours with one shadow step.

---

## 2. Palette — `scripts/autoload/tuning.gd` §6.1

Rewrite **in place**; names unchanged, so all 40 consuming files keep resolving.

`lum` is WCAG relative luminance. The world values are deliberately spaced at
roughly even ratio steps — that even spacing is what makes depth read without
fog.

### 2.1 The world as poster plates

| Constant | New value | lum | Was | Role |
|---|---|---|---|---|
| `C_SKY` | `Color("98DEFC")` | 0.6595 | `0B2C4E` (0.0242) | Flat pale sky, the brightest plate. |
| `C_FAR_HILLS` | `Color("6AA4CC")` | 0.3397 | `0E3A52` (0.0373) | Treeline. 1.82:1 below the sky. |
| `C_MID_TREES` | `Color("357E60")` | 0.1652 | `14584E` (0.0768) | Mid canopy. 1.81:1 below the treeline. |
| `C_NEAR_TREES` | `Color("194838")` | 0.0513 | `0A1C24` (0.0102) | Near trunks, the darkest plate. 2.13:1 below the canopy. |
| `C_GROUND` | `Color("8CC960")` | 0.4819 | `2F6B44` (0.1154) | The lit path. |
| `C_BRUSH` | `Color("44975F")` | 0.2419 | `0C2A2C` (0.0192) | Undergrowth. 1.82:1 below the path. |
| `C_ROCK` | `Color("8B96A2")` | 0.2991 | `2A3A44` (0.0394) | Scatter rocks, flat cool grey. |

Four sky-to-trunk plates at ~1.8-2.1:1 each. That ratio is not arbitrary and it
is not a compromise: 3:1 between *every* adjacent pair of a five-plate stack is
arithmetically impossible — each step multiplies the offset luminance, so the
top plate would need to exceed white. Consistent ~1.8:1 steps are what a poster
actually uses, and the audit's `min_world` floor encodes exactly that.

### 2.2 The console as paper

| Constant | New value | lum | Was | Role |
|---|---|---|---|---|
| `C_CONSOLE_BG` | `Color("487A9F")` | 0.1780 | `07171B` (0.0074) | The page behind the card — a mid slate blue, not a void. |
| `C_CONSOLE_INSET` | `Color("46768D")` | 0.1618 | `0B1E1C` (0.0108) | Recessed wells, now a mid blue plate. 3.64:1 against the card. |
| `C_CONSOLE_PANEL` | `Color("E8DCBE")` | 0.7206 | `0D2A2A` (0.0191) | **The card.** Cream paper. 3.38:1 against the page. |
| `C_CONSOLE_STONE` | `Color("F5EEDF")` | 0.8589 | `3A4A3C` (0.0612) | Raised frame — the brightest paper. |
| `C_PANEL_BORDER` | `Color("2F2115")` | 0.0175 | `2E5A4E` (0.0844) | **The ink.** Near-black brown. 11.42:1 against the card — the outline that defines every edge. |

### 2.3 Text, inverted to ink-on-paper

| Constant | New value | lum | Was | Role |
|---|---|---|---|---|
| `C_TEXT` | `Color("2F2115")` | 0.0175 | `F5F1E4` (0.8792) | **Dark ink.** Same value as the border — one ink for type and outline. 11.42:1 on the card. |
| `C_TEXT_DIM` | `Color("685643")` | 0.1000 | `9CB0AC` | Secondary ink. 5.14:1 on the card — comfortably AA, unlike the dark style where dim text had to move house. |
| `C_TEXT_GOLD` | `Color("7D5B1F")` | 0.1194 | `F0D588` | Heading ink, warm brown-gold. 4.55:1 on the card. |
| `C_GOLD` | `Color("DAA62C")` | 0.4236 | `D4A843` | Stays a bright gold — it is now a *fill* colour (coins, trim), not a text colour. |

**This inversion is the single largest change in the spec** and it has a long
tail. Every call site that assumes light-on-dark needs checking: outline sizes,
drop shadows, and `DisplayLabel/constants/outline_size = 5` in `theme.tres`,
which exists to hold white type off a dark ground and now does the opposite job.
Set the display outline to a pale value (`C_CONSOLE_STONE`) or drop it to 0 on
paper surfaces. `PlateLabel` already uses dark-on-light and becomes the norm
rather than the exception.

### 2.4 Reliquary — the modal layer (§6.1e)

Violet identity preserved, polarity flipped with everything else.

| Constant | New value | lum | Role |
|---|---|---|---|
| `C_RELIQUARY_STONE` | `Color("DFCFEB")` | 0.6631 | Pale violet tablet. 4.44:1 against its scrim. |
| `C_RELIQUARY_MIST` | `Color("704F90")` | 0.1105 | The scrim, now a deep violet wash. |
| `C_RELIQUARY_STONE_DARK` | `Color("5D3C79")` | 0.0694 | Edge shadow. |
| `C_CRYSTAL_BRIGHT` | `Color("7333AC")` | 0.0899 | **Now the dark accent**, since it sits on pale stone. 5.10:1. Note the name no longer describes it — leave the name, note it in a comment. |

### 2.5 Character and signal colours

Character colours (`C_WARRIOR_*`, `C_RANGER_*`, `C_MAGE_*`, `C_ORC_*`,
`C_FISH_*`) keep their hues but should be pushed to higher saturation and a
mid-to-bright value, because they now sit as flat fills against a bright world
rather than as lit surfaces in the dark. Signal colours (`C_DANGER`, `C_HEAL`,
`C_LIGHTNING`, `C_FIRE`, `C_ICE`) similarly: they must read against the *bright*
plates now, which is the opposite of what they were tuned for. Retune them
against `C_GROUND` (0.48) as the worst case, and verify damage numbers over the
lit path specifically.

---

## 3. Typography

Storybook wants a rounded, heavy, high-x-height face, not an engraved Roman one.

**Use `assets/fonts/Baloo2-Variable.ttf`, which is already vendored and
imported.** It was the display face before the Presentation Redesign replaced it
with Cinzel, so its licence (`Baloo2-OFL.txt`) and `.import` are already in the
repo — no download, no §0.1.2 problem.

| Role | Face | Setting |
|---|---|---|
| Display / headings | Baloo 2 | `wght` 800 |
| Body / labels | Baloo 2 | `wght` 600 |

Cinzel and EB Garamond stay in the repo, unreferenced by this style's theme —
if Storybook loses the night test, reverting is just pointing the theme back at
them.

Keep the Phase 0 type ramp exactly. It is face-independent.

## 4. Rendering — the flat pass

This is where Storybook stops being a repaint and becomes an art style.

### 4.1 Environment — `scenes/battle/battle_world.tscn`

| Setting | Current | New | Why |
|---|---|---|---|
| `fog_enabled` | true | **false** | Depth is now carried by §2.1's plates. Fog would muddy the steps it replaces. |
| `glow_enabled` | true | **false** | Nothing bioluminescent left to bloom. Also the largest single shader saving. |
| `ambient_light_energy` | 0.5 | **1.0** | Flat lighting: ambient does nearly all the work. |
| `adjustment_contrast` | 1.08 | **1.0** | The palette already carries the contrast; post-contrast would clip the flats. |
| `adjustment_saturation` | 1.3 | **1.1** | Poster colour is authored saturated, not pushed saturated. |
| `tonemap_mode` | 2 (Filmic) | **0 (Linear)** | Filmic exists to roll off highlights into a filmic curve. Flat colour wants the authored value back out, unmodified. |
| Directional lights | 0.75 / 0.95 / 0.7 | **0.35 / 0.2 / 0.0** | Keep a trace of key light for form; kill the fill and rim. |

`Tuning.FOG_DEPTH_BEGIN` / `FOG_DEPTH_END` become unused — leave the constants,
comment them as inert under this style rather than deleting them, so a revert is
one line.

### 4.2 The ink outline — and the one way this style wrecks performance

Every character, hero prop and crystal gets a dark outline in `C_PANEL_BORDER`.
Use an **inverted-hull** outline: duplicate the mesh, flip normals, scale along
normals, unshaded fill, `cull_front`. `scripts/battle/cel_materials.gd` is where
the material setup already lives and is the right home for it.

**The trap, and it is a hard rule: outline characters and hero props only.
Never the scatter multimeshes.** `scripts/battle/overworld_field.gd` scatters
tufts, grass, rocks, bushes, crystals and trees as MultiMesh instances; an
inverted hull doubles the draw for every one of them. That is the exact cost
centre `design documents/Sir Fish - Shader Link Counting Experiment.md` and the
web delivery spec were written about. Scatter props get their separation from
§2.1's value steps instead, which costs nothing.

Budget: outline the party (3), the enemies on screen (up to 3), Sir Fish, and
the hero-scale props. Nothing else.

### 4.3 Cel materials

`cel_materials.gd`'s ramp collapses to **two bands** — lit and shadow, one hard
step, no gradient. The shadow band is the base colour multiplied by ~0.75, not a
separate hue. Anything softer re-introduces the gradients this style exists to
remove.

## 5. Expected performance effect

Removing fog, glow and two of three lights should cut shader permutations
materially, and the web build's shader-link time is the project's known worst
freeze. **Treat this as a hypothesis, not a benefit.** Measure it with
`tools/analyze_web_profile.py` before and after, the same way the shader-link
experiment did, and record the numbers in that document. The inverted-hull pass
in §4.2 pushes the other way, which is exactly why §4.2's budget is a rule
rather than a suggestion.

## 6. Files to walk

| File | What changes |
|---|---|
| `scripts/battle/cel_materials.gd` | Two-band ramp (§4.3); inverted-hull outline (§4.2). |
| `scripts/battle/parallax_background.gd` | Layer tints become the flat plates; storm tint application needs re-thinking — see §7. |
| `scripts/battle/overworld_field.gd` | Scatter materials go flat. **No outlines here.** |
| `scripts/console/ornate_frame.gd` | Carved stone becomes a flat card with an ink edge. Largest single rewrite in this spec. |
| `scripts/ui/item_card_style.gd` | Cards on paper; rarity colours re-tuned against a bright ground. |
| `scripts/modals/item_glyph.gd` | Rarity ring/glow against a pale tablet — the glow may need to become a ring. |
| `assets/theme.tres` | Baloo 2; `DisplayLabel` outline (§2.3); every StyleBox border to the ink colour. |
| All `scripts/overlay/*` | Damage numbers, bars and status icons all assumed a dark ground. |

## 7. Storm mood

`Tuning.storm_tint()` darkens toward slate, which was designed to make a dark
world darker. Against a bright poster palette it will produce grey mud.

Storybook needs the storm re-conceived as a **desaturating, cooling** transform
rather than a darkening one — pull toward `STORM_SLATE`, reduce saturation, and
darken only slightly (`STORM_DARKEN` ~0.15). Verify on device in a storm
encounter; this is the piece most likely to look wrong first.

## 8. Verification

1. `python3 tools/palette_audit.py --profile storybook --strict` exits 0.
2. Every screen on device — the ink edge should make structure unmistakable.
3. Damage numbers and status icons legible over the *bright* path (§2.5).
4. A storm encounter after §7.
5. Draw-call check: confirm no MultiMesh scatter prop gained an outline (§4.2).
6. Web profile captured and compared per §5.
7. The night test from the exploration plan §3.2 — including the honest question
   of whether a bright screen is uncomfortable at 1 a.m., which is this style's
   real risk.

## 9. Risk and rollback

Bigger and messier to revert than Lantern: the polarity inversion (§2.3) touches
call sites all over `scripts/overlay/` and `scripts/modals/`, and §4's render
changes are scene-level. Do it on its own branch and keep the commits separated
by section so a partial revert is possible.

The strategic risks, in order:

1. **A bright screen at night may be worse than a dark one**, whatever the
   measurements say. This is exactly what the night test is for, and it is the
   reason this spec exists alongside Lantern rather than instead of it.
2. **It discards the bioluminescent identity** the project spent its whole
   presentation redesign establishing.
3. **The outline pass is a performance foot-gun** if §4.2's budget slips.

## 10. Effort

Substantially more than Lantern. The palette is an afternoon, but §4's render
work, §2.3's polarity inversion across the overlay and modal layers, and
`ornate_frame.gd`'s rewrite are each a session. Call it a week of sessions, with
the web profile measured at the end.
