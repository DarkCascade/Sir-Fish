@abstract
class_name ExpeditionPresentation
extends Control
## [expedition phase II] Everything RunController needs from the scene an
## expedition runs in (PRD §6.1). Each expedition style's root implements it:
## main_layout.gd for CLASSIC (the fight over the console), and the Rune
## Floor's root for RUNE_FLOOR (milestone 2, #212). One RunController drives
## every style through it, so encounters, loot and results never fork - only
## how they look does.
##
## RunController is a child of this node, so its _ready() runs FIRST: an
## implementation must answer these through get_node(), not @onready vars,
## which are still null at that point.

## The 3D battlefield. Every style's world extends battle_world.gd, which is
## what lets BattleDirector, props, drops and the wipe camera run unmodified.
@abstract func get_world() -> Node3D

## The shared BattleOverlay: enemy bars, damage numbers, glyphs, the boss
## nameplate.
@abstract func get_overlay() -> Control

## The shop encounter's blocking modal (`open(def)`, then `closed`).
@abstract func get_shop_modal() -> Control

## Hands the director to whatever shows the slot and the party's specials.
@abstract func bind_director(director: BattleDirector) -> void

## The boss's black-glass theme on or off. On lands at the nameplate's impact
## beat; off when the fight ends, whichever way. Must be safe to call when it
## is already in that state.
@abstract func boss_theme(on: bool) -> void

## The board shown or put away: on as a fight begins, off once it is won,
## before the drops land.
@abstract func board_visible(on: bool) -> void

## The party sets off toward `def`. Returns at once; travel runs until
## end_travel().
@abstract func begin_travel(def: EncounterDef) -> void

## Brings travel to a stop. A coroutine: it returns once the party has arrived
## and the encounter can start.
@abstract func end_travel() -> void

## Back to the start of the track and the board to its idle state, for a
## retry. The director, props and overlay are RunController's to clear.
@abstract func reset_track() -> void

## True when the UI is hidden for camera framing, so nothing can press a
## blocking modal's button (the shop skips instead of waiting).
@abstract func ui_hidden() -> bool
