# Prompt — Wire the ranger and mage special invokers once the art arrives

**Context:** backlog P7 (`design documents/Sir Fish - Backlog.md` §7), decisions 7.1/7.4.
**Branch at time of writing:** `backlog-p3`, head `5449e21`.
**Blocked on:** two Meshy renders. Everything else is built and proven on the warrior.

The warrior's invoker already works end to end. This is the "do it twice more" task, and
it is mostly asset prep — but the prep has three steps that are easy to get wrong.

---

## What the art must be

The existing asset is `assets/ui/invoker/invoker_cleave.png`, derived from
`design documents/reference/special_invoker/cleave_button_prototype.webp` (the original,
with pips) and a later pip-less regeneration.

Each button's **label and glyph are baked into the image**, so the ranger and mage each
need their own render. Required properties, all of which the cleave render satisfies:

- **Same frame:** gold neon outline, brass ring, domed glass lens, warm label text.
- **An EMPTY tab below the circle — no pips.** The pip row is drawn live on top. Any
  pips baked into the texture cannot light up and will sit under the real ones.
- **Aspect 1201 × 1309** (≈ 0.917). The tab anchors are fractions of the image, so a
  different aspect moves the tab out from under the meter. If the new render's aspect
  differs, re-measure (below) rather than assuming.
- **Glyph and label:** ranger → bomb arrow, "Bomb Arrow". Mage → a heal/mend glyph,
  "Mend" or "Heal" (**the mage keeps her party heal — she does NOT get chain
  lightning**, decision 7.4).
- Palette: the cleave render came back already on-palette (its gold sampled `#D8A949`
  against the project's `C_GOLD` `#D8AF52`). Prompt the same neon-on-dark-glass style so
  the three read as a set.

Cost is roughly 9 credits per image. Meshy is otherwise on hold.

---

## Step 1 — Key the baked background (required)

The renders ship as **RGB with no alpha** and a baked dark-navy ground (`#13111B`). That
navy is within a hair of `C_PLUM_VOID` (`#120A17`), so it looks fine on the plum console
and visibly wrong on the rootwood and boss-obsidian themes.

**Do not use a flat colour-distance threshold.** The tab's interior and the ring's inner
shadows are the same dark value as the background, and a global key punches holes in
them. Use a **flood fill from the corners** so only the connected outside is keyed, plus
a soft ramp so the neon halo fades instead of being sliced.

This is the exact script that produced `invoker_cleave.png` — reuse it, changing only
the paths:

```python
from PIL import Image, ImageDraw
src = "<the new render>"
im = Image.open(src).convert("RGB"); W, H = im.size
px = im.load()
BG = (0x13, 0x11, 0x1B)                      # re-sample a corner if the render differs
def dist(c): return max(abs(c[0]-BG[0]), abs(c[1]-BG[1]), abs(c[2]-BG[2]))

NEAR = 18
mask = Image.new("L", (W, H), 0); mp = mask.load()
for y in range(H):
    for x in range(W):
        if dist(px[x, y]) <= NEAR:
            mp[x, y] = 255

for corner in ((0,0), (W-1,0), (0,H-1), (W-1,H-1)):
    if mp[corner] == 255:
        ImageDraw.floodfill(mask, corner, 128, thresh=0)

LO, HI = 6.0, 40.0                            # soft ramp keeps the neon halo
out = Image.new("RGBA", (W, H)); q = out.load()
for y in range(H):
    for x in range(W):
        c = px[x, y]
        if mp[x, y] != 128:                   # inside the silhouette
            q[x, y] = (c[0], c[1], c[2], 255)
        else:
            t = (dist(c) - LO) / (HI - LO)
            a = 0 if t <= 0 else (255 if t >= 1 else int(t * 255))
            q[x, y] = (c[0], c[1], c[2], a)
out.save("assets/ui/invoker/invoker_<name>.png")
```

Sanity figures for the cleave render: **64% opaque, 32% transparent, 2% soft**. Wildly
different numbers mean the background colour or `NEAR` needs adjusting.

**Verify by compositing** over all four console grounds before committing — `C_PLUM_VOID`
`#120A17`, `C_ROOTWOOD_VOID` `#140D08`, `C_OBSIDIAN` `#211A2E`, `C_CONSOLE_BG` `#040709`.
Paste the RGBA over each and look for a dark halo box or a chewed glow.

## Step 2 — Measure the tab

The meter is anchored to fractions of the artwork. For the cleave render:

| Edge | Fraction |
|---|---|
| left | 0.219 |
| right | 0.781 |
| top | 0.810 |
| bottom | 0.897 |

Recorded as `TAB_LEFT/RIGHT/TOP/BOTTOM` in `scripts/console/special_invoker.gd` because
they are a property of **the artwork**. If the new renders place the tab identically,
reuse them. If not, either re-measure per render and give each scene its own anchors, or
ask for a re-render that matches.

To measure: find the gold outline's inner uprights for x, and scan rows below the ring
for the band that is uniformly dark across the centre for y. The session that built this
used a "% of centre-row pixels within 26 of the background colour" scan — the tab
interior read 100% between y 0.810 and 0.897 and fell off sharply either side.

## Step 3 — Duplicate the scene

Copy `scenes/console/special_invoker.tscn` to `special_invoker_ranger.tscn` /
`_mage.tscn` and change **three** things:

1. the `Texture2D` ext_resource path → the new PNG;
2. the root node's `hero_class` → `&"ranger"` / `&"mage"`;
3. the **`Meter` child's `hero_class` too** — it is a separate property on a separate
   node. Missing this is the likely bug: the button dims correctly but the pips track
   the wrong hero.

Everything else (anchors, `mouse_filter = 2` on both children, `flat = true` on the
button, `show_behind_parent` on the art) carries over unchanged.

Consider instead making the texture an `@export var art: Texture2D` on
`special_invoker.gd` and keeping **one** scene, instanced three times with two exported
fields set per instance. That is closer to how the codebase does things
(`upgrade_tray.tscn` authors its cards as instances) and avoids three near-identical
`.tscn` files. Your call; if you do it, `hero_class` should propagate to the meter in its
setter so only one field needs setting.

---

## Behaviour that is already handled — do not rebuild it

- **The press path.** `SpecialInvoker._on_pressed()` calls
  `director.invoke_hero_special(hero)`. The director owns *every* rule — dead hero,
  already mid-action, meter short, no valid target, mage's heal with nobody wounded —
  and **spends nothing when it refuses**. Do not add checks in the button.
- **Charging.** Every icon a hero owns charges that hero's meter as it resolves
  (`SlotMachine._resolve_board`). Nothing per-hero needs adding.
- **The meter.** `ChargeMeter` listens to `EventBus.special_charges_changed` and filters
  on its own `hero_class`. Five pips (`Tuning.SPECIAL_PIP_COUNT`), cost 10
  (`SPECIAL_CHARGE_COST`), partial wedge on the filling pip.
- **Dim/lit state.** `_refresh()` sets `modulate` from `GameState.special_ready()`.

### The mage is the one behavioural difference

`resources/abilities/mage_special.tres` has `special_requires_wounded_ally = true` and
`special_targets_opponent = false`. So:

- With the party at full HP, a **full** mage meter still refuses the press and keeps the
  charges. The button will look ready and do nothing, which reads as a bug to a player.
- **Decide and implement one of:** dim the mage's button when no ally is wounded even at
  full charge (needs a "can fire right now" query the button can call out of combat —
  note `_refresh()` runs with `director == null` in town); or let it fire and waste; or
  show a distinct "held" state.
- Recommended: add `BattleDirector.can_invoke_hero_special(c) -> bool` that shares the
  guard chain with `invoke_hero_special()`, and have the button prefer it when a
  director exists, falling back to `GameState.special_ready()` when it does not. Keep
  the two in one function so they cannot drift.
- Because she targets no opponent, her button must remain usable when the last enemy is
  dying — that is exactly why `special_targets_opponent` exists.

---

## Acceptance

1. Two keyed PNGs in `assets/ui/invoker/`, verified over all four console grounds.
2. Ranger and mage buttons instantiable and correct: right glyph, right hero on **both**
   the button and the meter, pips inside the tab recess.
3. The mage's wounded-ally case handled deliberately, with a test.
4. `tests/test_specials.gd` extended: the ranger's button invokes the bomb arrow, the
   mage's refuses at full party HP and fires once someone is hurt (that guard is already
   tested at the director level in `_check_invoke_guards` — extend to the button).
5. Full suite green (`python tools/run_tests.py`).
6. **Rendered and looked at**, all three side by side, at several charge values. Pattern:
   `scratch/invoker_preview.gd` (gitignored) instantiates the scene, sets
   `GameState.special_charges[&"<hero>"]`, and saves a PNG.

---

## Traps

- **`--import` strips the MCP autoloads from `project.godot`.** New PNGs need importing;
  run it, then `git checkout project.godot` immediately. Confirmed twice.
- **Formation order for the tray is left = ranger, middle = warrior, right = mage.**
  `Tuning.PARTY_FORMATION` is indexed by position in `active_party`, which starts
  `[warrior]` and *appends* recruits — its comment used to claim a fixed
  "0 mage, 1 ranger, 2 warrior" and was wrong until `66298b9`.
- The tray itself still holds the three slot upgrades. Replacing it is a separate task
  (`P7 - Slot Upgrades to Town.md`) — these buttons can be previewed and tested without
  it.
- Do not save `.tscn` through the editor; edit on disk.
