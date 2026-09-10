extends Control
## [town] The blacksmith (spec 7.3, 7.4). A routed town scene like the inn and
## the mayor's office, with four tabs mirroring the shop's TabContainer:
##
##   - Forge: GameState.equipped_set(&"warrior") - the warrior's three equipped
##     items, one row each, an empty-slot placeholder where a slot is unfilled.
##     Each row walks its item one rarity step up the ladder (Itemizer.forge());
##     every forge saves the profile and flashes the new modifier line.
##   - Buy: FORGE_SHOP_SLOTS cards from Itemizer.generate_forge_stock(), cached on
##     GameState.forge_stock and rerolled ONLY by the refresh button, which costs
##     SHOP_REFRESH_COST gold (spec 7.4). Walking out and back in never rerolls.
##   - Scrap: [item-card] one ItemCard per inventory item in
##     Mode.SCRAP - the primary bar melts the item down for Item.scrap_value()
##     scrap (a quarter of its gold sell price).
##   - Sell: [refinement-pass-3] the same rows in Mode.SELL, identical to the
##     expedition shop's Sell tab - the merchant at the quest shop is no longer
##     the only place to offload loot.
##
## The HUD's CurrencyPlate carries the gold/scrap readout, so this scene keeps
## none of its own. The forge background (assets/blacksmith-bg.png) and its
## darkening Vignette scrim are authored in blacksmith.tscn - the Meshy art
## pass, spec 12.1 (step 11).

const ITEM_CARD := preload("res://scenes/modals/item_card.tscn")
## The shared transactions behind the card buttons, and the Mode enum the
## Scrap and Sell tabs differ by.
const CardActions := preload("res://scripts/ui/item_card_actions.gd")

const SLOT_NAMES := {
	Item.Slot.WEAPON: "weapon",
	Item.Slot.ARMOR: "armor",
	Item.Slot.TRINKET: "trinket",
}

@onready var _tabs: TabContainer = $Layout/Tabs
@onready var _forge_list: VBoxContainer = $Layout/Tabs/Forge/ForgeList
@onready var _buy_list: VBoxContainer = $Layout/Tabs/Buy/BuyScroll/BuyList
@onready var _buy_empty: Label = $Layout/Tabs/Buy/BuyEmpty
@onready var _refresh_button: Button = $Layout/Tabs/Buy/BuyHeader/RefreshButton
@onready var _scrap_list: VBoxContainer = $Layout/Tabs/Scrap/ScrapScroll/ScrapList
@onready var _scrap_empty: Label = $Layout/Tabs/Scrap/ScrapEmpty
@onready var _scrap_all_button: Button = $Layout/Tabs/Scrap/ScrapHeader/ScrapAllCommonButton
@onready var _sell_list: VBoxContainer = $Layout/Tabs/Sell/SellScroll/SellList
@onready var _sell_empty: Label = $Layout/Tabs/Sell/SellEmpty
@onready var _sell_all_button: Button = $Layout/Tabs/Sell/SellHeader/SellAllCommonButton
@onready var _back_button: Button = $Layout/BackButton
@onready var _compare_flyout = $CompareFlyout   # CompareFlyout (untyped: custom API)

var _cards: Array = []
var _forge_rows: Dictionary = {}   # Item.Slot -> ItemCard (filled slots only)

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.BLACKSMITH
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	_refresh_button.pressed.connect(_on_refresh)
	_scrap_all_button.pressed.connect(_on_scrap_all_common)
	_sell_all_button.pressed.connect(_on_sell_all_common)
	EventBus.gold_changed.connect(_on_currency_changed)
	EventBus.scrap_changed.connect(_on_currency_changed)

	# spec 7.4: first visit generates the stock and persists it; every visit after
	# reads the cached copy. new_profile() clears the flag, so a fresh profile
	# lands here. The flag (not forge_stock.is_empty()) is the sentinel - buying
	# out all six cards must not read as "never generated" (A1).
	if GameState.needs_forge_restock():
		GameState.forge_stock = Itemizer.generate_forge_stock()
		GameState.forge_stock_generated = true
		SaveGame.save_profile()

	_build_forge()
	_build_buy()
	_build_scrap()
	_build_sell()
	_refresh_refresh_button()
	_tabs.current_tab = 0

## ui_cancel (and Android's back gesture) routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

# --- forge tab ---------------------------------------------------------------

func _build_forge() -> void:
	for child: Node in _forge_list.get_children():
		child.queue_free()
	_forge_rows.clear()
	var hero: StringName = GameState.active_party[0] if not GameState.active_party.is_empty() else &"warrior"
	for s: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		var worn := GameState.equipped_item(hero, s)
		if worn == null:
			_forge_list.add_child(_empty_slot_row(s))
			continue
		var card := ITEM_CARD.instantiate()
		_forge_list.add_child(card)
		card.setup(worn)
		var acts: Array[StringName] = [&"forge"]
		card.set_actions(acts)
		card.action_pressed.connect(_on_forge_pressed.bind(worn))
		_refresh_forge_card(card)
		_forge_rows[s] = card

## A named placeholder, not a missing row - "you have nothing in your trinket
## slot" is information the forge screen should volunteer (spec 7.3).
func _empty_slot_row(s: Item.Slot) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 0)
	var l := Label.new()
	l.text = "Your %s slot is empty — nothing to forge." % SLOT_NAMES[s]
	l.custom_minimum_size = Vector2(0, 120)
	l.add_theme_font_size_override("font_size", 54)
	l.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel

## [item-card] Takes the action id the universal card emits, then the item it
## was bound to. The id is ignored - the Forge card offers exactly one action.
func _on_forge_pressed(_id: StringName, item: Item) -> void:
	var slot := item.slot()
	if not Itemizer.forge(item):
		return
	SaveGame.save_profile()
	_build_forge()
	if _forge_rows.has(slot):
		# The whole card washes the new rarity colour now. forge_row.gd tinted
		# just the appended modifier LINE, which the card does not have - it
		# shows modifiers as icon chips, where a one-line colour fade would be
		# invisible.
		_forge_rows[slot].flash_rarity()
	_refresh_forge_affordability()
	# The forged item is worth more now, so its Scrap/Sell rows (shown but
	# locked while equipped) must reprice.
	_build_scrap()
	_build_sell()

func _refresh_forge_affordability() -> void:
	for card: Variant in _forge_rows.values():
		if is_instance_valid(card):
			_refresh_forge_card(card)

## Sets the Forge button label and enabled state (spec 7.3): the next rarity
## and its price when affordable, the shortfall spelled out when not, and a
## disabled "Fully forged" at ENHANCED - which is why the button is always
## present rather than swapped for the old static plate. Lifted from
## forge_row.gd, the scene the universal card replaced.
func _refresh_forge_card(card: Control) -> void:
	var item: Item = card.item
	if item == null:
		return
	if item.rarity >= Item.Rarity.ENHANCED:
		card.set_action_text(&"forge", "Fully forged")
		card.set_action_disabled(&"forge", true)
		return
	var cost: Array = Tuning.FORGE_COSTS[item.rarity]
	var need_scrap := int(cost[0])
	var need_gold := int(cost[1])
	var to_name: String = Item.rarity_name_for(item.rarity + 1)
	var short_scrap: int = maxi(0, need_scrap - GameState.scrap)
	var short_gold: int = maxi(0, need_gold - GameState.gold)
	if short_scrap == 0 and short_gold == 0:
		card.set_action_disabled(&"forge", false)
		card.set_action_text(&"forge", "FORGE  →  %s        %d scrap  ·  %d gold"
			% [to_name, need_scrap, need_gold])
	else:
		card.set_action_disabled(&"forge", true)
		var parts: PackedStringArray = []
		if short_scrap > 0:
			parts.append("%d more scrap" % short_scrap)
		if short_gold > 0:
			parts.append("%d more gold" % short_gold)
		card.set_action_text(&"forge", "FORGE  →  %s   (need %s)"
			% [to_name, " and ".join(parts)])

# --- buy tab ---------------------------------------------------------------

func _build_buy() -> void:
	for child: Node in _buy_list.get_children():
		child.queue_free()
	_cards.clear()
	_buy_empty.visible = GameState.forge_stock.is_empty()
	var index := 0
	for item: Item in GameState.forge_stock:
		var card := ITEM_CARD.instantiate()
		_buy_list.add_child(card)
		card.setup(item)
		var acts: Array[StringName] = [&"compare", &"buy"]
		card.set_actions(acts)
		card.set_action_text(&"buy", CardActions.buy_label(item))
		card.action_pressed.connect(_on_buy_action.bind(card, item))
		card.play_entrance(index)
		_cards.append(card)
		index += 1
	await get_tree().process_frame
	_refresh_cards()

func _on_compare_requested(item: Item) -> void:
	_compare_flyout.show_for(item)

func _refresh_cards() -> void:
	for card: Variant in _cards:
		if is_instance_valid(card):
			CardActions.refresh_buy_state(card, card.item)

func _on_buy_action(id: StringName, card: Control, item: Item) -> void:
	if id == &"compare":
		_on_compare_requested(item)
	elif id == &"buy" and CardActions.do_buy(card, item):
		_on_purchased(item)

func _on_purchased(item: Item) -> void:
	GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
	# The bought item leaves the persistent stock, so walking back in does not
	# offer it again (spec 7.4). add_item() may have auto-equipped it into an
	# empty slot, so the Forge tab is rebuilt too.
	GameState.forge_stock.erase(item)
	_buy_empty.visible = GameState.forge_stock.is_empty()
	SaveGame.save_profile()
	_build_forge()
	# add_item() put the purchase in the inventory (or auto-equipped it) - either
	# way it is now a Scrap/Sell candidate.
	_build_scrap()
	_build_sell()

func _on_refresh() -> void:
	if not GameState.spend_gold(Tuning.SHOP_REFRESH_COST):
		return
	GameState.forge_stock = Itemizer.generate_forge_stock()
	GameState.forge_stock_generated = true   # harmless when already true (A1)
	SaveGame.save_profile()
	_build_buy()

func _refresh_refresh_button() -> void:
	var affordable := GameState.gold >= Tuning.SHOP_REFRESH_COST
	_refresh_button.disabled = not affordable
	_refresh_button.modulate = Color.WHITE if affordable else Color(0.68, 0.65, 0.6, 1.0)

# --- scrap / sell tabs ---------------------------------------------------------

## [refinement-pass-3] Both tabs list the WHOLE inventory, equipped items
## included - exactly as the shop's Sell tab does (shop_modal.gd's _build_sell).
## An equipped card renders locked (ItemCardActions.refresh_sell_state), so
## the player can still see and compare it without being able to melt it down
## from under its hero.
func _build_scrap() -> void:
	_build_item_rows(_scrap_list, _scrap_empty, CardActions.Mode.SCRAP, _on_scrapped)

func _build_sell() -> void:
	_build_item_rows(_sell_list, _sell_empty, CardActions.Mode.SELL, _on_sold)

func _build_item_rows(list: VBoxContainer, empty: Label, mode: int,
		on_done: Callable) -> void:
	for child: Node in list.get_children():
		child.queue_free()
	var items := GameState.inventory
	empty.visible = items.is_empty()
	var index := 0
	for item: Item in items:
		var card := ITEM_CARD.instantiate()
		list.add_child(card)
		card.setup(item)
		var acts: Array[StringName] = [&"compare"]
		var eq := CardActions.equip_action(item)
		if eq != &"":
			acts.append(eq)
		acts.append(&"sell")
		card.set_actions(acts)
		CardActions.refresh_sell_state(card, item, mode)
		card.action_pressed.connect(_on_item_action.bind(card, item, mode, on_done))
		card.play_entrance(index)
		index += 1
	_refresh_bulk_buttons()

## `on_done` is the tab-specific tail (_on_scrapped / _on_sold), run only once
## the payout has actually happened - an equipped item refuses the sale.
func _on_item_action(id: StringName, card: Control, item: Item, mode: int,
		on_done: Callable) -> void:
	match id:
		&"compare":
			_on_compare_requested(item)
		&"equip", &"unequip":
			CardActions.do_equip(item, id == &"equip")
			_on_equip_changed()
		&"sell":
			if CardActions.do_sell(card, item, mode):
				on_done.call()

## The unequipped Common items - what "Sell/Scrap All Common" would act on.
## Equipped Commons are skipped for the same reason a row locks them: a bulk
## button should not strip a hero's gear.
func _loose_commons() -> Array[Item]:
	var out: Array[Item] = []
	for item: Item in GameState.inventory:
		if item.rarity == Item.Rarity.COMMON and item.equipped_by == &"":
			out.append(item)
	return out

func _refresh_bulk_buttons() -> void:
	var none := _loose_commons().is_empty()
	_scrap_all_button.disabled = none
	_sell_all_button.disabled = none

func _on_scrap_all_common() -> void:
	_bulk_dispose(true)

func _on_sell_all_common() -> void:
	_bulk_dispose(false)

## En-masse counterpart to ItemCardActions.do_sell(): same per-item payout
## and inventory removal, applied to every loose Common at once, then one save
## and one rebuild of both tabs.
func _bulk_dispose(as_scrap: bool) -> void:
	var commons := _loose_commons()
	if commons.is_empty():
		return
	for item: Item in commons:
		if as_scrap:
			GameState.add_scrap(item.scrap_value())
		else:
			GameState.add_gold(item.sell_price())
			GameState.run_stats["items_sold"] = int(GameState.run_stats["items_sold"]) + 1
		GameState.remove_item(item)
	SaveGame.save_profile()
	_build_scrap()
	_build_sell()

## Selling and scrapping both shrink the inventory, so the sibling tab is
## rebuilt to drop the same row. The acting tab lets its own row animate out.
func _on_scrapped() -> void:
	SaveGame.save_profile()
	_build_sell()

func _on_sold() -> void:
	SaveGame.save_profile()
	_build_scrap()

## An equip/unequip may have unequipped a DIFFERENT row's item for the same
## hero and it changes the Forge tab's equipped set, so everything downstream
## of the inventory is rebuilt.
func _on_equip_changed() -> void:
	SaveGame.save_profile()
	_build_forge()
	_build_scrap()
	_build_sell()

# --- currency --------------------------------------------------------------

func _on_currency_changed(_total: int, _delta: int) -> void:
	_refresh_forge_affordability()
	_refresh_cards()
	_refresh_refresh_button()
