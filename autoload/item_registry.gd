extends Node
# Central item database. Auto-scans res://items/resources/ at startup.
# Access anywhere as ItemRegistry.get_item(id), ItemRegistry.get_all(), etc.

var _items: Dictionary = {}  # id -> ItemData

func _ready() -> void:
	_scan()

func _scan() -> void:
	var dir := DirAccess.open(GameConstants.ITEM_RES_DIR)
	if not dir:
		push_error("ItemRegistry: cannot open " + GameConstants.ITEM_RES_DIR)
		return

	var all_files: Array[String] = []
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			all_files.append(file)
		file = dir.get_next()

	# Pass 1 — materials: load everything except blueprints so that
	# ItemData is fully populated before blueprint _init() runs.
	for f in all_files:
		if not f.begins_with("blueprint_"):
			_load_tres(f)

	# Pass 2 — blueprints: _init() can now call ItemRegistry.get_item()
	# and find all materials already registered.
	for f in all_files:
		if f.begins_with("blueprint_"):
			_load_tres(f)

func _load_tres(file: String) -> void:
	var res := load(GameConstants.ITEM_RES_DIR + file)
	if res is ItemData:
		if _items.has(res.id):
			push_warning("ItemRegistry: duplicate id '%s' in %s" % [res.id, file])
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
