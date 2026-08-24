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
## [ui-project-longshot] Halved from 2.4. On the concept board the three heroes
## read as a LINE abreast with the knight only slightly ahead - at 2.4, under
## the new camera's wider field, the front-rank warrior sat visibly deeper than
## his flankers and grouped with the enemies instead of with his own party.
const PARTY_ROW_DEPTH := 1.2               # front rank to back rank
const PARTY_ROW_SPREAD := 4.4              # gap between the two back-rank heroes

## The enemy line forms this far up-run from the party leader, spread across
## RUN_DIR's perpendicular so all three read as a facing rank. Melee closes
## the gap by blinking, so it costs nothing mechanically - it only has to fit
## the camera's frame.
##
## Coupled to BattleCamera's height and fov in battle_world.tscn.
##
## [ui-project-longshot] Both moved again, and this time they were SOLVED from
## the concept board rather than nudged. Measuring off the board: the horizon
## sits ~10% down its world panel and the party's feet ~93% down, which fixes
## the angle between them; the party stands ~31% of the panel tall, which fixes
## its distance. Those two constraints give a camera 6.0 units up and ~15.0
## horizontal units back from PARTY_ANCHOR, at a 30-degree VERTICAL field -
## which at the shipped 1080 x 764 viewport (KEEP_WIDTH) is fov 41.5.
##
## 15.0, not the 12.9 the board's own measurement gives directly, and the
## difference is PARTY_ROW_DEPTH: the anchor is the FRONT rank, and the two
## back-rank heroes stand 2.4 units NEARER the camera than it does. Solving for
## the anchor puts their feet below the bottom of the frame - which is exactly
## the failure the first attempt at this shipped. Solve for the NEAREST hero.
##
## The other trap, if any of this is re-solved: the camera was previously HIGHER
## (9.0) and looking down harder, and lowering it is what let the archway stay
## on screen. A 24-degree vertical field cannot hold both the party at the
## bottom and something at horizon level near the top - raise the camera again
## and the arch leaves the frame before the party is comfortably in it.
## Re-solve all three together - project every combatant's world position
## through the camera transform into NDC and check the worst-case |x|/|y|
## stays under about 0.85 - rather than nudging one number and eyeballing the
## rest.
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

# --- enemy drops --------------------------------------------------------------
## How strongly a class that is behind on drops is favoured by the next roll:
##   weight = 1 + DROP_CATCHUP * (leader_count - this_count)
## 0.0 makes drops uniform across classes and coverage a pure coin flip; higher
## converges coverage faster at the cost of feeling scripted. 2.5 means a class
## two drops behind is 6x as likely as the leader. Raised from 1.5 (spec §10 D9):
## at 1.5, simulated coverage landed at 92.2% against the required 95%.
const DROP_CATCHUP := 2.5

## A boss drop skips the weighted roll and goes to the hungriest class outright
## (§4.2). This is what turns §10's coverage gate from "usually" into "almost
## always". Set false to make bosses roll like anything else.
const DROP_BOSS_TARGETS_HUNGRIEST := true

## Seconds between drop labels when several land at once. Matches the chest
## cadence in _run_loot() so a drop reads as the same event as chest loot.
const DROP_LABEL_STAGGER := 0.25
## Height above the recorded corpse position that a drop label pops at.
const DROP_LABEL_LIFT := 1.2
## Smaller than spawn_world_label()'s 40 default: a drop label carries the item
## name AND the class, so it is roughly twice as wide as a chest label.
const DROP_LABEL_FONT_SIZE := 34

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

## [overworld prototype] Originally 0.82: the cabinet read as crowded edge to
## edge, so the whole thing was shrunk around its own centre (slot_machine.gd's
## apply_height sets Control.scale from this), padding it off from the rest of
## the console. [UI pass] Pushed back to 1.0 - "blow the slot machine up to
## fill its available space" - trading that breathing room for a bigger
## cabinet. That shrink is a single transform on the SlotMachine root, so
## every child - cabinet, reel windows, glyphs - already gets smaller on
## screen as a side effect; it does NOT, on its own, add any padding INSIDE a
## cell around its own glyph, since a glyph's size is drawn as a fixed
## fraction of its cell (slot_symbol.gd's box_fraction) and the cell shrinks
## right along with it. Applying this SAME factor again, inside _draw(), on
## top of box_fraction is what gives each glyph breathing room within its own
## cell rather than filling it corner to corner.
##
## Both places that use this also animate the exact property it scales
## (SlotMachine.scale for a 3-of-a-kind win punch; SlotSymbol.scale for a
## payline win pulse) and both tween back to a literal Vector2.ONE at rest -
## which would silently erase this shrink the first time either fires. Their
## rest values are SLOT_CABINET_SCALE now, not ONE; see the comments at each
## call site before changing either.
const SLOT_CABINET_SCALE := 1.0

# --- 5.7 Upgrades [v2] ------------------------------------------------------
## [ui-project-longshot] Raised from 3 to 4 because the concept board's cards
## carry FOUR level pips, and the pip row is drawn from this constant rather
## than hardcoded (upgrade_button.gd's _draw_pips), so the art and the rule are
## the same number by construction.
##
## This is the one change in the art pass that moves BALANCE and not just
## pixels, and it is worth stating plainly: a fourth level costs
## base x 1.9^3 = 6.9x the first, and every upgrade's ceiling effect rises one
## step (Quick Reels to 0.86^4, Overcharge to +100%, Fat Purse to +160%).
## Drop it back to 3 and the cards draw three pips again with nothing else to
## undo.
const UPGRADE_MAX_LEVEL := 4
const UPGRADE_COST_GROWTH := 1.9          # cost(n) = round(base x 1.9^(n-1))

const UPGRADE_QUICK_REELS_BASE := 60
const UPGRADE_QUICK_REELS_STEP := 0.86    # spin-cycle multiplier per level (compounding)

const UPGRADE_OVERCHARGE_BASE := 70
const UPGRADE_OVERCHARGE_STEP := 0.25     # +25% lightning damage per level (additive)

const UPGRADE_FAT_PURSE_BASE := 50
const UPGRADE_FAT_PURSE_STEP := 0.40      # +40% gold per level (additive)

# --- 6.1 Palette -------------------------------------------------------------
## [ui-project-longshot] Bioluminescent night forest, retargeted to the new art
## director's concept board. The previous pass was teal-GREEN lit by violet;
## the concept is teal-BLUE lit by cyan, with green surviving only as the moss
## underfoot and the heal glyph. Every value below is a rewrite IN PLACE -
## names are unchanged so every call site still resolves, only the hues moved.
##
## The single organising rule, and the reason the concept reads as one image:
## COOL BLUE IS THE LIGHT, GREEN IS THE GROUND, GOLD IS THE UI. Nothing that
## belongs to the world may be gold, and nothing that belongs to the frame may
## be cyan, or the two halves of the screen stop separating.
const C_SKY := Color("0B2C4E")            # canopy gap, deep night blue
const C_FAR_HILLS := Color("0E3A52")      # deepest treeline, blue-drowned
const C_MID_TREES := Color("14584E")      # mid canopy, teal
const C_NEAR_TREES := Color("0A1C24")     # near trunks, nearly black blue
const C_GROUND := Color("2F6B44")         # lit moss down the path centre
const C_BRUSH := Color("0C2A2C")          # undergrowth
const C_INK := Color("241E14")            # dark ink/outline - stays dark on purpose,
										  # reused as text-on-parchment (S8)
const C_WARRIOR_ARMOR := Color("5878A8")
const C_WARRIOR_ACCENT := Color("C0333F")
const C_RANGER_LEATHER := Color("478A5C")
const C_RANGER_ACCENT := Color("9C6B33")
## [ui-project-longshot] The mage's robe. mage_mage_texture.png's magenta
## swatch was hue-shifted to THIS hue (255 degrees), so the model and every
## VFX that reads this constant finally agree - before, the constant said
## violet while the texture drew a magenta that fought the whole blue palette.
const C_PRIEST_CLOTH := Color("6E5AA8")
const C_PRIEST_ACCENT := Color("C4B5FD")
const C_ORC_SKIN := Color("6FA83E")
const C_ORC_IRON := Color("8C94A3")
const C_SHADOW_BODY := Color("14121A")
const C_SHADOW_EYES := Color("FF2D2D")
const C_GOLD := Color("D4A843")           # the frame's trim gold, one step brighter
const C_DANGER := Color("E4484F")
const C_HEAL := Color("55C94A")           # green, matches the PLUS slot symbol
## [ui-project-longshot] Back to blue. The concept's bolt glyph and its HP-bar
## sibling are an electric blue-white, not violet - violet is demoted to the
## frame's flowers (C_FLOWER) and a few background spikes, which is the only
## place the concept still uses it.
const C_LIGHTNING := Color("4C86F0")
const C_DEFEND := Color("D9A825")         # was blue - now the shield gold
const C_CONSOLE_BG := Color("07171B")     # behind everything, near-black blue
const C_CONSOLE_PANEL := Color("0D2A2A")  # panel fill, the dark glass of a reel well
const C_TEXT := Color("F5F1E4")           # near-white, on dark
const C_TEXT_DIM := Color("9CB0AC")       # muted sage, on dark
const C_WOOD := Color("7A4E28")           # slightly darkened for the night mood
const C_WOOD_DARK := Color("5A3419")
const C_PANEL_BORDER := Color("2E5A4E")   # inner border, one step off the panel fill
const C_FIRE := Color("FF7A1A")           # [v2] fire-modifier damage numbers, unchanged
const C_ICE := Color("5BC8F5")            # [v2] ice-modifier damage numbers, unchanged
const C_FISH_SCALE := Color("4A9BE8")     # [v2] Sir Fish body
const C_FISH_FIN := Color("3B6FD4")       # [v2] Sir Fish fins
const C_ROCK := Color("2A3A44")           # [v3] layer-4 scatter rocks - now blue-slate

# --- 6.1b Arcane accents [ui-project-longshot] -------------------------------
## The blue every crystal, rune and slot bolt shares, so the world and the
## console read as the same magic on purpose. Retargeted from violet: in the
## concept the crystals lighting the forest are unmistakably SAPPHIRE, and the
## light they throw is what tints the whole frame.
const C_ARCANE := Color("3FA9E8")         # crystal body / bolt glyph
const C_ARCANE_BRIGHT := Color("BFEEFF")  # emissive core / glow peak, near-white cyan
const C_ARCANE_DEEP := Color("14417F")    # shadowed crystal faces
const C_PORTAL := Color("9FF2FF")         # the archway light / any "destination" cue

## The violet that used to be the arcane hue, kept as a SECONDARY only: the
## slim background spikes and the frame's blooms. It must never out-bloom
## C_ARCANE or the concept's blue-dominant read collapses.
const C_ARCANE_VIOLET := Color("8B5CF6")

# --- 6.1c Console chrome [ui-project-longshot] -------------------------------
## The concept's frame is CARVED MOSSY STONE with gold trim, not the flat
## green panel this was. Stone reads warm-grey-green against the cold world
## behind it, which is most of what makes the console sit in front rather than
## blend into the forest.
const C_CONSOLE_STONE := Color("3A4A3C")     # raised frame face (ornate_frame.gd)
const C_CONSOLE_STONE_LIT := Color("5E7057")  # top-lit carved edge
const C_CONSOLE_STONE_DARK := Color("1E2A22") # underside of a carved edge
## Recessed wells (reel windows, price plates). Dark GREEN-black, not blue-
## black: on the board the glass behind the reels still carries the forest's
## green, and a neutral near-black well reads as a hole punched in the cabinet.
const C_CONSOLE_INSET := Color("0B1E1C")
const C_GOLD_BRIGHT := Color("F5DFA0")       # top bevel highlight / payline glow
const C_GOLD_DARK := Color("7A5A18")         # bottom bevel shadow
const C_VINE := Color("3D7A45")              # frame overgrowth
const C_VINE_DARK := Color("1F4526")         # its shadowed side
const C_FLOWER := Color("A78BFA")            # frame blooms, the violet's home
const C_GEM := Color("4A6FD4")               # the blue diamond inlays at frame joints
const C_GEM_BRIGHT := Color("9FB8FF")        # their lit facet

# --- 6.1d Parchment [presentation redesign] -----------------------------------
## Upgrade cards only (S8) - every other panel is stone, not parchment.
## Pulled slightly cooler and lighter to match the concept's pale carved-stone
## cards, which read as chiselled tablets rather than paper.
## Cooler and greyer than a true parchment: on the board these cards are pale
## carved STONE, and a warm cream card against a cold blue console reads as
## paper pinned to the cabinet rather than as part of it.
const C_PARCHMENT := Color("C7C4B5")
const C_PARCHMENT_SHADE := Color("A4A294")  # lower half of the card's gradient
const C_TEXT_GOLD := Color("F0D588")        # headings and numerals on dark stone

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
##
## [ui-project-longshot] Roughly doubled across the board. The concept's forest
## is CROWDED - there is no bare ground anywhere outside the path, and the
## treeline is a solid mass rather than a scattering of individuals. The old
## counts left the frame reading as an empty lawn with props on it, which is
## the single largest difference between the old render and the board.
const FIELD_BUSHES := 220
const FIELD_ROCKS := 130
const FIELD_TUFTS := 340
const FIELD_GRASS := 520
const FIELD_TREES := 104
## [ui-project-longshot] No longer "sparser than the rocks". In the concept
## crystals are the light source of the whole scene and they are everywhere -
## a bed of small ones underfoot with a few large landmarks standing out of it.
## That spread is what CRYSTAL_SCALE_MIN/MAX's much wider range buys.
const FIELD_CRYSTALS := 170
## The gem meshes in env_crystal.glb are already 1-2 units across on their
## own, so this multiplies an already-sizeable cluster - a max much past 1.5
## puts crystals taller than the 2.3-unit knight all over the field, and the
## party stops being the biggest thing in its own frame.
const CRYSTAL_SCALE_MIN := 0.45
const CRYSTAL_SCALE_MAX := 1.5
## Strength of the fresnel rim on a crystal facet - see _crystal_material().
const CRYSTAL_RIM := 0.75
## Emission energy on the Godot-side material_override (not baked into the
## .glb - see overworld_field.gd's _crystal_material()), tuned against
## glow_hdr_threshold so the clusters bloom at their tips WITHOUT clipping to
## white. A crystal that blows out stops being a blue gem and becomes a hole
## in the frame - the concept's crystals hold their hue all the way into the
## highlight, which means staying under the tonemapper's shoulder, not over it.
const CRYSTAL_EMISSION_ENERGY := 1.15

## [ui-project-longshot] How far a tree's own leaf/bark colour is pulled toward
## C_NEAR_TREES before it is ever lit. The concept's forest is a DARK mass
## pierced by bright crystals - the contrast between the two is what makes the
## crystals read as the light source. Left at the .glb's authored green, the
## canopy lights up to the same value as the crystals and the whole frame
## flattens into one bright mint field.
const TREE_TINT := 0.62

# --- 5.8c The path and the archway [ui-project-longshot] --------------------
## Two features the concept has and the old field did not, and between them
## most of what gives that frame its depth: a lit path running away from the
## camera, and something glowing at the end of it to run TOWARD.

## The path is the corridor FIELD_CLEAR_RADIUS already keeps bare - this only
## paints it. Slightly narrower than the clear radius so the undergrowth's
## edge overhangs the stone rather than stopping in a ruler-straight line.
const PATH_WIDTH := 3.9
const PATH_COLOR := Color("4E7A56")       # lit moss between the flags
const PATH_STONE_COLOR := Color("6E8A76")  # the flagstones themselves
const FIELD_FLAGSTONES := 120             # scattered ALONG the corridor, not outside it

## The archway stands at a FIXED distance up-run and never scrolls, exactly as
## the backdrop treering does: the camera never moves in this scene, so a
## landmark pinned in world space reads as an unreachable destination on the
## horizon - which is what the concept's arch is - while everything nearer
## slides past it. Making it scroll would have the party arrive at it every
## twelve seconds and then run through it, which is a different game.
const ARCH_DISTANCE := 62.0               # up-run from PARTY_ANCHOR
const ARCH_SCALE := 1.05                  # env_arch.glb is authored ~8.8 units tall
const ARCH_STONE_TINT := 0.55             # how far the stone is pulled to haze, like the backdrop
## The veil's emission. Deliberately just over 1.0 rather than far over it:
## the arch has to be the BRIGHTEST thing in frame, but a value that clips to
## white erases the archway's silhouette along with everything behind it, and
## the shape is half of why it reads as a destination.
const ARCH_GLOW_ENERGY := 1.6
## An omni at the arch's mouth, so the light it throws lands on the ground in
## front of it instead of the arch reading as a decal pasted on the treeline.
const ARCH_LIGHT_ENERGY := 9.0
const ARCH_LIGHT_RANGE := 40.0

## Drifting spores/fireflies. The concept's air is full of them and they cost
## almost nothing - one GPUParticles3D box around the play area.
const MOTE_COUNT := 260
const MOTE_BOX := Vector3(46.0, 11.0, 46.0)
const MOTE_DRIFT := 0.55                  # units/sec upward
const MOTE_SIZE := 0.075

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
## [ui-project-longshot] Pushed back out to 84. The concept's depth comes from
## seeing FOUR distinct distance bands - near crystals, the party, the mid
## treeline, the arch - each a step paler and bluer than the last. A fog that
## reaches full opacity at 42 collapses the last two of those into one flat
## wall of haze, so there was nowhere for the archway to stand. Begin is
## pulled in rather than out to keep the same number of bands in front of the
## party as behind it.
const FOG_DEPTH_BEGIN := 9.0
const FOG_DEPTH_END := 84.0

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
## [ui-project-longshot] Tripled, and the ring pushed both nearer and much
## further: the concept's treeline is a solid dark mass that closes the frame
## on three sides, and 70 trees spread over a 22-unit band read as a picket
## fence with sky between the posts. The wider band is also what gives the
## archway trees both in FRONT of and BEHIND it to sit between.
const FIELD_TREES_BACKDROP := 210
const FIELD_BACKDROP_MIN_RADIUS := 34.0    # just past the near scatter's own reach
const FIELD_BACKDROP_MAX_RADIUS := 88.0    # inside FOG_DEPTH_END, so it still fades in rather than never being visible at all
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
const C_HORIZON_HAZE := Color(0.114, 0.365, 0.494)  # [ui-project-longshot] matches the new sky_horizon_color / fog_light_color

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
