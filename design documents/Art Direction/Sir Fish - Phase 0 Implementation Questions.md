# Sir Fish — Phase 0 Implementation Questions

Written against the implementation of `Sir Fish - Art Style Exploration Plan.md`
§1 (Phase 0), done in this pass. §-references point at that document unless
stated otherwise.

**Scope read:** "implement this spec as written" is read as **§1 only** — the
type ramp, body weight, and border floor. §2/§3 describe the two candidate
styles and the night-test process but don't instruct any code change
themselves, and §4's own sequencing gates implementing either full style
(steps 2-3) behind eliminating one on the proof sheets (step 0) first, which
is a human, on-a-phone, in-a-dark-room judgement — not something this pass
can do. If "as written" meant go further than §1, say so and I'll continue.

---

## 1. The one real blocker: no Godot editor in this environment

This session runs in an isolated cloud container with no Godot binary, no
Godot MCP server, and no way to open the project and look at it rendered.
That collides directly with two things §1 explicitly calls for:

- **§1.1's "trap."** The spec is direct about this: *"This is the actual work
  of Phase 0 — not the find-and-replace, but the per-screen re-fit
  afterwards."* The find-and-replace is done (§2 below) and machine-verified.
  The re-fit is not done, because it requires looking at seven rendered
  screens and I cannot render any of them here.
- **§1.2's on-device fallback.** *"If 600 still reads thin on device, swap to
  Crimson-Semibold."* I implemented the primary instruction (wght 600) and
  left the fallback as a documented option in the font resource's comment
  (see `assets/body_font.tres`). Whether it's actually needed is a device
  judgement I can't make from here.

**What this means practically: before merging, someone needs to open the
project in the Godot editor (or build + play it) and walk the seven screens
named in §1.1** — battle, console, shop, forge, inventory, party, quest
result — the same list the spec names. §3 below narrows that to the one
screen I'd check first.

## 2. What was verified, mechanically

`python3 tools/palette_audit.py --profile lantern --strict` now fails with
**10 findings, all of them palette** (§6.1 luminance work — Spec A's job, not
Phase 0's). Zero findings in the type-scale or border-weight sections, which
is exactly the clean split §1.4 asks for:

- **Type**: 273 declarations, down to exactly the 6 ramp values (40/46/54/
  64/78/96), smallest 40px → 14.4 CSS px on a 390px phone. Floor held
  everywhere.
- **Borders**: 42 `border_width_*` lines in `assets/theme.tres`, down to
  exactly 7/8/10px (from 2/3/4), smallest → 2.53 CSS px.
- **Body weight**: `assets/body_font.tres` wght 400 → 600.

## 3. The one concrete overflow risk I can name without a renderer

I did a static pass (not a substitute for §1.1's real re-fit) looking for
fixed-size containers near the edited text, specifically because the spec
warns overflow is the real cost. One screen stands out:

**`scenes/modals/quest_result.tscn`.** The `Panel` is a *fixed* rect —
`offset_top = -880`, `offset_bottom = 880` against a 1920-tall viewport, so
1760px fixed height with only 160px of margin total. Inside it, `Stats` is a
plain `VBoxContainer` (**no `ScrollContainer`**) holding 15 rows, each an
`HBoxContainer` with `custom_minimum_size = Vector2(0, 54)`. None of those 15
rows set their own font size, so they all inherit `default_font_size` — which
this pass just raised **34px → 46px (+35%)**.

`custom_minimum_size` is a floor, not a cap — Godot will grow each row past
54px to fit 46px text plus line-height, so the real risk isn't clipped text
inside a row, it's the **whole stack growing taller than the fixed 1760px
panel**, with nothing to scroll and almost no margin to absorb it. This is my
best guess at the single highest-risk screen in the whole ramp, but it's a
guess from reading the file, not a measurement. Two fixes are available and
I deliberately didn't pick one, since both are layout decisions the spec
reserves for an in-editor pass:

1. Wrap `Stats` in a `ScrollContainer` — matches the pattern already used
   elsewhere (e.g. `inventory_modal.tscn`'s `Scroll`/`Body`).
2. Loosen the Panel's fixed offsets — there's only 160px of slack total, so
   this alone may not be enough.

## 4. Judgement calls made during the mechanical pass

The spec's ramp table enumerated the sizes it found at the time it was
written. A handful of live sites didn't match anything in that table, or
weren't reachable by `tools/palette_audit.py`'s own regex (positional
literals, ternaries, function defaults, a named constant, a 3D label). Each
was resolved individually rather than left inconsistent; all are small and
easy to revert if the call is wrong.

| Site | Was | Now | Reasoning |
|---|---|---|---|
| `scripts/modals/quest_result.gd:81` — victory/defeat title, a ternary the audit tool can't parse | `76 if _victory else 84` | `78 if _victory else 96` | Neither 76 nor 84 is in §1.1's table. Mapped each to its nearest ramp step (XL/XXL), preserving the victory-title-smaller-than-defeat relationship the original authored. |
| `scripts/overlay/damage_number.gd:4`, `scripts/overlay/battle_overlay.gd:164` — default parameters, not literal overrides | `42`, `40` | `54`, `54` | Both are real on-screen font sizes (floating combat numbers) the audit's regex can't see because it only matches `add_theme_font_size_override(...)` calls and theme overrides, not function signatures. Both were in the M group. |
| `scripts/autoload/tuning.gd` — `DROP_LABEL_FONT_SIZE` | `34` | `46` | A named constant, deliberately smaller than `spawn_world_label`'s default "so it reads as roughly twice as wide." Remapped to preserve that relationship (46 < 54) and updated the comment's embedded "40 default" to "54 default" so the doc stays accurate. |
| `scripts/ui/currency_feedback.gd:28`, `scripts/modals/shop_modal.gd:185`, `scripts/console/upgrade_tray.gd:60` — positional literal arguments to `show_number(...)` | `38`, `38`, `34` | `46`, `46`, `46` | Real font sizes, just passed positionally rather than by keyword, so no regex in the audit tool reaches them. Found by grepping call sites by hand. |
| `scenes/console/sir_fish_tank.tscn:474` — `Label3D.font_size`, a 3D world-space value, not a 2D canvas_items one | `font_size=16, pixel_size=0.0016` | `font_size=40, pixel_size=0.00064` | This is the one site where the ramp's "design px → CSS px" reasoning doesn't transfer — Label3D text size is `font_size × pixel_size` in world units, rendered through a sub-viewport camera, not scaled by the 1080-wide stretch math at all. I raised `font_size` to the XS step (for sharper glyph rasterization — a real, verifiable-by-reading-the-docs improvement) and divided `pixel_size` by the same 2.5× so the **on-screen size is unchanged**, rather than guessing whether the plaque should actually render bigger. **This is the one change in the whole pass I'd most want eyes on** — it's a different scaling domain than everything else here, and I have no way to confirm the plaque still fits its mesh. |

## 5. Scoped deliberately narrow, flagging in case that's wrong

- **Border floor's primary scope is `assets/theme.tres`, per §1.3's literal
  wording** ("Every border in `assets/theme.tres` goes to a floor of 7 design
  px") — but I did grep `scripts/` for code-built `StyleBoxFlat`s rather than
  leave that as a guess, and found exactly two:
  - `scripts/modals/party_modal.gd`'s `_bar_bg()` set a literal `2` —
    genuinely the same sub-pixel problem §1.3 exists for, so I raised it to
    `7` along with everything else.
  - `scripts/console/ornate_frame.gd`'s `_draw_rounded_outline()` takes its
    width from `clampf(border * 0.55, 4.0, 9.0)` — a formula feeding a
    hand-drawn decorative outline, not a fixed pixel value, and
    `ornate_frame.gd` is already named in `Sir Fish - Art Style A - Lantern
    Spec.md` §5 as a derived-colour file to walk during the actual style
    pass. I left it alone: retuning a clamped formula is a different kind of
    change than raising a literal, and it's already scheduled for deliberate
    attention rather than a blanket floor.
- **Didn't touch `tools/palette_audit.py` itself**, even though §4 above
  found real blind spots in its `scan_font_sizes()` (ternaries, default
  parameters, positional literals). The tool still did its one job correctly
  — it caught and reported the type-scale and border sections cleanly for
  everything it *can* see — but its declaration count (273) is a floor, not
  the true total. Worth hardening later if the ramp changes again, but didn't
  want to change the audit tool's own logic silently inside a pass whose
  point was applying a spec, not revising the instrument.

## 6. What to do with this

1. Open the project in Godot (or play a build) and check the seven screens
   §1.1 names, `quest_result.tscn` (§3) first.
2. Decide `quest_result.tscn`'s fix (scroll vs. a taller/repositioned panel)
   and apply it — I left this undone on purpose.
3. Look at the Sir Fish tank plaque (§4) and confirm the text still reads
   right and fits the plaque mesh.
4. Confirm on a real phone whether EB Garamond at wght 600 is legible enough,
   or whether §1.2's Crimson-Semibold fallback is needed.
5. Decide on §5's two scoping questions (GDScript-authored borders; the audit
   tool's blind spots) — both are fine to simply accept as out-of-scope for
   now if that's the call.

None of the above blocks committing this pass — the mechanical substitution
is verified correct by the audit tool, and every judgement call in §4 is
individually small and reversible. They're real open questions, not reasons
to hold the work.
