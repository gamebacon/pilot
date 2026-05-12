extends Node3D
class_name ShopBuilding

@export var shop_label: String = "Shop"
@export var shop_type: String  = "general"  # "hardware" | "grocery" | "paint" | ...
@export var stock_ids: Array[String] = []

var _stock: Array[ItemData] = []

func _ready() -> void:
	_load_stock()
	_populate_empty_slots()

func _load_stock() -> void:
	if stock_ids.is_empty():
		_stock = ItemRegistry.get_all()
	else:
		for id in stock_ids:
			var item := ItemRegistry.get_item(id)
			if item:
				_stock.append(item)
			else:
				push_warning("ShopBuilding '%s': unknown item id '%s'" % [shop_label, id])

# Fills any ShopShelfSlot descendants that have no item_data assigned.
# Pre-assigned slots (set in the scene) are left untouched.
func _populate_empty_slots() -> void:
	var empty: Array[ShopShelfSlot] = []
	_collect_empty(self, empty)

	var idx := 0
	for slot in empty:
		if idx >= _stock.size():
			break
		slot.item_data = _stock[idx]
		slot.apply_display()
		idx += 1

func _collect_empty(node: Node, out: Array[ShopShelfSlot]) -> void:
	if node is ShopShelfSlot and node.item_data == null:
		out.append(node as ShopShelfSlot)
	for child in node.get_children():
		_collect_empty(child, out)
