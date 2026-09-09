# Sir Fish — Art Style Exploration Plan

Target: decide whether the game keeps its bioluminescent night-forest direction,
and fix the thing that actually makes it unreadable on a phone at night.

Written against `main` at the time the complaint was raised: *"the colour scheme
of the game is too dark and the text is too small to read on my phone at night."*

§-references in the form §6.1 point at `scripts/autoload/tuning.gd`. Bare §2
points at this document. References to *Presentation Redesign* mean
`design documents/Town - Forge - Quest/Sir Fish - Presentation Redesign Spec.md`.

**This is a presentation exploration. It changes no gameplay, no odds, no
balance.**

---

## 0. Before you start

### 0.1 The measurement comes first, and it disagrees with the complaint

Run this before forming any opinion:

```bash
python3 tools/palette_audit.py
```

`tools/palette_audit.py` was written for this exploration. It parses the real
palette out of §6.1, the real font sizes out of `assets/theme.tres` plus every
`.tscn` and `.gd` override, and reports what those values do on a phone.

**The naive reading of the complaint is wrong, and acting on it would make the
game worse.** "Too dark, can't read the text" sounds like a contrast failure.
It is not one. Every text-on-surface pair in the shipped palette clears WCAG AA
comfortably:

| Pair | Ratio | Verdict |
|---|---|---|
| `C_TEXT` on `C_CONSOLE_PANEL` | 13.45:1 | AA (needs 4.5) |
| `C_TEXT` on `C_CONSOLE_BG` | 16.20:1 | AA |
| `C_TEXT_DIM` on `C_CONSOLE_PANEL` | 6.67:1 | AA |
| `C_TEXT_GOLD` on `C_CONSOLE_PANEL` | 10.55:1 | AA |

Brightening the text would fix nothing and would cost the art direction. What
actually fails is three other things.

### 0.2 What actually fails

**1. Luminance-range compression — the layout is invisible, not the text.**
Eleven of the fifteen world and chrome colours sit below 0.05 relative
luminance. Everything is crammed into the bottom sixth of the range, so
surfaces that are meant to sit in front of each other do not separate:

| Adjacent surfaces | Ratio | |
|---|---|---|
| `C_CONSOLE_PANEL` vs `C_CONSOLE_BG` | 1.20:1 | panel edge invisible |
| `C_CONSOLE_INSET` vs `C_CONSOLE_BG` | 1.06:1 | well edge invisible |
| `C_CONSOLE_INSET` vs `C_CONSOLE_PANEL` | 1.14:1 | well edge invisible |
| `C_NEAR_TREES` vs `C_CONSOLE_BG` | 1.05:1 | world/frame boundary invisible |
| `C_BRUSH` vs `C_NEAR_TREES` | 1.15:1 | depth layers merge |
| `C_RELIQUARY_STONE` vs `C_RELIQUARY_MIST` | 1.06:1 | modal edge invisible |

Anything under about 1.5:1 stops being an edge at phone brightness. On an OLED
at 25% in a dark room, with the screen's own reflection as ambient glare, the
whole bottom of that range collapses into one black mass. §6.1's organising
rule already says the two halves of the screen must separate — *"nothing that
belongs to the world may be gold, and nothing that belongs to the frame may be
cyan, or the two halves of the screen stop separating."* The rule is right. The
values do not deliver it, because separation was assigned to **hue** and hue is
the first thing to go at low brightness.

**2. Sub-pixel structure.** All that separation is carried by borders — and
every border in `theme.tres` is 2-4 px against a 1080-wide design viewport:

| Design width | On a 390 px phone | Count |
|---|---|---|
| 2 px | **0.72 CSS px** | 18 |
| 3 px | **1.08 CSS px** | 20 |
| 4 px | **1.44 CSS px** | 4 |

A 0.72 CSS px border is below one physical pixel at 1× and is the first thing
mobile texture filtering eats. The gold trim doing all the structural work is
effectively not being drawn.

**3. Type is genuinely small, and set in the worst possible face for it.**
Under `window/stretch/mode="canvas_items"`, a design pixel maps to
`design_px × phone_width ÷ 1080`:

| Design size | On a 390 px phone | Declarations |
|---|---|---|
| 38 px | 13.7 CSS px | 68 |
| 34 px (theme default) | 12.3 CSS px | 18 |
| 30 px | 10.8 CSS px | 19 |
| 26 px | 9.4 CSS px | 22 |
| 22 px | 7.9 CSS px | 3 |
| 16 px | **5.8 CSS px** | 2 |

The body face is EB Garamond at weight 400 — an old-style serif with hairline
strokes and a small x-height. It is a beautiful face at 16 pt on paper and the
single worst choice at 10 CSS px on a backlit phone. The 16 px offenders are
`scenes/console/sir_fish_tank.tscn:474` and `scripts/modals/party_modal.gd:170`.

### 0.3 The consequence for this exploration

Two of the three failures — type scale and border weight — **are not art-style
questions at all**. They are wrong in every style. So they ship first, on their
own, before any style decision (§1). Only the third failure, the luminance
distribution, is genuinely a question of art direction, and that is what the two
candidate styles answer differently.

### 0.4 Non-goals — do not drift into these

- No gameplay, odds, balance, or `Tuning.SLOT_STRIP` changes. The 50.038% win
  rate and the tests asserting it stay untouched.
- No new third-party assets. §0.1.2 / §23.1 still stand: every mesh, texture,
  icon, material and glyph is generated. **Fonts are the established
  exception** (Cinzel, EB Garamond and Crimson are all already vendored under
  `assets/fonts/` with their OFL licences) — and both candidate styles are
  deliberately specified to use faces **already on disk**, so neither requires a
  download.
- No re-modelling. Both styles keep every Meshy/Blender mesh, every armature,
  and every animation clip exactly as they are. Only materials and palette
  change.
- No settings screen. There is none today (`find scenes scripts -iname
  "*setting*"` returns nothing), and building one is not a prerequisite for
  either style. Whether the winning style later becomes a *toggle* is §6.

---

## 1. Phase 0 — the fixes that are true in every style

Do this first, on its own branch, and ship it. It is the majority of the
user-visible relief and none of it is a style commitment.

### 1.1 The type ramp

Replace the current 27 distinct ad-hoc sizes with a six-step ramp. The floor is
**40 design px = 14.4 CSS px** on a 390 px phone, which is the point below which
body text stops being comfortable at arm's length in the dark.

| Step | Design px | On a 390 px phone | Replaces | Use |
|---|---|---|---|---|
| XS | 40 | 14.4 | 16, 22, 24, 26, 28, 30 | captions, chips, tags |
| S | 46 | 16.6 | 32, 34, 36, 38 | body, labels, button text |
| M | 54 | 19.5 | 39, 40, 42, 44, 45 | emphasis, prices |
| L | 64 | 23.1 | 46, 48, 51, 52 | subheads |
| XL | 78 | 28.2 | 56, 60, 72 | headings |
| XXL | 96 | 34.7 | 84, 90, 96 | display numerals, damage |

**The trap.** The viewport is 1920 tall and the Presentation Redesign's §4
screen budget already allocates every band of it. Raising 94 declarations by
20-45% *will* overflow layouts. This is the actual work of Phase 0 — not the
find-and-replace, but the per-screen re-fit afterwards. Budget for it, and check
every screen: battle, console, shop, forge, inventory, party, quest result.
Where a panel genuinely cannot fit its text at the ramp, the fix is fewer words
or a taller panel, **never** a size below the XS floor.

### 1.2 Body face weight

EB Garamond is a variable font with a `wght` axis, so this costs nothing and
needs no new file. In `assets/body_font.tres`:

```
variation_opentype = {
"wght": 600.0
}
```

If 600 still reads thin on device, `assets/fonts/Crimson-Semibold.ttf` is
already vendored and imported — swap `base_font` to it rather than downloading
anything. Cinzel stays as the display face in both candidate styles; it is the
game's identity and it is heavy enough already.

### 1.3 Border weight

Every border in `assets/theme.tres` goes to a floor of **7 design px** (2.5 CSS
px). Current 2 px → 7, 3 px → 8, 4 px → 10. This is what makes panel edges
survive mobile filtering, and it is why both candidate profiles gate on
`min_border_css_px`.

### 1.4 Phase 0 gate

```bash
python3 tools/palette_audit.py --profile lantern --strict
```

Phase 0 alone will still fail the palette half of the `lantern` profile — that
is expected and correct. What must pass after Phase 0 is the **type scale** and
**border weight** sections: no design size below 40, no border below 7. Confirm
those two sections are clean before merging, and leave the palette failures for
Phase 1.

---

## 2. The two candidate styles

Both are fully specified as implementable documents in this folder. Both keep
every mesh, rig and animation. Both were designed against `tools/palette_audit.py`
and **both are verified to pass their own gate** — the palettes in those specs
are not sketches, they are solved values.

### 2.1 Art Style A — Lantern (high-contrast night)

`Sir Fish - Art Style A - Lantern Spec.md`

Keeps the bioluminescent night forest. The diagnosis is not that the game is
dark; it is that the game is *uniformly* dark. Lantern widens the range instead
of lifting it: the background drops to near-black (0.002 luminance), and the
console lifts into a genuine lit mid-tone (panel 0.145, raised frame 0.210), so
the console reads as a lantern held up in real darkness. Every chrome edge
clears 2.0:1 and the three chrome tiers are separated by ≥0.045 luminance.

- **Preserves** the art direction the project has invested most heavily in — the
  Meshy pipeline's palette, the storm transform, the reliquary modals, §6.1's
  blue/green/gold rule.
- **Stays OLED-friendly**, which matters for the actual use case: playing in a
  dark room at night. A full-bright UI is legible but fatiguing at 1 a.m.
- **Risk**: still a dark game. If the real problem turns out to be the phone at
  minimum brightness in a *bright* room, Lantern helps but does not fully solve
  it.

### 2.2 Art Style B — Storybook (flat illustrated poster)

`Sir Fish - Art Style B - Storybook Spec.md`

Abandons atmospheric rendering. Fog off, glow near-off, lights flattened, every
surface a flat block of colour with a heavy ink outline. Depth stops being haze
and becomes discrete poster layers, each a measured luminance step apart. The
console becomes a printed card: dark ink on pale paper.

- **Most legible by construction** — every element is its own value block, so
  nothing depends on subtle separation surviving a dim screen.
- **Probably faster on web.** Killing fog, glow and most of the lighting model
  cuts shader permutations, which is the exact cost centre
  `design documents/Sir Fish - Shader Link Counting Experiment.md` was written
  about. Treat this as a hypothesis to measure, not a promise.
- **Risk**: the biggest departure. It discards the bioluminescent identity, and
  the ink-outline pass costs a second draw per outlined mesh — which must be
  held to characters and hero props, never the scatter multimeshes.

### 2.3 Considered and parked — Dawn (daylight repaint)

A third direction was worked up and rejected *for now*: keep the forest and the
atmospheric renderer, but move the whole thing from night to overcast dawn. It
is the cheapest of the three to try, because `Tuning.storm_tint()` already
proves the machinery — the storm mood is a *transform* of the fair-weather
palette rather than a second copy, and Dawn could be the same kind of transform
in the other direction.

It is parked rather than specified because it is the worst fit for the stated
problem: the complaint is specifically about **playing at night**, and a
daylight palette on a phone in a dark room is the one outcome that is more
uncomfortable than what ships today. Promote it only if the night test (§3)
shows the user is mostly playing in bright ambient light after all.

---

## 3. How to decide — the night test

The whole point is a judgement that can only be made on the actual device in
the actual conditions, so the exploration is built around getting builds onto
the phone rather than around screenshots.

**Start on the proof sheets, not in the engine.** Two static pages in this
folder render the candidate palettes at true on-device scale, and they exist
because of a flaw in the obvious approach: your eye adapts within seconds, so
judging dark palettes *sequentially* — loading one build after another — compares
a live impression against a memory formed under different adaptation. Two builds
cannot be open at once on one phone, so the itch route is inherently sequential
for exactly the judgement that most needs simultaneity.

| File | Compares | Settles |
|---|---|---|
| `Sir Fish - Proof 1 - Style Comparison.html` | current / Lantern / Storybook | whether each style's structure survives a dim screen; how much of the win is the Phase 0 type ramp alone |
| `Sir Fish - Proof 2 - Lantern Hues.html` | Lantern in teal / purple / green / red | which console hue collides with an existing signal colour |

Open them straight off disk on the phone. Both are self-contained apart from
Google Fonts, and both scale a literal 1080-design-px mock the way
`canvas_items` stretch scales the real game, so type and borders land at the
size they land at on device.

**Use the proofs to eliminate, not to choose.** A style that fails there will
fail in the engine. What they cannot show is the render pass — no cel shading,
fog, glow or ink outlines — so Storybook is under-represented by construction
and must not be dropped on aesthetics at this stage, only on whether its
structure reads.

### 3.1 Getting each style onto the phone

`.github/workflows/deploy-itch.yml` already exports the `Web` preset and pushes
it to itch via butler, triggered manually. Each style branch gets a build there.

**Use a separate itch project for the A/B**, not extra channels on the live
page. A game page embeds one browser-playable build at a time, so pushing
`lantern` and `storybook` to different channels of `darkcascade/sir-fish` still
means flipping which one is playable between comparisons — and it risks the
public page showing a prototype. Create a second, restricted project (e.g.
`sir-fish-style-test`), point a copy of the workflow at it via its own
`ITCH_GAME`, and push both candidates there as channels `lantern` and
`storybook`. The live page stays clean.

### 3.2 The test itself

Run it in the conditions from the complaint: **dark room, phone at ~25%
brightness, at arm's length, no glasses adjustment, after 10 p.m.** Do all three
builds (current, A, B) in one sitting — impressions do not survive a day's gap.

For each build, time these and note failures:

1. Read the gold total without leaning in.
2. Tell the console frame from the world behind it, at a glance.
3. Find the HP bar of a specific party member.
4. Read a shop price and its item name.
5. Open a modal and tell the tablet edge from the scrim.
6. Play one full encounter. Note every moment of hesitation about *where*
   something is, separately from *what* it says.

The scoring that matters is item 6 and the second half of item 2. Text
legibility is largely settled by Phase 0; what the styles are competing on is
whether the *structure* reads instantly.

### 3.3 The gate

Pick one style. The loser stays on file as a documented spec — this folder is
the record of what was considered, and a parked spec is cheap to revive. Do
**not** ship both behind a toggle as a way of avoiding the decision: a toggle
means every future UI change has to be authored and verified twice, and there is
no settings screen to hang it on. A style toggle is only worth building later,
as a deliberate accessibility feature, once one style is the committed default.

---

## 4. Sequencing

| Step | Work | Gate |
|---|---|---|
| 0 | Read the proof sheets on the phone at night (§3) | at least one style eliminated, or both confirmed worth building |
| 1 | Phase 0 — type ramp, body weight, border weight (§1) | type + border sections of the audit clean; every screen re-fitted |
| 2 | Branch `art/lantern`, implement Spec A | `--profile lantern --strict` passes |
| 3 | Branch `art/storybook`, implement Spec B | `--profile storybook --strict` passes |
| 4 | Push the survivors to the style-test itch project (§3.1) | playable builds |
| 5 | Night test (§3.2) | one style chosen |
| 6 | Merge the winner to `main`; leave the loser's spec in place | audit gate added to CI |

Step 0 is free and can happen tonight; it exists to avoid spending steps 2 and 3
on a style the proof would have ruled out. Steps 2 and 3 are independent and can
be done in either order, or in parallel on separate branches — but implementing
*both* in full before deciding is the expensive mistake this sequence is arranged
to prevent. Prefer a palette-only spike of the survivor (`tuning.gd` §6.1 is one
file) over a full implementation, with the caveat that Storybook needs at least
its §4.1 environment changes to get a fair hearing — a poster palette rendered
with fog, glow and filmic tonemap still on will look wrong and lose unfairly.

## 5. Risks

- **Phase 0 overflow is the real cost.** The palette work in both specs is
  mechanical — one file, verified numbers. Re-fitting seven screens to a 20-45%
  larger type ramp is not, and it is where the schedule will actually go.
- **`Tuning.C_*` is read by 40 script files.** That is a genuine chokepoint in
  the good sense — the constants are the single source of truth — but a handful
  of call sites derive their own tints from those constants
  (`storm_tint()`, `cel_materials.gd`, `parallax_background.gd`). Changing a
  base hue changes their outputs too. Both specs call out the derived-colour
  sites they touch.
- **The audit is a floor, not a taste test.** A palette that passes
  `--strict` can still be ugly. The gate exists so the night test is spent
  judging whether a style is *good*, rather than rediscovering that it is
  *illegible*.

## 6. If the answer turns out to be "both"

If the night test says Lantern wins at night and Storybook wins in daylight,
that is a real finding and the honest response is a style toggle — but build it
as its own piece of work, after one style is the default, and build the settings
screen it needs first. Do not let it become the reason neither style ships.
