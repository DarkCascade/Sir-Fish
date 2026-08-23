extends Node
## Tuning — the single source of truth for every balance and timing number.
## No other file in this project may hardcode any of these values (spec 0.1.5, 5).

# --- 5.1 Timing -------------------------------------------------------------
const TRAVEL_SPEED := 4.0                 # world units/sec the parallax scrolls at full speed
const TRAVEL_ACCEL_TIME := 0.6            # ease-in when travel starts
const TRAVEL_DECEL_TIME := 0.9            # ease-out when arriving at an encounter
## [overworld prototype] Unused: enemies run in from off-screen now rather
## than fading in (see BattleDirector._run_enemy_in). Kept because the fade is
## still the right entrance for a future indoor or ambush encounter, where
## there is no off-screen corner to run in from.
const ENEMY_FADE_IN_TIME := 0.35
const ENEMY_DEATH_HOLD := 1.5             # corpse lies still before fading
const ENEMY_DEATH_FADE := 2.0             # then fades out over this long, then queue_free
const BARS_POP_IN_TIME := 0.25
const COOLDOWN_START_FRACTION := 0.5      # every combatant starts half-charged
const COOLDOWN_START_JITTER := 0.10       # +/-10% (spec 21-D2)
const HURT_ANIM_TIME := 0.30
const DEAD_HERO_EXIT_TIME := 1.6          # dead heroes slide off the left edge
const ENCOUNTER_RESOLVE_PAUSE := 0.8      # beat between "cleared" and travel starting
## [overworld prototype] How long a shop encounter holds on the building when
## the UI is hidden and there is no modal to open (RunController._run_shop).
const SHOP_SKIP_HOLD := 1.8
const AOE_STAGGER := 0.06                 # [v2] gap between per-target resolutions of any AoE
const DAMAGE_NUMBER_SPREAD := 46.0        # [v2] px offset per concurrent number (spec 11.4)

# --- 5.3 Ability tuning -----------------------------------------------------
const WARRIOR_DEFEND_REDUCTION := 0.50    # incoming damage x (1 - 0.50)
const WARRIOR_DEFEND_DURATION := 4.0
const RANGER_BOMB_AOE_MULT := 0.75        # bomb arrow hits every enemy for base_damage x 0.75
const PRIEST_HEAL_MULT := 1.0             # heal = priest current damage x 1.0
## [overworld prototype] Off. Spec 9.3's darkening pass existed to sell a bolt
## called down out of the sky - the sky dims, then the bolt lands. The priest's
## primary is an aimed MagicBolt thrown from its hand now, so there is no sky
## strike left for the dimming to belong to, and on a bright open field a
## half-second drop to 55% brightness across the whole frame reads as the game
## glitching rather than as a telegraph. The warning glow on the target, which
## is the half of the telegraph that points AT something, still fires.
const PRIEST_DARKEN_ENABLED := false
const DAMAGE_VARIANCE := 0.15             # every hit rolls damage x randf_range(0.85, 1.15)
const SPECIAL_CAST_FLASH_TIME := 0.15     # [v2] universal special-cast telegraph (spec 9.6)

# --- 5.3b Battlefield geometry ---------------------------------------------
## [overworld prototype] v3.6's BATTLEFIELD_SCALE is gone along with the
## orthographic side-on camera it existed to compensate for: squeezing the
## field and the camera's ortho size by the same factor kept screen positions
## fixed while models grew. The overhead camera is perspective and pinned to
## KEEP_WIDTH, so framing is set by where the camera stands, and there is no
## squeeze left to tune. Composition now lives in 5.3c below.
const MAX_ENEMIES := 3
const PARTY_SIZE := 3                     # priest, ranger, warrior

# --- 5.3c Overworld field [overworld prototype] -----------------------------
## The battle is laid out on the XZ ground plane under an overhead camera, not
## along the single X axis the side-on view used. Every position in the fight
## derives from ONE direction vector: the party runs along RUN_DIR (up and to
## the right on screen), the enemies form up at the far end of it, and the
## field scrolls back along -RUN_DIR to sell the running. Rotate RUN_DIR and
## the entire composition rotates with it - there is no second place to edit.
##
## -Z is "up screen" and +X is "right screen", so a vector that is mostly -Z
## with some +X points at the upper-right corner.
##
## THE SLOPE IS DERIVED FROM THE BATTLE VIEWPORT'S ASPECT, not eyeballed. The
## fight runs corner to corner of the frame, so it has to be exactly as much
## taller-than-wide as the frame is. Writing RUN_DIR as normalized(1, 0, -k):
##
##     k = 1 / ( sin(camera tilt) * (viewport width / viewport height) )
##
## Because a unit along the run axis moves the action 1/L across the screen and
## k/L up-field, and the camera's tilt foreshortens up-field by sin(55) = 0.82.
## Recompute k whenever main_layout's split changes - it is the one number that
## does not survive a re-split:
##
##     1080 x  960   (50/50, current)          k = 1.085
##     1080 x 1920   (console hidden entirely) k = 2.170
##     1080 x  640   (the shipped 33/66 split) k = 0.723
##
## Getting this wrong is not subtle: at k = 2.1 in the 50/50 viewport the fight
## was a third taller than the frame and the back rank hung off the bottom edge.
const RUN_DIR := Vector3(0.67772, 0.0, -0.73532)      # normalized(1, 0, -1.085)

## Where the party's FRONT rank stands - lower-left of frame. Everyone else is
## placed relative to it by PARTY_FORMATION.
const PARTY_ANCHOR := Vector3(-1.6, 0.0, 3.4)

## The party formation, in RUN_DIR's own frame rather than world axes:
##   x = across, in units of PARTY_ROW_SPREAD (+ is the party's right)
##   y = back,   in units of PARTY_ROW_DEPTH  (+ is further from the enemy)
## Indexed by hero slot, which is fixed: 0 priest/mage, 1 ranger, 2 warrior.
##
## Warrior alone in front, mage and ranger flanking behind him. Authoring it as
## a table rather than deriving it from a spacing means a new shape is three
## numbers, not a formula - and because it is expressed in RUN_DIR's frame it
## rotates with the run axis for free.
const PARTY_FORMATION := [
	Vector2(-0.5, 1.0),                   # priest / mage - back rank, left
	Vector2(0.5, 1.0),                    # ranger        - back rank, right
	Vector2(0.0, 0.0),                    # warrior       - front rank, on the axis
]
## The floor both sit at is silhouette overlap - the mage's hat is about 1.2
## units across and the warrior's cape about 1.0, so anything under ~2.0
## between neighbours has them intersecting on screen. Both are pushed well
## past that floor for the low chase-cam angle (BattleCamera now sits behind
## and low, at roughly rotation (-15, -42, 0)): a wide, loose formation is
## what reads as a party crossing open ground from that angle, where the old
## overhead framing could get away with a tighter huddle.
const PARTY_ROW_DEPTH := 2.4               # front rank to back rank
const PARTY_ROW_SPREAD := 4.4              # gap between the two back-rank heroes

## The enemy line forms this far up-run from the party leader, spread across
## RUN_DIR's perpendicular so all three read as a facing rank. Melee closes
## the gap by blinking, so it costs nothing mechanically - it only has to fit
## the camera's frame.
##
## Coupled to BattleCamera's height and fov in battle_world.tscn (currently
## 14.0 / 34 degrees, both brought down from 21.6 / 26 for a lower, closer
## vantage point). Bringing the camera down without also pulling the enemy
## line in would have clipped the back rank - a lower camera at a fixed tilt
## has more foreground perspective, which needs EITHER a wider fov or a
## smaller world extent to fit the same subjects. Re-solve both together -
## project every combatant's world position through the camera transform into
## NDC and check the worst-case |x|/|y| stays under about 0.85 - rather than
## nudging one number and eyeballing the other.
const ENEMY_DISTANCE := 7.0
const ENEMY_SPREAD := 1.7                 # gap between adjacent enemies

## Enemies run in from off-screen past the upper-right corner instead of
## fading in: they spawn this far beyond their slots, down-run, and sprint to
## them (spec 10.1's fade is replaced wholesale by this).
const ENEMY_ENTRY_DISTANCE := 12.0
const ENEMY_ENTRY_TIME := 1.15
const ENEMY_ENTRY_STAGGER := 0.13         # gap between each enemy's departure

# --- 5.3d Melee teleport [overworld prototype] ------------------------------
## Melee attackers do not walk to their target - they blink to it. Ranged and
## magic attackers never teleport; they fire something that flies instead.
const TELEPORT_OUT_TIME := 0.13           # dissolve at the origin
const TELEPORT_IN_TIME := 0.15            # reform at the destination
const TELEPORT_STRIKE_GAP := 1.35         # how far short of the target it lands
const TELEPORT_GHOSTS := 5                # afterimages left along the path
const TELEPORT_GHOST_FADE := 0.28
const TELEPORT_RETURN_DELAY := 0.14       # beat spent at the target after impact

# --- 5.3e Magic bolt [overworld prototype] ----------------------------------
## The priest's primary is an aimed bolt now, not a pillar dropped from the
## sky. The sky-drop version survives only as the slot machine's payout, which
## is a called-down strike and reads correctly as one.
const MAGIC_BOLT_SPEED := 12.0            # world units/sec
const MAGIC_BOLT_ARC := 0.9               # how high above the straight line it bows

# --- 5.4 Economy ------------------------------------------------------------
const STARTING_GOLD := 75                 # [v2] was 50 (spec 5.4 / Q23)
const SHOP_BUY_MARKUP := 1.5              # buy price  = round(value x 1.5)
const SHOP_SELL_RATE := 0.5               # sell price = round(value x 0.5)
const LOOT_ITEMS_PER_CHEST := 2
const SHOP_ITEMS_FOR_SALE := 3

# --- 5.5 Slot machine -------------------------------------------------------
enum Sym { LIGHTNING, GOLD, PLUS, BLANK }

const SLOT_REEL_STOPS := 27

## 27 stops: LIGHTNING 7, GOLD 7, PLUS 7, BLANK 6.
## P(win) = 9849 / 19683 = 0.500381... (spec 16.2). Recompute if you edit this.
const SLOT_STRIP: Array[int] = [
	Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,      Sym.PLUS,      Sym.LIGHTNING,
	Sym.GOLD,      Sym.PLUS,      Sym.BLANK,     Sym.LIGHTNING, Sym.GOLD,
	Sym.PLUS,      Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,      Sym.PLUS,
	Sym.LIGHTNING, Sym.GOLD,      Sym.PLUS,      Sym.BLANK,     Sym.LIGHTNING,
	Sym.GOLD,      Sym.PLUS,      Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,
	Sym.PLUS,      Sym.BLANK,
]

const SLOT_SPIN_DURATION := 1.10          # reel 1 stop time
const SLOT_REEL_STAGGER := 0.28           # reel 2 stops +0.28s, reel 3 stops +0.56s
const SLOT_RESULT_HOLD := 0.85            # pause after reel 3 stops before the next spin
const SLOT_PAY_2_GOLD := 35               # [v2] was 25
const SLOT_PAY_3_GOLD := 90               # [v2] was 50
const SLOT_HEAL_2_FRACTION := 0.25        # lowest-hp hero healed 25% of max
const SLOT_HEAL_3_FRACTION := 0.25        # entire party healed 25% of max
const SLOT_LIGHTNING_2_MULT := 1.0        # damage = avg(last 3 hero strikes) x 1.0
const SLOT_LIGHTNING_3_MULT := 2.0        # x 2.0
const SLOT_LIGHTNING_FALLBACK := 12       # used if fewer than 1 hero strike recorded
## [v2] Attract mode (spec 16.6 / Q17): out of combat the reels drift instead of
## stopping. "Does nothing" means nothing that affects the game - not dead air.
const SLOT_ATTRACT_SPEED := 0.15          # fraction of spin speed while drifting
const SLOT_ATTRACT_DIM := Color(0.78, 0.78, 0.82)   # [v2] was Color(0.55, 0.55, 0.62)

## [overworld prototype] The cabinet read as crowded edge to edge, so the
## whole thing is shrunk around its own centre (slot_machine.gd's
## apply_height sets Control.scale from this), which pads it off from the
## rest of the console. That shrink is a single transform on the SlotMachine
## root, so every child - cabinet, reel windows, glyphs - already gets
## smaller on screen as a side effect; it does NOT, on its own, add any
## padding INSIDE a cell around its own glyph, since a glyph's size is drawn
## as a fixed fraction of its cell (slot_symbol.gd's BOX_FRACTION) and the
## cell shrinks right along with it. Applying this SAME factor again, inside
## _draw(), on top of BOX_FRACTION is what gives each glyph breathing room
## within its own cell rather than filling it corner to corner.
##
## Both places that use this also animate the exact property it scales
## (SlotMachine.scale for a 3-of-a-kind win punch; SlotSymbol.scale for a
## payline win pulse) and both tween back to a literal Vector2.ONE at rest -
## which would silently erase this shrink the first time either fires. Their
## rest values are SLOT_CABINET_SCALE now, not ONE; see the comments at each
## call site before changing either.
const SLOT_CABINET_SCALE := 0.82

# --- 5.7 Upgrades [v2] ------------------------------------------------------
const UPGRADE_MAX_LEVEL := 3
const UPGRADE_COST_GROWTH := 1.9          # cost(n) = round(base x 1.9^(n-1))

const UPGRADE_QUICK_REELS_BASE := 60
const UPGRADE_QUICK_REELS_STEP := 0.86    # spin-cycle multiplier per level (compounding)

const UPGRADE_OVERCHARGE_BASE := 70
const UPGRADE_OVERCHARGE_STEP := 0.25     # +25% lightning damage per level (additive)

const UPGRADE_FAT_PURSE_BASE := 50
const UPGRADE_FAT_PURSE_STEP := 0.40      # +40% gold per level (additive)

# --- 6.1 Palette -------------------------------------------------------------
## [presentation redesign] Bioluminescent night forest. Every value below is a
## rewrite IN PLACE of the old fair-weather-meadow palette - names are
## unchanged so every call site still resolves, only the hues moved. See
## "Sir Fish - Presentation Redesign Spec.md" S2.
const C_SKY := Color("0E2A33")            # canopy gap, teal-black
const C_FAR_HILLS := Color("143A38")      # deepest treeline
const C_MID_TREES := Color("1B4B3A")      # mid canopy
const C_NEAR_TREES := Color("14231F")     # near trunks, nearly black
const C_GROUND := Color("3E6B3A")         # lit moss down the path centre
const C_BRUSH := Color("0F2B22")          # undergrowth
const C_INK := Color("241E14")            # dark ink/outline - stays dark on purpose,
										  # reused as text-on-parchment (S8)
const C_WARRIOR_ARMOR := Color("5878A8")
const C_WARRIOR_ACCENT := Color("C0333F")
const C_RANGER_LEATHER := Color("478A5C")
const C_RANGER_ACCENT := Color("9C6B33")
const C_PRIEST_CLOTH := Color("6E5AA8")   # was cream F5F0E6 - now the concept's violet robe
const C_PRIEST_ACCENT := Color("C4B5FD")
const C_ORC_SKIN := Color("6FA83E")
const C_ORC_IRON := Color("8C94A3")
const C_SHADOW_BODY := Color("14121A")
const C_SHADOW_EYES := Color("FF2D2D")
const C_GOLD := Color("C9A227")           # aged gold, was the brighter F2C230
const C_DANGER := Color("E4484F")
const C_HEAL := Color("7CC142")           # green, matches the PLUS slot symbol
const C_LIGHTNING := Color("A855F7")      # was blue - now the arcane purple
const C_DEFEND := Color("D9A825")         # was blue - now the shield gold
const C_CONSOLE_BG := Color("0B1A18")     # behind everything, near-black teal
const C_CONSOLE_PANEL := Color("123A32")  # panel fill
const C_TEXT := Color("F2E9D0")           # cream, on dark
const C_TEXT_DIM := Color("9CAFA4")       # muted sage, on dark
const C_WOOD := Color("7A4E28")           # slightly darkened for the night mood
const C_WOOD_DARK := Color("5A3419")
const C_PANEL_BORDER := Color("2E5A4E")   # inner border, one step off the panel fill
const C_FIRE := Color("FF7A1A")           # [v2] fire-modifier damage numbers, unchanged
const C_ICE := Color("5BC8F5")            # [v2] ice-modifier damage numbers, unchanged
const C_FISH_SCALE := Color("4A9BE8")     # [v2] Sir Fish body
const C_FISH_FIN := Color("3B6FD4")       # [v2] Sir Fish fins
const C_ROCK := Color("2A3A44")           # [v3] layer-4 scatter rocks - now blue-slate

# --- 6.1b Arcane accents [presentation redesign] -----------------------------
## The purple every crystal, rune and slot bolt shares, so the world and the
## console read as the same magic on purpose.
const C_ARCANE := Color("8B5CF6")
const C_ARCANE_BRIGHT := Color("C4B5FD")  # emissive core / glow peak
const C_ARCANE_DEEP := Color("4C1D95")    # shadowed crystal faces
const C_PORTAL := Color("7FE3D8")         # the archway light / any "destination" cue

# --- 6.1c Console chrome [presentation redesign] -----------------------------
const C_CONSOLE_STONE := Color("1E4038")  # raised frame face (ornate_frame.gd)
const C_CONSOLE_INSET := Color("081412")  # recessed wells (reel windows, price plates)
const C_GOLD_BRIGHT := Color("E8C55A")    # top bevel highlight / payline glow
const C_GOLD_DARK := Color("8A6E1C")      # bottom bevel shadow
const C_VINE := Color("2F6B3E")           # [Pass B] frame overgrowth, unused until S5.4
const C_FLOWER := Color("A78BFA")         # [Pass B] frame blooms, unused until S5.4

# --- 6.1d Parchment [presentation redesign] -----------------------------------
## Upgrade cards only (S8) - every other panel is stone, not parchment.
const C_PARCHMENT := Color("C3BDA8")
const C_PARCHMENT_SHADE := Color("A49E8A")  # lower half of the card's gradient
const C_TEXT_GOLD := Color("E8C55A")        # headings and numerals on dark stone

# --- storm mood (M9) ---------------------------------------------------------
## The palette above is the fair-weather art direction and stays as authored.
## The storm is a TRANSFORM of it, not a second copy: `storm_tint()` darkens
## and pulls a colour toward slate, so every layer keeps its relationship to
## its neighbours and there is still one source of truth per hue.
##
## Only the UNSHADED surfaces are tinted in code (the generated parallax layers
## run `parallax_layer.gdshader`, which ignores lights entirely, so nothing
## else can darken them). Everything lit - characters, the modelled ground and
## brush - goes dark on its own once the key and fill lights drop, which is
## where the rest of the gloom comes from.
const STORM_SKY := Color("16203A")        # the lowered background colour
const STORM_SLATE := Color("5A6E96")      # what every hue is pulled toward
const STORM_DARKEN := 0.50
const STORM_TINT_MIX := 0.35

## How bright the sky goes at the peak of a lightning flash. Not white: a
## blown-out white frame reads as a bug, a cold blue-white reads as weather.
const STORM_SKY_FLASH := Color("6E8CC4")

# --- lightning (M9) ----------------------------------------------------------
const LIGHTNING_INTERVAL_MIN := 4.5
const LIGHTNING_INTERVAL_MAX := 11.0
## Chance a strike is a double - the second bolt lands 0.12-0.30 s later, in a
## different part of the sky. Real storms rarely flash exactly once.
const LIGHTNING_DOUBLE_CHANCE := 0.35
const LIGHTNING_LIGHT_ENERGY := 3.4       # peak of the DirectionalLight3D pulse
const LIGHTNING_SCREEN_ALPHA := 0.42      # peak of the full-viewport flash
## Thunder arrives after the light does. The delay is what sells distance, and
## the shake is the only "sound" this project has - there are no audio assets.
const LIGHTNING_THUNDER_DELAY_MIN := 0.35
const LIGHTNING_THUNDER_DELAY_MAX := 0.85
const LIGHTNING_SHAKE := 0.055
const LIGHTNING_SHAKE_TIME := 0.55

# --- 5.8 Parallax [v3] -------------------------------------------------------
const PARALLAX_TILE_COPIES := 3
const PARALLAX_TILE_WIDTH_PROC := 36.0    # layers 1-3, generated (spec 7.5)
const PARALLAX_TILE_WIDTH_MODEL := 12.0   # layers 4-5, modelled (spec 23.4)
const PARALLAX_SEAM_EPSILON := 0.0001     # test_parallax_seam's tolerance

# --- 5.8b Overworld field scatter [overworld prototype] ---------------------
## The five parallax layers are gone: an overhead camera sees real ground, so
## the field is an actual scattered plane. Props live on a rectangle in
## RUN_DIR's frame (ACROSS x ALONG) and wrap toroidally as it scrolls, which
## is what makes an "open field" out of a finite number of meshes.
##
## ALONG is generous because the camera looks down the run axis and the far
## end of the field is on screen for a long time; ACROSS only has to cover the
## frame's width plus a margin.
## ACROSS has to cover the frame's full width at the FAR edge of the view,
## where the camera sees widest - and the field rectangle is rotated ~32
## degrees against the screen, so its corners have to reach further still.
const FIELD_ACROSS := 56.0                # extent perpendicular to RUN_DIR
const FIELD_ALONG := 46.0                 # extent along RUN_DIR
const FIELD_SCATTER_SEED := 20260822      # fixed: the field is identical every run

## Counts are per whole field, not per square unit - the field's size is
## fixed, so these ARE the density.
const FIELD_BUSHES := 90
const FIELD_ROCKS := 70
const FIELD_TUFTS := 160
const FIELD_GRASS := 200
const FIELD_TREES := 52
## [presentation redesign S10.1] Sparser than the rocks - crystals are meant
## to read as landmarks the party runs past, not as ground texture.
const FIELD_CRYSTALS := 90
const CRYSTAL_SCALE_MIN := 0.75
const CRYSTAL_SCALE_MAX := 1.6
## Emission energy on the Godot-side material_override (not baked into the
## .glb - see overworld_field.gd's _crystal_material()), tuned against
## glow_hdr_threshold = 0.95 (S9.4) so the clusters actually bloom.
const CRYSTAL_EMISSION_ENERGY := 2.2

## Nothing is scattered within this distance of the run corridor's centre
## line, so neither the party formation nor the enemy rank spawns in a bush.
## The bald stripe this leaves reads as the path the party is running along.
##
## The widest thing in the corridor sets the floor: the enemy rank spreads
## ENEMY_SPREAD (1.7) either side of the lane, plus about half a model on top.
const FIELD_CLEAR_RADIUS := 2.4

## The tree is authored at twice the humanoid reference height (the warrior's
## knight.glb stands 2.3 units at model_scale 1.0), so 4.6. Trees also take a
## per-instance scale jitter around that.
const TREE_HEIGHT := 4.6
const TREE_SCALE_JITTER := 0.22           # +/- fraction on each planted tree

## Extra clearance a TREE gets on top of FIELD_CLEAR_RADIUS, because a canopy
## is far wider than the trunk that has to miss the fighters - about 3.5 units
## across, so 1.75 of overhang eats most of a small extra before any bare
## ground is left over.
##
## Widened well past that floor for the low chase-cam angle (BattleCamera at
## roughly position (-14, 9, 17), rotation (-15, -42, 0)): looking nearly
## straight up the run corridor, the treeline reads as a wall pressing in from
## both sides unless the clearing is generously wide. 2.4 + 3.0 = 5.4 total,
## which nets to roughly a 3.65-unit bare half-width once the canopy overhang
## is subtracted - comfortably outside PARTY_ROW_SPREAD's widest hero (2.2).
##
## The old overhead framing (BattleCamera pitched steeply down) could read a
## much narrower gap, because it looked down the LENGTH of the corridor for
## only a short on-screen distance rather than staring straight into the
## treeline - raise this again with that in mind if the camera goes back to
## something closer to top-down.
const TREE_CLEAR_EXTRA := 3.0

## [overworld prototype] Depth fog, applied at runtime by battle_world.gd
## rather than left as the .tscn's inline Environment sub-resource default -
## same pattern main_layout.gd already uses for cam.keep_aspect, and it means
## these two numbers live in the one file every other tuned constant does.
##
## Pulled in hard for the low chase-cam angle (BattleCamera at roughly
## position (-14, 9, 17), rotation (-15, -42, 0)). The old values (38 / 96)
## were sized for a steeply-overhead camera, where "depth" mostly meant
## distance straight down; looking nearly along the ground instead, the
## party itself sits at a view-depth of about 20, so fog has to start past
## that (never fog the party) and reach full well short of the far clip, or
## the horizon stays hard-edged no matter how much background art sits out
## there. FIELD_BACKDROP_MIN/MAX_RADIUS below are deliberately chosen to fall
## inside this range, so the far treeline actually fades rather than either
## standing out crisp or being fully invisible.
const FOG_DEPTH_BEGIN := 11.0        # [presentation redesign] pulled in for the night mood, was 16.0
const FOG_DEPTH_END := 42.0          # was 55.0

## A second, non-scrolling ring of trees well outside the play area, sparser
## and colour-shifted toward the fog - cheap atmospheric perspective for the
## gap between the last foreground tree and the sky that the low chase-cam
## angle opened up (a steep overhead view never showed enough horizon for
## this to matter). Placed in a full radial ring around the origin, not just
## ahead along RUN_DIR, so it still reads correctly if the camera gets
## rotated again.
##
## Deliberately NOT part of the scrolling scatter (OverworldField._groups):
## the camera itself never moves in this scene (the field slides under it
## instead - see OverworldField's own header), so a backdrop this far out
## has no perceptible parallax to sell and tiling logic would be pure
## overhead for zero visible benefit.
const FIELD_TREES_BACKDROP := 70
const FIELD_BACKDROP_MIN_RADIUS := 40.0    # just past the near scatter's own reach
const FIELD_BACKDROP_MAX_RADIUS := 62.0    # inside FOG_DEPTH_END, so it still fades in rather than never being visible at all
## How far toward the fog colour a backdrop tree's own material is pre-tinted,
## on top of whatever real-time depth fog it also picks up at render time -
## real fog alone (which reads current depth, not placement) still leaves a
## backdrop tree at the NEAR edge of the ring looking as saturated as a
## foreground one; this pre-tint is what marks the whole ring as "far" even
## for the instances fog has barely touched yet.
const FIELD_BACKDROP_TINT := 0.55
## Matches the sky/fog colours already authored in battle_world.tscn's
## ProceduralSkyMaterial.sky_horizon_color and Environment.fog_light_color.
## Kept as its own constant instead of read live off the WorldEnvironment
## sibling node, so OverworldField never has to reach outside itself to
## build a backdrop material - if the sky colour is ever re-authored, update
## this to match by eye at the same time.
const C_HORIZON_HAZE := Color(0.101961, 0.290196, 0.290196)  # [presentation redesign] matches the new sky_horizon_color / fog_light_color

# --- 5.9 Health chunk [v3.5 D6] ---------------------------------------------
const CHUNK_FLING_X := 45.0               # was an inline +/-90 in floating_health_chunk.gd
const CHUNK_FLING_Y_MIN := 25.0           # was 50
const CHUNK_FLING_Y_MAX := 65.0           # was 130
const CHUNK_SPIN := 0.45                  # was +/-0.9 rad
const CHUNK_FLIGHT_TIME := 0.70           # unchanged, moved here so no number stays inline

# --- 5.10 Status icons [v3.5 F2] --------------------------------------------
const ICON_DEFEND_RADIUS := 36.0
const ICON_DEFEND_FILL_ALPHA := 0.28
const ICON_DEFEND_GLYPH_BOX := 46.0
const ICON_HEAL_RADIUS := 42.0
const ICON_HEAL_FILL_ALPHA := 0.22
const ICON_HEAL_GLYPH_BOX := 50.0
const ICON_RING_WIDTH := 5.0

# --- 5.1b Enemy death, rushed [v3.5 D4] --------------------------------------
const ENEMY_DEATH_HOLD_RUSH := 0.30       # corpse hold when the fight is already won
const ENEMY_DEATH_FADE_RUSH := 0.45       # 0.30 + 0.45 = 0.75, inside ENCOUNTER_RESOLVE_PAUSE

# --- 17.6 Rarity colours ----------------------------------------------------
const RARITY_COLORS := [
	Color("B8B2C4"),  # Common
	Color("4CC38A"),  # Uncommon
	Color("4A9BE8"),  # Magic
	Color("F2C230"),  # Rare
]

# --- 2.1 Screen budget (logical viewport pixels) ---------------------------
const VIEWPORT_W := 1080
const VIEWPORT_H := 1920
const BATTLE_H := 640
const DIVIDER_H := 8
const CONSOLE_Y := 648
const STATUS_PANEL_H := 300
const SLOT_MACHINE_H := 600
const PARTY_BUTTON_H := 160
const UPGRADE_TRAY_H := 212

## The yaw that points a combatant along `dir` on the ground plane.
##
## A combatant's forward is +X in its own local space, which is why this is
## atan2(-z, x). The three heroes get there via a -90 degree Y rotation on
## their Model node (see warrior.tscn); the orcs are authored facing +X in
## Blender. That convention is also why the side-on view could turn an enemy
## around with nothing but `rotation.y = PI`.
##
## It lives here rather than on BattleWorld because Combatant needs it during
## setup(), when reaching through `director.world` would couple a combatant's
## own facing to the director being wired up first.
func yaw_along(dir: Vector3) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.z, flat.x)

## Fair-weather palette entry -> its storm equivalent (see the block above).
func storm_tint(color: Color) -> Color:
	var dark := color.darkened(STORM_DARKEN)
	return dark.lerp(STORM_SLATE.darkened(STORM_DARKEN), STORM_TINT_MIX)
