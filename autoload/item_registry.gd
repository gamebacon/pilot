extends Node
# Central item database. All resources are preloaded so Godot's export
# scanner tracks them and they end up in the .pck.

var _items: Dictionary = {}  # id -> ItemData

const _MATERIALS: Array = [
	# Harvestables / crafting base
	preload("res://items/resources/stone.tres"),
	preload("res://items/resources/wood_log.tres"),
	preload("res://items/resources/wooden_plank.tres"),
	# Building pieces — twig tier (only craftable tier for now)
	preload("res://items/resources/building/foundation_twig.tres"),
	preload("res://items/resources/building/wall_twig.tres"),
	preload("res://items/resources/building/tower_twig.tres"),
	# Tools
	preload("res://items/resources/tools/axe_wooden.tres"),
	preload("res://items/resources/tools/axe_stone.tres"),
	preload("res://items/resources/tools/axe_iron.tres"),
	preload("res://items/resources/tools/pickaxe_wooden.tres"),
	preload("res://items/resources/tools/pickaxe_stone.tres"),
	preload("res://items/resources/tools/pickaxe_iron.tres"),
	# Weapons
	preload("res://items/resources/weapons/sword_wooden.tres"),
	preload("res://items/resources/weapons/sword_stone.tres"),
	preload("res://items/resources/weapons/sword_iron.tres"),
	# Placeable items
	preload("res://items/resources/chest.tres"),
	# Ore drops
	preload("res://items/resources/ores/flint.tres"),
	preload("res://items/resources/ores/coal.tres"),
	preload("res://items/resources/ores/copper_ore.tres"),
	preload("res://items/resources/ores/iron_ore.tres"),
	preload("res://items/resources/ores/quartz.tres"),
	preload("res://items/resources/ores/gold_ore.tres"),
	preload("res://items/resources/ores/amber.tres"),
	preload("res://items/resources/ores/diamond.tres"),
	preload("res://items/resources/ores/obsidian_shard.tres"),
]

func _ready() -> void:
	for res in _MATERIALS:
		_register(res)

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
