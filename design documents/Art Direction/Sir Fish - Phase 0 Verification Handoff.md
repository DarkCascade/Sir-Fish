# Sir Fish — Phase 0 Verification Handoff

For a session running with **Godot MCP Pro tools connected** (this needs the
Godot editor open locally with the MCP plugin running — a cloud session can't
reach it). Everything mechanical is already done and pushed; what's left is
exactly the three things that needed a renderer, which the session that did
the mechanical pass didn't have.

**Start here:** `Sir Fish - Phase 0 Implementation Questions.md` (same
folder) is the full record of what was done and why. This doc is just the
worklist distilled from its §1, §3 and §6 into concrete tool calls.

**Branch:** `claude/itch-sir-fish-update-trsjcf`, currently `b1afa6a`, open as
PR #30. Pull it before starting — the type ramp, border floor, and body
weight are already committed there. Nothing below should touch `tuning.gd`'s
palette constants; that's Spec A's work, not this.

---

## 1. `quest_result.tscn` — the one real overflow risk

**Why:** `Panel` is fixed at 1760px tall (offset −880/+880) against a 1920px
viewport — 160px of slack, total. `Stats` is a plain `VBoxContainer`, no
`ScrollContainer`, holding 15 rows each at `custom_minimum_size = Vector2(0,
54)`. None of the 15 rows set their own font size, so they inherit
`default_font_size`, which Phase 0 just raised 34px → 46px (+35%). Godot
containers grow past a `custom_minimum_size` floor to fit content, so the
real question is whether the grown stack still fits in 1760px.

**Do:**
```
open_scene res://scenes/modals/quest_result.tscn
get_scene_tree                      # confirm Panel/Layout/Stats structure unchanged
play_scene
# trigger a quest_result modal in the running game — either a real run to a
# quest/level end, or find the fastest debug path (check scripts/autoload/debug.gd)
get_game_screenshot
```
Look for: any stat row's text clipped, the `Buttons` row (Primary/Secondary)
pushed off the bottom edge, or visible overflow past the panel's carved
border.

**If it overflows,** two fixes are on the table (pick one, don't invent a
third without checking back):
1. Wrap `Stats` in a `ScrollContainer` — the pattern already used in
   `inventory_modal.tscn` (`Panel/Layout/Scroll/Body`). Preserves the fixed
   panel size everywhere else.
2. Loosen `Panel`'s offsets — there's only 160px of margin total between
   1760 and the 1920px viewport, so this alone may not be enough on its own.

## 2. The Sir Fish tank plaque

**Why:** `scenes/console/sir_fish_tank.tscn:474`, the `PlaqueText` Label3D,
is the one site in the whole pass where the 2D type-ramp math doesn't apply —
Label3D size is `font_size × pixel_size` in 3D world units through a
sub-viewport camera, not the `canvas_items` stretch every other font size in
the game goes through. `font_size` was raised 16→40 (matching the ramp's XS
step) and `pixel_size` was divided by the same 2.5× (0.0016→0.00064) to hold
the on-screen size constant — the intent was sharper glyph rasterization
without changing how big the plaque text reads, but that's a guess from
reading the file, not a render.

**Do:**
```
open_scene res://scenes/console/sir_fish_tank.tscn
get_editor_screenshot
```
Look for: "SIR FISH" on the plaque — same apparent size as before, noticeably
crisper edges, and (the actual risk) **not** overflowing the plaque mesh
bounds. If it looks larger or smaller than intended, the two numbers to
adjust are exactly `font_size` and `pixel_size` on `PlaqueText` — keep their
product constant (`font_size × pixel_size = 0.0256` currently) to preserve
size while changing sharpness, or move them independently if the intent is
actually to change the plaque's rendered size.

## 3. Body face weight — the on-device fallback

**Why:** `assets/body_font.tres` raised EB Garamond's `wght` axis 400→600.
The spec's own instruction: *"If 600 still reads thin on device, swap to
Crimson-Semibold."* This wasn't a wait-and-see hedge — it's a real fallback
already vendored and imported (`assets/fonts/Crimson-Semibold.ttf`), just not
wired in.

**Do:** Play a build (ideally on an actual phone, per the exploration plan's
whole point about screenshots not substituting for the device), and read a
body-weight paragraph — an upgrade blurb or item subtitle is the best test,
since that's what the comment in `body_font.tres` names as the face's job.

**If 600 still reads thin:**
```
read_script res://assets/body_font.tres
edit_script    # swap base_font's ExtResource from EBGaramond-VariableFont.ttf
               # to Crimson-Semibold.ttf; Crimson is a static weight, not
               # variable, so the variation_opentype wght block goes away
               # entirely, not just its value
```
Don't push `wght` past 600 as the first move — `body_font.tres`'s own comment
already flags that EB Garamond's axis starts deforming letterforms above
~700, which is a worse failure mode than "reads a bit thin."

## 4. The other five screens

§1.1 names seven screens to re-fit: battle, console, shop, forge, inventory,
party, quest result. §1 above covers quest result (the one static analysis
flagged as highest-risk) and the tank plaque covers most of console. The
remaining five weren't flagged by the static pass, which means they're
*probably* fine — nothing else in the diff touched a fixed-height container
the way `quest_result.tscn` does — but "probably fine" from reading a diff is
exactly the gap this handoff exists to close. A fast pass:

```
play_scene
# walk: an expedition encounter (battle), the console/slot view, open the
# shop modal, the blacksmith/forge tabs, the inventory modal, the party
# modal
get_game_screenshot   # after each
```
Nothing needs fixing unless something's visibly wrong — clipped text, a
button label overflowing its own bar, a card's content pushing past its
border. If everything reads clean, that's the confirmation this pass never
got, and Phase 0 can be considered actually done rather than just merged.

## 5. When done

Update `Sir Fish - Phase 0 Implementation Questions.md` §6 with what was
found — even "checked, no issues" for each item is worth recording, since
right now that document reads as entirely open. Then Phase 0 is genuinely
closed and the exploration plan's step 0 (proof sheets) / steps 2-3 (branch
and implement whichever style the night test picks) can proceed without this
hanging over them.
