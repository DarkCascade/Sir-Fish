# Sir Fish — Art Style A: Lantern (High-Contrast Night) Spec

Target: keep the bioluminescent night forest and make it readable on a phone at
night by **widening the luminance range instead of lifting it**.

Written against `main`, on top of Phase 0 (`Sir Fish - Art Style Exploration
Plan.md` §1). §-references in the form §6.1 point at
`scripts/autoload/tuning.gd`; bare §2 points at this document.

**This is a presentation spec. It changes no gameplay, no odds, no balance.**

---

## 0. Before you start

### 0.1 Phase 0 is a hard prerequisite

Do not start this spec until the exploration plan's §1 has landed: the type ramp
(40 px floor), the body-face weight bump, and the 7 px border floor. This spec
assumes borders are thick enough to carry a colour and that no text is below the
XS step. Implementing Lantern on top of 0.72 CSS px borders wastes the palette
work — the edges still will not draw.

### 0.2 Verify with the audit, continuously

```bash
python3 tools/palette_audit.py --profile lantern --strict
```

This is the gate, and every number in §2 is solved against it. When you have
finished §2 it must exit 0. If you change any value in §2's table, re-run it —
several of those values are within 0.05 of a floor and are not free to nudge.

### 0.3 The one idea

The game is not too dark. The game is **uniformly** dark: 11 of 15 world and
chrome colours sit below 0.05 luminance, so nothing separates from anything.

Lantern's answer is not to brighten the game. It is to **push the background
further down and the console further up**, so the frame reads as a lit object
held in real darkness. The night stays night — darker than it ships today, in
fact, at the very back — while the thing you actually read becomes a genuine
mid-tone surface.

This is also the cheapest possible reading of §6.1's existing rule. That rule
already demands the world and the frame separate; it just assigned the job to
**hue**, and hue is the first channel to fail at low brightness. Lantern
reassigns it to **luminance**, which survives.

### 0.4 Non-goals

- No re-modelling, re-rigging, or re-animating. Every `.glb`, armature and clip
  is untouched.
- No change to §6.1's semantic rule. Cool blue is still the light, green is
  still the ground, gold is still the UI. Only the values move.
- No change to the reliquary modals' *violet identity* (§6.1e). Their luminance
  moves; their hue does not.
- No settings screen, no toggle. Lantern replaces the current palette in place.

---

## 1. The look in one paragraph

A lantern in a black forest. The back of the world falls away to near-black and
the near trunks read as silhouettes against it. The console is the light source
in the composition: a lit teal-green stone cabinet, its raised frame catching a
warm gold rim bright enough to be an actual edge, its recessed wells dropping
back into shadow. The moss path and the undergrowth immediately around the
console catch that light and are the brightest things in the world layer,
falling off fast into the dark. Crystals and runes still glow sapphire; the
modal layer is still a plum-black tablet in violet mist, just far enough
separated from its scrim that you can see where it ends.

---

## 2. Palette — `scripts/autoload/tuning.gd` §6.1

Rewrite **in place**. Every constant name is unchanged, so all 40 consuming
script files keep resolving; only the values move. Do not add or rename
constants.

The `lum` column is WCAG relative luminance and is the reason each value is what
it is — those are the numbers the audit gates on, not the hexes.

### 2.1 Console chrome — the lantern itself (§6.1c)

| Constant | New value | lum | Was | Why |
|---|---|---|---|---|
| `C_CONSOLE_BG` | `Color("040709")` | 0.0020 | `07171B` (0.0074) | **Darker.** The void behind the lantern. Going down here is what buys the console its contrast. |
| `C_CONSOLE_INSET` | `Color("194341")` | 0.0460 | `0B1E1C` (0.0108) | The recessed well. Still the darkest *surface*, but now 2.03:1 against its own panel, so the hole reads as a hole. |
| `C_CONSOLE_PANEL` | `Color("34756A")` | 0.1449 | `0D2A2A` (0.0191) | **The big move.** A lit teal mid-tone. 3.75:1 against the background — the panel finally has an edge. |
| `C_CONSOLE_STONE` | `Color("668761")` | 0.2102 | `3A4A3C` (0.0612) | The raised carved frame, the brightest chrome surface. 5.01:1 against the void. |
| `C_PANEL_BORDER` | `Color("BFA864")` | 0.4000 | `2E5A4E` (0.0844) | **Now a lit gold rim, not a dark teal line.** 2.31:1 against its own panel. This is the lantern's edge light and it is doing structural work. |

The three chrome tiers are separated by 0.099 (well→panel) and 0.065
(panel→frame), both above the profile's 0.045 floor. That is the depth read, and
it now survives a dim screen.

### 2.2 The world (§6.1)

| Constant | New value | lum | Was | Why |
|---|---|---|---|---|
| `C_SKY` | `Color("193152")` | 0.0301 | `0B2C4E` (0.0242) | Canopy gap, deep night blue. Barely moved. |
| `C_FAR_HILLS` | `Color("2A586E")` | 0.0860 | `0E3A52` (0.0373) | Lifted so the treeline is a shape rather than a smudge. |
| `C_MID_TREES` | `Color("2E7366")` | 0.1380 | `14584E` (0.0768) | Mid canopy. |
| `C_NEAR_TREES` | `Color("234B58")` | 0.0609 | `0A1C24` (0.0102) | Near trunks. Still the dark silhouette layer, but 2.13:1 against the void so the silhouette has an outline. |
| `C_GROUND` | `Color("41905C")` | 0.2184 | `2F6B44` (0.1154) | Lit moss down the path centre — the brightest world surface, because it is what the lantern lights. |
| `C_BRUSH` | `Color("3B826B")` | 0.1796 | `0C2A2C` (0.0192) | **Deliberately brighter than the near trunks now** (2.07:1). The undergrowth catches the console's light; the trunks in front of it do not. That inversion is the whole lantern conceit. |
| `C_ROCK` | `Color("496071")` | 0.1097 | `2A3A44` (0.0394) | Scatter rocks, blue-slate. |

### 2.3 Text (§6.1)

| Constant | New value | lum | Was | Why |
|---|---|---|---|---|
| `C_TEXT` | `Color("F5F1E6")` | 0.8804 | `F5F1E4` | Unchanged in practice. 4.77:1 on the new lit panel. |
| `C_TEXT_DIM` | `Color("B5D2C8")` | 0.6009 | `9CB0AC` (0.4110) | **Brighter, and its home moved** — see §2.6. |
| `C_TEXT_GOLD` | `Color("EFD694")` | 0.6858 | `F0D588` | Headings on dark stone. 3.77:1 on the panel: AA-large, which is what it is for. |
| `C_GOLD` | `Color("D8AF52")` | 0.4587 | `D4A843` (0.4241) | The frame's trim gold, one step brighter. |

### 2.4 Reliquary — the modal layer (§6.1e)

Hue is untouched; these are the same plum and amethyst. Only luminance moves, so
the tablet separates from its own mist.

| Constant | New value | lum | Was | Why |
|---|---|---|---|---|
| `C_RELIQUARY_STONE` | `Color("614984")` | 0.0897 | `1A1526` (0.0090) | The tablet. Now 2.26:1 against the scrim. |
| `C_RELIQUARY_MIST` | `Color("251536")` | 0.0120 | `241832` (0.0126) | The scrim. Essentially unchanged — a scrim is *supposed* to be dark. |
| `C_RELIQUARY_STONE_DARK` | `Color("100B16")` | 0.0041 | `0E0B16` | Underside of a carved edge. Unchanged in practice. |
| `C_CRYSTAL_BRIGHT` | `Color("DCC1F7")` | 0.6007 | `D8B4FE` (0.5440) | Lit facet / heading on plum stone. 4.66:1 on the tablet. |

`C_RELIQUARY_STONE_LIT` and `C_CRYSTAL` / `C_CRYSTAL_DEEP` are not in the gate
but must be re-derived to sit sensibly between their neighbours — keep
`STONE_LIT` roughly midway between `STONE` and `CRYSTAL_BRIGHT`.

### 2.5 Everything else in §6.1

Character colours (`C_WARRIOR_*`, `C_RANGER_*`, `C_MAGE_*`, `C_ORC_*`,
`C_FISH_*`), signal colours (`C_DANGER`, `C_HEAL`, `C_LIGHTNING`, `C_DEFEND`,
`C_FIRE`, `C_ICE`, `C_MEAL`), the arcane accents and the frame ornament colours
(`C_VINE`, `C_FLOWER`, `C_GEM`, `C_GOLD_BRIGHT`, `C_GOLD_DARK`) **stay as
authored**. They already sit in the upper range and they are the game's
recognisable identity. Check them against the new panel with the audit's text
section, but do not retune them speculatively.

### 2.6 One design ruling this palette forces

**A lit panel carries primary text only. Secondary text lives in the wells.**

At 0.145 luminance, `C_CONSOLE_PANEL` is bright enough that no genuinely *dim*
colour can clear AA on it — that is arithmetic, not preference: even pure white
only reaches 4.77:1 there. So `C_TEXT_DIM` moves home. It sits on
`C_CONSOLE_INSET` (6.78:1, comfortable AA) and on the void, never on the lit
panel.

Where a screen currently puts dim text on a panel, either promote it to `C_TEXT`
or move it into a recessed well. Both are one-line changes at the call site.

**And no text ever sits on `C_CONSOLE_STONE`.** At 0.210 luminance the raised
frame cannot carry legible text of any colour. It is ornament — carved chrome —
and it is already used that way today. Do not start putting labels on it.

---

## 3. Lighting and environment — `scenes/battle/battle_world.tscn`

The palette above is the unshaded half. The lit 3D half needs matching work or
the world will not land where §2.2 says it does.

| Setting | Current | New | Why |
|---|---|---|---|
| `ambient_light_energy` | 0.5 | **0.75** | Lifts the world's floor so `C_NEAR_TREES` actually reaches its 0.06. |
| `adjustment_contrast` | 1.08 | **1.18** | Widens the range rather than lifting the midpoint — the whole thesis of this style. |
| `adjustment_saturation` | 1.3 | **1.15** | High saturation at low luminance is what makes dark colours read as mud. Pull back as the range widens. |
| `fog_light_color` | `(0.114, 0.365, 0.494)` | `(0.16, 0.42, 0.55)` | Fog is the far-depth cue; it has to sit above `C_FAR_HILLS` or distance inverts. |
| `fog_depth_begin` | 9.0 | **14.0** | Start the haze further out. Near-field fog is what currently flattens the mid-ground into the background. |
| `tonemap_white` | 2.2 | 2.2 | Unchanged. |
| `glow_intensity` | 0.7 | 0.7 | Unchanged — the bioluminescence is the identity. |

`Tuning.FOG_DEPTH_BEGIN` is the source of truth (`battle_world.gd:34` enforces
it over the scene's inline value), so change the constant, not just the `.tscn`.

The three lights (`light_energy` 0.75 / 0.95 / 0.7) stay as authored. The lift
comes from ambient, deliberately: raising the key would re-introduce hard
falloff and re-crush the shadows this style is trying to open up.

## 4. Storm mood — `Tuning.storm_tint()`

The storm is a transform of the fair-weather palette (§6.1 "storm mood"), so it
inherits the new values for free. But `STORM_DARKEN := 0.50` was tuned against a
palette whose panels sat at 0.019; applied to a 0.145 panel it will now produce a
*more* legible storm than clear weather, which is backwards.

Retune to `STORM_DARKEN := 0.35` and re-check that the storm's console still
clears the structural floors. The audit does not cover the storm transform —
verify by eye, in a storm encounter, on the phone.

## 5. Files that derive colour and must be re-checked

Changing base constants changes everything computed from them. Look at each:

| File | What it derives | Watch for |
|---|---|---|
| `scripts/battle/cel_materials.gd` | cel ramp bands from base hues | Bands were tuned against dark bases; the ramp may need re-spacing. |
| `scripts/battle/parallax_background.gd` | layer tints, storm tint application | Line ~127 applies the storm tint here rather than darkening the palette — re-check against §4. |
| `scripts/console/ornate_frame.gd` | the carved-stone frame geometry's shading | This is where `C_PANEL_BORDER`'s new gold rim actually gets drawn. The single most important file to eyeball. |
| `scripts/ui/item_card_style.gd` | item card fills and rarity treatment | Cards sit on the new panel; check rarity colours still separate. |
| `scripts/modals/item_glyph.gd` | rarity ring / glow around Meshy icons | Glow was tuned against a near-black modal. |
| `scripts/battle/overworld_field.gd` | scatter prop materials | Uses `C_GROUND`, `C_BRUSH` — §2.2 inverted their relationship. |

## 6. Verification

1. `python3 tools/palette_audit.py --profile lantern --strict` exits 0.
2. Every screen opened on device: battle, console, shop, forge, inventory,
   party, quest result. For each, the panel edge is visible without leaning in.
3. A storm encounter, on device, after §4's retune.
4. A modal opened over a battle — the tablet edge must be findable instantly.
5. Grep guard from §6.1e still holds: nothing outside `scripts/modals/` +
   `item_card_style.gd` + the modal scenes reads a `C_RELIQUARY_*` /
   `C_CRYSTAL*` / `C_THORN*` constant.
6. The night test from the exploration plan §3.2.

## 7. Risk and rollback

The palette is one file and one commit. Rollback is `git revert`; nothing else
in this spec is structural.

The genuine risk is §5: derived colours drifting somewhere nobody looks. The
mitigation is that all six of those files are enumerated above — walk them
deliberately rather than waiting for the derived colour to surface in a
screenshot.

The strategic risk is that this is still a dark game. If the night test says
the phone is the problem rather than the palette, Lantern will have improved
things without solving them, and `Art Style B — Storybook` is the answer.

## 8. Effort

Palette rewrite is an afternoon. §5's six derived-colour files are the real
work — call it two sessions with device checks between. §3 and §4 are small but
must be done on device, not in the editor.
