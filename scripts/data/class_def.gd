class_name ClassDef
extends Resource
## A hero class's identity on the slot board (decision D1 - Executor, content
## phase 1 spec §2/§3 Step 2). Everything that used to differentiate a class
## through hardcoded per-id branches moves here: SlotIcon.innate_for()'s
## mage/damage ternary, SlotMachine._swinging_hero()'s "first living hero"
## rule, HeroBars.CLASS_BAR_COLORS, ClassIconGlyph._draw()'s per-class match,
## and Itemizer.ITEM_TYPES' `classes: [&"warrior"]` rows. Adding a fourth class
## is meant to be one CombatantStats .tres, one ClassDef .tres, one rig
## profile, one scene - see the executor ceiling note in §2.1 for what to do
## when a new class has no unowned icon kind left.

@export var id: StringName = &""

## [content phase 1] Where this class sits in the derived roster
## (GameState.PARTY_ORDER) - moved off CombatantStats (spec §3 Step 5 / D3
## originally put it there; §2's ClassDef table moves it here for Phase 1).
@export var roster_order: int = 0

## The icon id a living hero of this class contributes every spin, one per
## living hero, regardless of gear (SlotIcon.innate()'s floor). Replaces
## SlotIcon.innate_for()'s hardcoded ternary.
@export var innate_icon: StringName = &""

## The executor rule (D1): which SlotIcon.Kind values (as ints - kept plain
## rather than Array[SlotIcon.Kind] so a .tres doesn't have to guess how Godot
## serialises a typed array of a nested enum) this class resolves the
## aggregated action for when a living member of it is available. See
## SlotMachine._executor_for() and content-phase-1 questions doc Q2 for
## exactly which board resolutions this currently changes (only the DAMAGE
## swing, in Phase 1).
@export var executes: Array[int] = []

## The party-bar medallion glyph (was ClassIconGlyph._draw()'s per-class
## texture match) and the box-fraction it draws at (was that function's
## per-class magic number, e.g. 0.66 for the mage's heart-shaped cross).
@export var glyph: Texture2D
@export_range(0.0, 1.0, 0.01) var glyph_box_fraction: float = 0.7

## The party-bar fill/medallion colour (was HeroBars.CLASS_BAR_COLORS).
@export var bar_color: Color = Color.WHITE

## Every Itemizer.ITEM_TYPES key this class may wield/wear, across all three
## slots (was ITEM_TYPES[type]["classes"] listing &"warrior" on every row).
## See content-phase-1 questions doc Q3 for why armor/trinket rows are shared
## across classes while weapon rows stay class-exclusive.
@export var item_types: Array[StringName] = []
