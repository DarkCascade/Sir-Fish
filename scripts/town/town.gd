extends Control
## [town] The hub (spec 7.1). Three buttons, one per interior; the scene is
## otherwise scriptless chrome - button positions and art are authored in
## town.tscn, per CLAUDE.md's "prefer inspector properties over code".
##
## BlacksmithButton routes to a scene that does not exist until step 10. That is
## fine: SceneRouter.go()'s missing-path bail (spec 3.1) logs a warning and stays
## put rather than soft-locking behind the fade. MayorButton is live from step 8.

@onready var _inn_button: Button = $InnButton
@onready var _blacksmith_button: Button = $BlacksmithButton
@onready var _mayor_button: Button = $MayorButton

func _ready() -> void:
	# spec 3.1: every routed scene re-asserts its own place, so a direct launch
	# (F5, MCP play_scene) that never went through go() still reads true.
	SceneRouter.place = SceneRouter.Place.TOWN
	_inn_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.INN))
	_blacksmith_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.BLACKSMITH))
	_mayor_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.MAYOR))
