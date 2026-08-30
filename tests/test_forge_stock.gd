extends Node
## The blacksmith's Buy-tab stock: generate_forge_stock()'s shape, the restock
## predicate that stops buying out the stock from being a free refresh (spec 7.4
## / A1), and forge_stock's persistence (spec 2.4). The step-10 pinning test the
## initiative shipped without - A1 and B2 would both have been caught here (C1).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_forge_stock.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	GameState.new_profile()

	# --- stock shape (spec 7.4, B2) ----------------------------------------
	var stock := Itemizer.generate_forge_stock()
	t.check(stock.size() == Tuning.FORGE_SHOP_SLOTS,
		"generate_forge_stock() returns FORGE_SHOP_SLOTS items (%d vs %d)"
			% [stock.size(), Tuning.FORGE_SHOP_SLOTS])

	var enhanced_seen := 0
	var rarities_seen := {}
	var slot_bad := 0
	var unusable := 0
	var party := GameState.active_party
	for _n: int in range(400):
		for it: Item in Itemizer.generate_forge_stock():
			if it.rarity == Item.Rarity.ENHANCED:
				enhanced_seen += 1
			rarities_seen[int(it.rarity)] = true
			if not (it.slot() in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]):
				slot_bad += 1
			var can := false
			for c: StringName in it.usable_by():
				if c in party:
					can = true
			if not can:
				unusable += 1
	t.check(enhanced_seen == 0,
		"ENHANCED never appears in forge stock - it is forge-only (%d seen)" % enhanced_seen)
	t.check(rarities_seen.has(int(Item.Rarity.COMMON)) and rarities_seen.has(int(Item.Rarity.UNCOMMON))
			and rarities_seen.has(int(Item.Rarity.MAGIC)) and rarities_seen.has(int(Item.Rarity.RARE)),
		"every rarity COMMON..RARE appears across the sample (%s)" % [rarities_seen.keys()])
	t.check(slot_bad == 0, "every item's slot() is one of the three (%d off)" % slot_bad)
	t.check(unusable == 0,
		"every item is usable by the active party - slot-first generation (%d off)" % unusable)

	# --- generate_shop_stock() is untouched (spec 7.4, §0.3) --------------
	t.check(Itemizer.generate_shop_stock().size() == Tuning.SHOP_ITEMS_FOR_SALE,
		"generate_shop_stock() still returns SHOP_ITEMS_FOR_SALE items")
	t.check(Tuning.FORGE_SHOP_SLOTS != Tuning.SHOP_ITEMS_FOR_SALE,
		"the forge stock is a separate generator, not generate_shop_stock() (%d vs %d)"
			% [Tuning.FORGE_SHOP_SLOTS, Tuning.SHOP_ITEMS_FOR_SALE])

	# --- restock predicate (A1) ------------------------------------------
	GameState.new_profile()
	t.check(GameState.needs_forge_restock(),
		"after new_profile(), needs_forge_restock() is true")

	GameState.forge_stock = Itemizer.generate_forge_stock()
	GameState.forge_stock_generated = true
	t.check(not GameState.needs_forge_restock(),
		"after a generation sets the flag, needs_forge_restock() is false")

	for it: Item in GameState.forge_stock.duplicate():
		GameState.forge_stock.erase(it)
	t.check(GameState.forge_stock.is_empty() and not GameState.needs_forge_restock(),
		"an emptied (bought-out) stock still reads needs_forge_restock() == false - A1's regression guard")

	GameState.forge_stock = Itemizer.generate_forge_stock()   # a reroll
	GameState.forge_stock_generated = true
	t.check(not GameState.needs_forge_restock(), "a reroll leaves needs_forge_restock() false")

	# --- persistence (spec 2.4) ----------------------------------------
	GameState.new_profile()
	GameState.gold = 500
	GameState.forge_stock = Itemizer.generate_forge_stock()
	GameState.forge_stock_generated = true
	var want: Array = []
	for it: Item in GameState.forge_stock:
		want.append([it.weapon_type, int(it.rarity), it.value, it.forge_count, it.modifiers.size()])
	SaveGame.save_profile()

	GameState.forge_stock = []
	GameState.forge_stock_generated = false
	t.check(SaveGame.load_profile(), "the round-trip save loads back")
	var round_trip_ok := GameState.forge_stock.size() == want.size()
	for i: int in range(mini(want.size(), GameState.forge_stock.size())):
		var it := GameState.forge_stock[i]
		if [it.weapon_type, int(it.rarity), it.value, it.forge_count, it.modifiers.size()] != want[i]:
			round_trip_ok = false
	t.check(round_trip_ok, "forge_stock round-trips field-for-field")
	t.check(GameState.forge_stock_generated, "forge_stock_generated round-trips (true)")

	# --- a save with no forge_stock_generated key derives the default (A1) ---
	var f := FileAccess.open(SaveGame.PATH, FileAccess.READ)
	var d: Dictionary = str_to_var(f.get_as_text())
	f.close()
	d.erase("forge_stock_generated")
	var w := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	w.store_string(var_to_str(d))
	w.close()
	GameState.forge_stock_generated = false
	SaveGame.load_profile()
	t.check(GameState.forge_stock_generated,
		"a legacy save with no forge_stock_generated key, holding real stock, loads as generated (not bare false)")

	t.finish(get_tree(), "test_forge_stock")
