extends Node
## Tuning — the single source of truth for every balance and timing number.
## No other file in this project may hardcode any of these values (spec 0.1.5, 5).

# --- 5.1 Timing -------------------------------------------------------------
const TRAVEL_SPEED := 4.0                 # world units/sec the parallax scrolls at full speed
const TRAVEL_ACCEL_TIME := 0.6            # ease-in when travel starts
const TRAVEL_DECEL_TIME := 0.9            # ease-out when arriving at an encounter
const ENEMY_FADE_IN_TIME := 0.35
const ENEMY_DEATH_HOLD := 1.5             # corpse lies still before fading
const ENEMY_DEATH_FADE := 2.0             # then fades out over this long, then queue_free
const BARS_POP_IN_TIME := 0.25
const COOLDOWN_START_FRACTION := 0.5      # every combatant starts half-charged
const COOLDOWN_START_JITTER := 0.10       # +/-10% (spec 21-D2)
const HURT_ANIM_TIME := 0.30
const DEAD_HERO_EXIT_TIME := 1.6          # dead heroes slide off the left edge
const ENCOUNTER_RESOLVE_PAUSE := 0.8      # beat between "cleared" and travel starting
const AOE_STAGGER := 0.06                 # [v2] gap between per-target resolutions of any AoE
const DAMAGE_NUMBER_SPREAD := 46.0        # [v2] px offset per concurrent number (spec 11.4)

# --- 5.3 Ability tuning -----------------------------------------------------
const WARRIOR_DEFEND_REDUCTION := 0.50    # incoming damage x (1 - 0.50)
const WARRIOR_DEFEND_DURATION := 4.0
const RANGER_BOMB_AOE_MULT := 0.75        # bomb arrow hits every enemy for base_damage x 0.75
const PRIEST_HEAL_MULT := 1.0             # heal = priest current damage x 1.0
const PRIEST_DARKEN_ENABLED := true       # spec 9.3 - battlefield darkens under the bolt
const DAMAGE_VARIANCE := 0.15             # every hit rolls damage x randf_range(0.85, 1.15)
const SPECIAL_CAST_FLASH_TIME := 0.15     # [v2] universal special-cast telegraph (spec 9.6)

# --- 5.3b Battlefield geometry ---------------------------------------------
## [v3.6] How far apart the battlefield is spread, as a fraction of the authored
## v3.5 spacing. main_layout.gd scales the camera's world width by exactly the
## same factor, so every combatant, prop and parallax layer keeps its screen
## POSITION - what changes is that the character models, whose size is fixed in
## world units, cover more of those pixels. 1.0 is the authored size; 0.72 was
## the "bigger characters" experiment, and needed ENEMY_X_MAX pulled in to 3.8 to
## stop the widest enemy hanging off the right edge.
const BATTLEFIELD_SCALE := 1.0

const HERO_SLOT_X := [-4.0, -2.5, -1.0]   # [v3.5 F1/F3] priest, ranger, warrior (left -> right)
const ENEMY_X_MIN := 1.2                  # [v3.5 F3] was 1.6
const ENEMY_X_MAX := 4.0                  # [v3.5 F3] was 4.8
const MAX_ENEMIES := 3

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

## Fair-weather palette entry -> its storm equivalent (see the block above).
func storm_tint(color: Color) -> Color:
	var dark := color.darkened(STORM_DARKEN)
	return dark.lerp(STORM_SLATE.darkened(STORM_DARKEN), STORM_TINT_MIX)
