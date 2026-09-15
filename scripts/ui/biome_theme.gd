extends RefCounted
## [biome-frames] Which environment "skin" the reliquary chrome (the crystal
## corner ornament and the item-card border) should wear right now. Static and
## stateless, the same shape as item_card_style.gd and item_card_actions.gd
## beside it.
##
## The crystal at each corner is the one constant across every skin - it is the
## reliquary's own motif, not the environment's - and only what SURROUNDS it
## (vine, plank-and-fieldstone, brass-and-velvet, black glass) changes. See
## `design documents/reference/biome_frames/` for the mockups this was built
## from.
##
## Town's Hearthwood art is the only CARD_FRAME/CORNER skin drawn so far
## (2026-09-13); every other biome() branch falls through to &"expedition" for
## those two - i.e. the original gold vine - until Shop gets its own art (Boss
## now has its own - card_frame_boss.png / frame_corner_boss.png, Meshy
## nano-banana-pro image-to-image off the vine frame, same pipeline as
## Hearthwood). There is no Place.SHOP / Place.BOSS in SceneRouter: a shop is
## a modal opened from inside a Place, not a Place of its own, and a boss
## fight is a QUEST whose encounter happens to be a boss. Both need a
## caller-supplied override (see `for_shop()` / `for_boss()`) rather than a
## SceneRouter reading.
##
## &"expedition" DOES have its own full-panel look already - rootwood-canopy,
## _PANEL_COLOR below - since that is the console's permanent reskin (slot
## machine, status bar) bleeding into whatever modal the player has opened
## while questing, not new per-biome art of the reliquary's own kind.

## SceneRouter.Place -> biome id. Every indoor town scene reads as the same
## warm hearthwood interior; only QUEST (the overworld path and its battles)
## is the cooler outdoor default.
const _PLACE_BIOME := {
	SceneRouter.Place.TOWN:       &"town",
	SceneRouter.Place.INN:        &"town",
	SceneRouter.Place.BLACKSMITH: &"town",
	SceneRouter.Place.MAYOR:      &"town",
	SceneRouter.Place.QUEST:      &"expedition",
}

const _CARD_FRAME := {
	&"town": "res://assets/ui/reliquary/card_frame_town.png",
	&"boss": "res://assets/ui/reliquary/card_frame_boss.png",
}
const _CORNER := {
	&"town": "res://assets/ui/reliquary/frame_corner_town.png",
	&"boss": "res://assets/ui/reliquary/frame_corner_boss.png",
}
const _DEFAULT_CARD_FRAME := "res://assets/ui/reliquary/card_frame.png"
const _DEFAULT_CORNER := "res://assets/ui/reliquary/frame_corner.png"

## Full-panel backdrops (inventory, party status). Unlike the card frame and
## corner, which always have SOME art (the vine default), a biome with no entry
## here just keeps its modal's plain flat fill - there is no default plank/
## stone/brass/glass texture to fall back to. CC0 (ambientCG), same convention
## as Wood060/Paper002 in mayor_office.tscn: the raw diffuse map, darkened by
## self_modulate on the TextureRect rather than pre-processing the file.
const _PANEL_BG := {
	&"town": "res://assets/Planks012_1K-JPG_Color.jpg",
	&"expedition": "res://assets/Net001A_1K-JPG_Color.jpg"
}

## [rootwood-canopy] Full-panel flat TINT, applied under whatever _PANEL_BG
## gives (or on its own, with no texture entry above - exactly the "expedition"
## case right now, pending a background texture to replace this flat square).
## A biome with no entry here keeps the modal's scene-authored plum fill
## (rel_panel in inventory_modal.tscn / party_modal.tscn) - same "no entry, no
## change" contract as _PANEL_BG, and the same reason: town's reliquary plum was
## never meant to need an override, only expedition's rootwood is new.
##
## A function, not a const dict like _CARD_FRAME/_CORNER/_PANEL_BG above:
## those hold Strings (load() paths), which GDScript can const-fold, but a
## Color pulled from another autoload's own const (Tuning.C_ROOTWOOD) is not a
## constant expression to the compiler - only reachable from inside a function
## body.
static func _panel_color(id: StringName) -> Variant:
	match id:
		&"expedition": return Tuning.C_ROOTWOOD
		&"shop": return Tuning.C_VELVET
	return null

## [brass-and-velvet] The shop's fixed identity, not a SceneRouter place - a
## shop opened in town or mid-quest looks the same either way, so callers pass
## this explicitly as the `override` on card_frame()/frame_corner()/
## apply_panel_backdrop() rather than letting biome() read the live place (see
## header). Mirrors the for_boss() this file's header already anticipates, once
## boss encounters get their own black-glass skin.
static func for_shop() -> StringName:
	return &"shop"

## [black-glass] The boss's own fixed identity, same reasoning as for_shop()
## above - a boss fight looks the same regardless of which quest it's in.
## console.gd's apply_boss_theme()/clear_boss_theme() pass this to
## card_frame() for the console's own vine-border NinePatchRects; nothing
## calls frame_corner(for_boss()) yet, since the reliquary modals are locked
## out for the whole of a boss's combat (Hud._combat_locked()) - kept for the
## same for_shop()/for_boss() symmetry the header above already commits to.
static func for_boss() -> StringName:
	return &"boss"

## SceneRouter.place, translated to a biome id. Reads live off the router
## rather than being cached, so a caller's _ready() always sees the place it
## routed INTO (spec 3.1's go() sets `place` before the fade-in finishes).
static func biome() -> StringName:
	return _PLACE_BIOME.get(SceneRouter.place, &"expedition")

## The item-card nine-patch border (card_frame.png and its skins) for the
## current biome, or an explicit `override` (for a shop modal or a boss
## encounter, neither of which SceneRouter tracks as a Place - see header).
static func card_frame(override: StringName = &"") -> Texture2D:
	var id := override if override != &"" else biome()
	return load(_CARD_FRAME.get(id, _DEFAULT_CARD_FRAME))

## The crystal corner ornament (frame_corner.png and its skins) for the
## current biome, or an explicit `override`.
static func frame_corner(override: StringName = &"") -> Texture2D:
	var id := override if override != &"" else biome()
	return load(_CORNER.get(id, _DEFAULT_CORNER))

## The full-panel backdrop texture for the current biome, or null if that
## biome has no backdrop art (see _PANEL_BG).
static func panel_background(override: StringName = &"") -> Texture2D:
	var id := override if override != &"" else biome()
	var path: String = _PANEL_BG.get(id, "")
	return load(path) if not path.is_empty() else null

## Wires a modal's Panel + its backing "Grain" TextureRect (show_behind_parent,
## drawn under Panel's own border - see inventory_modal.tscn) to the current
## biome's backdrop: a flat tint (_PANEL_COLOR), a texture over it (_PANEL_BG),
## or neither, in which case both are left untouched - Grain stays hidden and
## Panel keeps whatever flat fill the scene already gives it.
##
## Callers must re-run this on every open(), not just _ready() - InventoryModal
## and PartyModal live under the persistent Hud autoload (see hud.gd), so their
## _ready() only ever fires once, at boot, while SceneRouter.place is still its
## default TOWN. Re-reading here is what lets a modal opened mid-quest actually
## show the biome it was opened INTO.
##
## The stylebox swap is done here, on the LIVE stylebox, rather than authoring a
## second "town"/"expedition" copy of the panel's border/radius/margin numbers
## in every .tscn that calls this - one of those going stale under the other's
## edits is exactly the drift item_card_actions.gd's header warns about.
static func apply_panel_backdrop(panel: PanelContainer, grain: TextureRect,
		override: StringName = &"") -> void:
	var id := override if override != &"" else biome()
	var color: Variant = _panel_color(id)
	var tex := panel_background(id)
	grain.visible = tex != null
	if color == null and tex == null:
		return
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	if color != null:
		style.bg_color = color
	if tex != null:
		grain.texture = tex
		style.draw_center = false
	panel.add_theme_stylebox_override("panel", style)
