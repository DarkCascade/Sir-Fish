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
## The 1:2.1 ratio is much steeper than a true 45-degree diagonal, and it is
## picked rather than eyeballed. The viewport is portrait (1080 x 1920), so the
## frame is 1.78x taller than it is wide, and the fight has to be that much
## taller than it is wide to fill it. One unit along RUN_DIR moves the action
## 0.43 to the right and 0.90 up-field, and the camera's 55-degree tilt
## foreshortens up-field by cos(55) = 0.82 - giving a screen slope of
## 0.90 x 0.82 / 0.43 = 1.72, near enough the frame's own 1.78. At the 1:1.6
## first pass the fight came out squarer than the frame and wasted the top
## third of the screen.
const RUN_DIR := Vector3(0.42992, 0.0, -0.90283)      # normalized(1, 0, -2.1)

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
## Both are set by silhouette overlap, not by taste: the mage's hat is about
## 1.2 units across and the warrior's cape about 1.0, so anything under ~2.0
## between neighbours has them intersecting on screen at this camera angle.
const PARTY_ROW_DEPTH := 1.8              # front rank to back rank
const PARTY_ROW_SPREAD := 2.0             # gap between the two back-rank heroes

## The enemy line forms this far up-run from the party leader, spread across
## RUN_DIR's perpendicular so all three read as a facing rank. Wide enough to
## put the two sides in opposite corners of a tall frame; melee closes it by
## blinking, so the gap costs nothing mechanically.
const ENEMY_DISTANCE := 10.0
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

# --- 5.7 Upgrades [v2] ------------------------------------------------------
const UPGRADE_MAX_LEVEL := 3
const UPGRADE_COST_GROWTH := 1.9          # cost(n) = round(base x 1.9^(n-1))

const UPGRADE_QUICK_REELS_BASE := 60
const UPGRADE_QUICK_REELS_STEP := 0.86    # spin-cycle multiplier per level (compounding)

const UPGRADE_OVERCHARGE_BASE := 70
const UPGRADE_OVERCHARGE_STEP := 0.25     # +25% lightning damage per level (additive)

const UPGRADE_FAT_PURSE_BASE := 50
const UPGRADE_FAT_PURSE_STEP := 0.40      # +40% gold per level (additive)

# --- 6.1 Palette ------------------------------------------------------------
const C_SKY := Color("7EC8E3")
const C_FAR_HILLS := Color("4A9E6F")
const C_MID_TREES := Color("2E8B57")
const C_NEAR_TREES := Color("1E6B45")
const C_GROUND := Color("8FBF4F")
const C_BRUSH := Color("14532D")
const C_INK := Color("0F0E14")
const C_WARRIOR_ARMOR := Color("4A6FA5")
const C_WARRIOR_ACCENT := Color("D9333F")
const C_RANGER_LEATHER := Color("3E7A4E")
const C_RANGER_ACCENT := Color("8B5A2B")
const C_PRIEST_CLOTH := Color("F5F0E6")
const C_PRIEST_ACCENT := Color("3B6FD4")
const C_ORC_SKIN := Color("6FA83E")
const C_ORC_IRON := Color("8C94A3")
const C_SHADOW_BODY := Color("14121A")
const C_SHADOW_EYES := Color("FF2D2D")
const C_GOLD := Color("F2C230")
const C_DANGER := Color("E03131")
const C_HEAL := Color("2FBF4F")
const C_LIGHTNING := Color("3B82F6")
const C_DEFEND := Color("3B6FD4")
const C_CONSOLE_BG := Color("231F2E")
const C_CONSOLE_PANEL := Color("332C42")
const C_TEXT := Color("FFF6E0")
const C_TEXT_DIM := Color("9B93AE")
const C_WOOD := Color("8B5A2B")
const C_WOOD_DARK := Color("6B4423")
const C_PANEL_BORDER := Color("4A4260")
const C_FIRE := Color("FF7A1A")           # [v2] fire-modifier damage numbers
const C_ICE := Color("5BC8F5")            # [v2] ice-modifier damage numbers
const C_FISH_SCALE := Color("4A9BE8")     # [v2] Sir Fish body
const C_FISH_FIN := Color("3B6FD4")       # [v2] Sir Fish fins
const C_ROCK := Color("7D8A6B")           # [v3] layer-4 scatter rocks (spec 23.4)

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
const FIELD_TREES := 36

## Nothing is scattered within this distance of the run corridor's centre
## line, so neither the party formation nor the enemy rank spawns in a bush.
## The bald stripe this leaves reads as the path the party is running along.
const FIELD_CLEAR_RADIUS := 2.2

## The tree is authored at twice the humanoid reference height (the warrior's
## knight.glb stands 2.3 units at model_scale 1.0), so 4.6. Trees also take a
## per-instance scale jitter around that.
const TREE_HEIGHT := 4.6
const TREE_SCALE_JITTER := 0.22           # +/- fraction on each planted tree

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
