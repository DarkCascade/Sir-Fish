# QUESTIONS — Web Delivery & Render Performance Spec

Working log for implementing `Sir Fish - Web Delivery & Render Performance
Spec.md`. Follows the project's standing discipline: implement what's
unambiguous and reversible, record every deviation, raise a question rather
than guess on anything that changes the player-visible result or that no
available tool can do safely.

Status: **Phase 1 (build hygiene) and part of Phase 3 (cheap GPU wins) done.**
Phase 2 (confirm renderer) resolved as already-correct, no change needed. The
rest of Phase 3 and all of Phase 4 are blocked on the questions below.

---

## Done

- **§2.2.1 Character atlases.** All seven (`knight_knight_texture.png`,
  `mage_mage_texture.png`, `rogue_rogue_texture.png`,
  `skeleton_{mage,minion,rogue,warrior}_skeleton_texture.png`) reimported at
  `process/size_limit=64`, `compress/mode=0` (Lossless), `mipmaps/generate=false`.
  Verified via the actual reimport output, not just the `.import` text:
  `knight_knight_texture` went from two 699 KB VRAM-compressed `.ctex` files
  (S3TC + ETC2, 1024×1024) to one 1.3 KB lossless `.ctex` (64×64). Confirmed
  in-game via `play_scene` + `get_game_screenshot` on the town scene — no
  visible regression there (the town background is a separate asset, see
  next item), and no new editor errors from the reimport.
  **Not yet visually confirmed on an actual character in battle** — see Q1.
- **§2.2.3 Background plates.** `blacksmith-bg.png`, `inn-bg.png`,
  `mayor-bg.png`, `town-with-purple-mist.png`, `town_overview.png`,
  `world-map.png` switched from `compress/mode=0` (Lossless) to `compress/mode=1`
  (Lossy) at `lossy_quality=0.85`. `particle_glow.png` deliberately left alone
  — it's a 64×64 alpha gradient, not a background plate, and lossy WebP on a
  soft alpha edge is more likely to band than save anything meaningful.
  Confirmed visually: the town screenshot above uses
  `town-with-purple-mist.png` post-conversion and shows no visible artefacting
  at this JPEG-viewer resolution.
  Measured effect on the shipped `.png` payload: **33.21 MB → 17.56 MB** so
  far (atlases + backgrounds combined; the spec's estimate was ~26.8 MB
  combined for these two items, so this is ahead of projection).
- **§2.2.4 Export filter.** Added an `exclude_filter` to the Web preset rather
  than switching `export_filter` away from `all_resources` (safer — narrower
  blast radius). Excludes `addons/script-ide/*` (confirmed zero references
  anywhere in `scripts/`, `scenes/`, or `project.godot`) and the parts of
  `addons/godot_mcp/` that are editor-only tooling
  (`commands/`, `ui/`, `utils/`, `websocket_server.gd`, `command_router.gd`,
  `plugin.gd`, the `skills.*.md` localizations) — **but deliberately keeps**
  `mcp_screenshot_service.gd`, `mcp_input_service.gd`, and
  `mcp_game_inspector_service.gd`, because `project.godot`'s `[autoload]`
  section references those three by path and Godot has to be able to load an
  autoload's script even though the script immediately disables itself via
  `OS.has_feature("editor")`. Verified those three files have no `preload`/
  `load()` calls reaching into anything now excluded. Also excludes `*.blend`
  project-wide.
- **§2.3 Side module.** `variant/extensions_support` set `false` in the Web
  preset (project ships no GDExtensions — both addons are pure GDScript).
- **§3.1 Confirm the renderer.** Read via
  `get_project_settings(section: "rendering/renderer")`:
  `rendering_method.web` already resolves to `"gl_compatibility"` — this is
  Godot 4.7's built-in default for the web platform, not something the spec's
  "no `.web` override in `project.godot`" observation should have read as
  unconfirmed. No change needed; noted here so nobody re-investigates it.
  `Vulkan 1.4.341 - Forward+` in the log line at the top of `get_output_log`
  is the **editor's own** renderer (desktop preview), unrelated to what the
  web export uses — don't let that log line read as a contradiction.
- **§3.2 MSAA.** Set `rendering/anti_aliasing/quality/msaa_3d.web = 0.0` via
  `set_project_setting`. Web-only override; editor/desktop preview unaffected.
- **§3.2 Glow.** `scripts/battle/battle_world.gd`'s `_ready()` now sets
  `env.glow_enabled = false` when `OS.has_feature("web")`. One line, gated,
  reversible, doesn't touch desktop/editor. **Not screenshot-verified against
  the web export** (no local web build was run) — see Q7.

### Not touched — VRAM compression variant

The spec's §2.2.1 also recommends `vram_texture_compression/for_desktop=false`
in the Web preset (drop the S3TC copy, keep ETC2 only), independent of the
atlas downscale above. **Applied** — flagged here rather than folded silently
into "Done" above because it's an export-preset change I could not verify by
reimporting (export presets don't reimport anything; the effect only shows up
in an actual `export_project` run, which I did not do — see Q8).

---

## Q1 — Character-atlas downscale not visually confirmed on an actual skinned character

**What's blocking a full check.** Verifying the atlas change end-to-end means
getting a knight/rogue/mage/skeleton-* combatant on screen — that requires
driving into a quest and a battle through the town UI (`play_scene` +
`click_button_by_text`/`find_ui_elements` navigation), which I stopped short
of given the size of the rest of this pass. What I *did* confirm: the reimport
pipeline produced a correct 64×64 lossless texture with no import errors, and
these are flat palette atlases (13–38 KB source PNGs) of exactly the kind
CLAUDE.md's Meshy pipeline notes describe as fine at low resolution.

**Ask:** would you like me to drive a quest to a battle screen and screenshot
one of each affected character (knight, rogue, mage, skeleton_warrior at
minimum) to confirm 64×64 reads cleanly at actual on-screen size before this
ships? If the coloring reads muddy or blocky at battle-camera distance, the
fallback is a size between 64 and 256 rather than reverting to VRAM
compression — worth knowing before an export.

## Q2 — MSDF fonts: which of the nine are "UI" vs. "body," and is softened body serif acceptable?

The spec (§3.5) recommends `multichannel_signed_distance_field=true` on "the
UI fonts" to kill the per-size/per-glyph rasterization hitch, with a fallback
of `preload`-ing exact glyph ranges where MSDF would visibly soften text.

I did not implement either option. The font set is:

```
Baloo2-Variable.ttf        (rounded — reads as a UI/heading face by name)
Cinzel-VariableFont.ttf    (fantasy display capitals — likely titles/headers)
Crimson-Bold / -BoldItalic / -Italic / -Roman / -Semibold / -SemiboldItalic
                            (five weights of one serif family — reads as body)
EBGaramond-VariableFont.ttf (serif — also reads as body)
```

I have not traced which theme slots (`theme.tres`) or which specific `Label`s
in `scripts/console/`, `scripts/overlay/`, `scripts/modals/` use which font,
so I can't tell from the names alone whether Crimson/EBGaramond are used at
the small, frequently-changing sizes MSDF would actually help with (damage
numbers, HP text) or only at large, static sizes (quest/item description
paragraphs) where MSDF's softening would be the more noticeable trade.

**Ask:** either (a) confirm Baloo2 + Cinzel are the two to flip to MSDF and
the Crimson/EBGaramond family should stay bitmap (my best guess from the
names), or (b) point me at which `Label`/`RichTextLabel` nodes render damage
numbers and the enemy name chip specifically — that's the actual hitch
source per the original smoothness analysis — so only those get MSDF and
everything else is left alone.

## Q3 — Folding `FillLight`/`RimLight` into ambient (§3.3) needs an art pass, not a mechanical edit

The spec frames this as "should be recoverable by tuning `shadow_tint` and
`ambient_light_energy`" — i.e., it explicitly expects iteration against how it
actually looks, not a value substitution I can compute from the shader math
alone. `cel_shade.gdshader`'s `light()` runs the band/rim computation per
light; removing two of three directional lights changes the specular rim
contribution (`SPECULAR_LIGHT += rim_color.rgb * rim * 0.5`, summed once per
light) and the banded diffuse mix, not just brightness — there's no single
number I can solve for that reproduces the current look exactly.

**Ask:** should I (a) make the cut and then iterate by eye via
`get_game_screenshot` against the current town/battle screenshots as a
reference, taking a few passes to retune `ambient_light_energy`/`shadow_tint`/
`rim_amount`, or (b) leave this one alone until there's a moment to look at it
together? Given it's the shader every character and prop in the game runs
through, I'd rather not land a lighting change on a guess.

## Q4 — §3.4 transparent-pass rework: explicitly out of scope for this pass

The spec itself calls this "the highest-risk item… should be prototyped
behind a flag and screenshot-diffed before it is committed," and sequences it
as Phase 4, after the others are measured. I have not touched
`cel_shade.gdshader`'s `blend_mix` / `CelMaterials.fade()`. No action needed
from you here unless you want to pull this forward — flagging only so it
isn't mistaken for "done" by omission.

## Q5 — §3.6 shader warm-up: needs a materials inventory I haven't built

Building a warm-up pass means enumerating every distinct material/shader
*variant* the game actually constructs at runtime — not just the four
`CelMaterials` factory functions, but every flavour `BattleVfx` builds
(`_unshaded()` calls with different blend/cull/billboard combinations, each
particle system's `ParticleProcessMaterial`). I read `cel_materials.gd` in
full but only sampled `battle_vfx.gd` in the original smoothness pass, not
exhaustively enough to enumerate every call site with confidence I wouldn't
miss one (a missed variant just means that one still compiles late, so this
is low-risk to get partially right — but I'd rather scope it properly than
half-build it).

**Ask:** worth a dedicated pass where I read `battle_vfx.gd` end-to-end,
enumerate every material construction site, and build a single hidden warm-up
node that instances one of each? Estimate: straightforward once scoped, but
it's a distinct chunk of work I didn't want to start speculatively inside this
same sitting.

## Q6 — §2.2.2 Animation-clip trimming: no safe tool for it, flagging as a blocker rather than guessing

This is the second-largest single win in the spec (~10 MB of the ~55 MB pck)
and I did **not** attempt it. Reason: Godot 4's glTF importer controls
per-clip inclusion through `_subresources` entries in the `.glb.import` file,
written by the Advanced Import Settings dialog — I don't have a verified,
current schema for "exclude this named animation from the import" I could
hand-write into seven `.import` files with confidence, and there is no
`execute_editor_script`-equivalent tool in this MCP build to drive the dialog
or call the importer API directly (confirmed absent from the current tool
list, matching the same gap `QUESTIONS-m8b.md` Q2 already recorded for a
different task). Hand-editing binary-adjacent import config on a guess risks
silently corrupting the animation import for all seven characters — exactly
the kind of thing this project's own discipline says to stop and ask about
rather than push through.

**Two paths forward, both outside what I can do with current tools:**

- **In-editor, one-time, per character:** open each `.glb` in the Advanced
  Import Settings dialog, switch to the Animation tab, uncheck everything but
  the ~10 clips `CombatantBakedAnimations` actually references (`Idle`,
  `Running_A`, `Hit_A`, `Death_A`, `Block`, `1H_Melee_Attack_Chop`,
  `1H_Ranged_Shoot`, `Spellcast_Shoot`, `Unarmed_Melee_Attack_Punch_A`,
  `Unarmed_Melee_Attack_Kick`), reimport. Five minutes of clicking per
  character, ten total — genuinely faster by hand than scripting it blind.
- **Durable fix, per the spec's own preference:** strip the unused actions in
  Blender before export, so the source `.glb`s themselves drop from ~4.7 MB to
  ~400 KB and the repo stops carrying the dead weight permanently rather than
  filtering it at every reimport.

**Ask:** do you want to do the in-editor pass yourself (fastest), or should I
attempt the Blender-side strip via the Blender MCP tools now available in this
session (`execute_blender_code`) against the source `.blend` files — the same
class of surgery already logged in `CLAUDE.md`'s enemy-rig pipeline notes?
That second path needs the source `.blend` files identified first — I haven't
located them (`blender/` directory exists in the repo but I haven't opened
it), and would want to confirm the export step reproduces the exact same
skin/rig before touching anything.

## Q7 — Glow-disabled web look not screenshot-verified against a real web export

I made the `OS.has_feature("web")` cut in `battle_world.gd`, but confirming it
*reads right* means running an actual web export and looking at it, or at
minimum forcing `env.glow_enabled = false` temporarily in the editor and
screenshotting a battle. I didn't do either — the editor screenshot above is
the town scene, which doesn't touch `battle_world.tscn`'s environment at all.

**Ask:** should I force the flag on in-editor and grab a battle screenshot for
a side-by-side before you next test the actual web build, or is this fine to
leave for you to eyeball on the next real web export?

## Q8 — Export-preset changes (extensions_support, VRAM compression variant, exclude_filter) are unverified beyond parsing

`export_presets.cfg` edits don't reimport anything and aren't exercised by
`play_scene` (which runs the editor's own Forward+ desktop preview, not an
export). I confirmed the file still parses (`get_editor_errors` clean after
`reload_project`) but have not run an actual `export_project` to confirm:

- the game still boots with `variant/extensions_support=false`,
- the `exclude_filter` doesn't accidentally catch something load-bearing I
  didn't think to check (I verified the MCP autoload scripts and
  `script-ide` specifically, but the filter is a glob against the whole
  project — one more pair of eyes on the final `export_presets.cfg` before
  the next real export would be cheap insurance),
- the `.pck` size actually lands near the ~20 MB estimate.

**Ask:** should I run `export_project` now (there's a Godot MCP export tool)
and report back the actual numbers, or would you rather do that yourself as
part of your normal deploy step, since it also re-triggers the GitHub Pages
publish?

---

## Method note

Every "Done" item above was checked at least one of these ways: (a) the
`.import` file's own reimport output (new `.ctex` byte size, new `dest_files`
paths — a stronger check than reading the text back, since it proves Godot
actually re-ran the importer against the new params), (b) `get_editor_errors`
clean after `reload_project`, or (c) an in-editor `play_scene` +
`get_game_screenshot` against a scene the change actually touches. Items
without a screenshot check against the *specific* scene they affect are
called out explicitly above rather than implied by their presence in "Done."
