extends Control
## [screen-corner variant] The party's bonus list, docked to the top-right of
## the screen instead of living in the console (see bonus_strip.gd for the
## data and glyphs, both shared with the console's copy and the shop's). This
## is a thin wrapper: it owns the frame background and keeps the panel's own
## size (and therefore its top-right-anchored position) matched to however
## tall the vertical list currently is.

@onready var frame: OrnateFrame = $Frame
@onready var strip: Control = $BonusStrip  # BonusStrip (untyped: custom API)

func _ready() -> void:
	EventBus.party_bonuses_changed.connect(func(_b: Dictionary) -> void: _refresh())
	EventBus.run_started.connect(_refresh)
	_refresh()

func _refresh() -> void:
	strip.refresh()
	visible = strip.has_bonuses()
	custom_minimum_size = strip.size
	size = strip.size
