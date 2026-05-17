extends Node
# Central item database.
#
# Materials are preloaded as constants — Godot's export scanner tracks them
# and their ItemData._init() never calls ItemRegistry, so the timing is safe.
#
# Blueprints call ItemRegistry.get_item() inside their _init() (they need the
# material data to build their slot lists). They must be loaded in _ready(),
# after all materials are already registered. load() with literal paths is
# also tracked by Godot's export scanner, so they'll be in the .pck.

var _items: Dictionary = {}  # id -> ItemData

# ── Material resources (preloaded — safe at parse time) ───────────────────────

const _MATERIALS: Array = [
	preload("res://items/resources/aspen_cladding.tres"),
	preload("res://items/resources/birch_bundle.tres"),
	preload("res://items/resources/chewing_gum.tres"),
	preload("res://items/resources/chips_bag.tres"),
	preload("res://items/resources/chocolate_bar.tres"),
	preload("res://items/resources/coffee_cup.tres"),
	preload("res://items/resources/cola_bottle.tres"),
	preload("res://items/resources/concrete_slab.tres"),
	preload("res://items/resources/drywall.tres"),
	preload("res://items/resources/energy_drink.tres"),
	preload("res://items/resources/floor_joist.tres"),
	preload("res://items/resources/framing_section.tres"),
	preload("res://items/resources/glass_window.tres"),
	preload("res://items/resources/hand_cream.tres"),
	preload("res://items/resources/hot_dog.tres"),
	preload("res://items/resources/ice_scraper.tres"),
	preload("res://items/resources/insulation_batt.tres"),
	preload("res://items/resources/isolation.tres"),
	preload("res://items/resources/lighter.tres"),
	preload("res://items/resources/lottery_ticket.tres"),
	preload("res://items/resources/milk_carton.tres"),
	preload("res://items/resources/newspaper.tres"),
	preload("res://items/resources/orange_juice.tres"),
	preload("res://items/resources/painkiller.tres"),
	preload("res://items/resources/pine_board.tres"),
	preload("res://items/resources/pine_decking.tres"),
	preload("res://items/resources/protein_bar.tres"),
	preload("res://items/resources/road_map.tres"),
	preload("res://items/resources/roofing_panel.tres"),
	preload("res://items/resources/sauna_beer.tres"),
	preload("res://items/resources/sauna_panel.tres"),
	preload("res://items/resources/sauna_sausage.tres"),
	preload("res://items/resources/sauna_stone.tres"),
	preload("res://items/resources/snus_can.tres"),
	preload("res://items/resources/soap_bar.tres"),
	preload("res://items/resources/stud_2x4.tres"),
	preload("res://items/resources/timber_post.tres"),
	preload("res://items/resources/timber_stud.tres"),
	preload("res://items/resources/wall_plate.tres"),
	preload("res://items/resources/wall_stud.tres"),
	preload("res://items/resources/water_bottle.tres"),
	preload("res://items/resources/wet_wipes.tres"),
	preload("res://items/resources/wood_board.tres"),
	preload("res://items/resources/wood_plank.tres"),
	preload("res://items/resources/stone.tres"),
	preload("res://items/resources/wood_log.tres"),
	preload("res://items/resources/wooden_plank.tres"),
	preload("res://items/resources/wooden_wall.tres"),
]

func _ready() -> void:
	# Pass 1 — register all materials so they're available via get_item().
	for res in _MATERIALS:
		_register(res)

	# Pass 2 — blueprints: their _init() calls get_item() to look up materials,
	# so they must be loaded here, after pass 1 completes.
	# load() with literal strings is tracked by Godot's export dependency scanner.
	_register(load("res://items/resources/blueprint_house.tres"))
	_register(load("res://items/resources/blueprint_sauna.tres"))
	_register(load("res://items/resources/blueprint_terrace.tres"))
	_register(load("res://items/resources/blueprint_woodshed.tres"))

func _register(res: Resource) -> void:
	if not res is ItemData:
		return
	if _items.has(res.id):
		push_warning("ItemRegistry: duplicate id '%s'" % res.id)
	else:
		_items[res.id] = res

# ── Lookups ───────────────────────────────────────────────────────────────────

func get_item(id: String) -> ItemData:
	return _items.get(id, null)

func get_all() -> Array[ItemData]:
	var arr: Array[ItemData] = []
	arr.assign(_items.values())
	return arr

func get_by_category(cat: String) -> Array[ItemData]:
	var arr: Array[ItemData] = []
	for item: ItemData in _items.values():
		if item.category == cat:
			arr.append(item)
	return arr

func all_ids() -> Array[String]:
	return _items.keys()
