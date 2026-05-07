class_name Inventory
extends Node

signal item_added(item: PhysicalItem)
signal item_removed(item: PhysicalItem)
signal changed(items: Array[PhysicalItem], capacity: int)

@export var capacity: int = 10

var items: Array[PhysicalItem] = []

func add(item: PhysicalItem) -> void:
	items.append(item)
	item_added.emit(item)
	changed.emit(items, capacity)

func remove(item: PhysicalItem) -> void:
	items.erase(item)
	item_removed.emit(item)
	changed.emit(items, capacity)

func remove_by_id(id: String) -> PhysicalItem:
	for i in range(items.size() - 1, -1, -1):
		if items[i].item_data and items[i].item_data.id == id:
			var item := items[i]
			items.remove_at(i)
			item_removed.emit(item)
			changed.emit(items, capacity)
			return item
	return null

func find_by_id(id: String) -> PhysicalItem:
	for item in items:
		if item.item_data and item.item_data.id == id:
			return item
	return null

func has_id(id: String) -> bool:
	return find_by_id(id) != null

func last() -> PhysicalItem:
	return items.back() if not items.is_empty() else null

func is_full() -> bool:
	return items.size() >= capacity

func is_empty() -> bool:
	return items.is_empty()

func size() -> int:
	return items.size()
