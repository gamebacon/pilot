class_name Inventory
extends Node

signal item_added(item: PhysicalItem)
signal item_removed(item: PhysicalItem)
signal changed(items: Array[PhysicalItem], capacity: int, active_index: int)

@export var capacity: int = 10

var items: Array[PhysicalItem] = []
var active_index: int = 0

# ── Core mutations ─────────────────────────────────────────────────────────────

func add(item: PhysicalItem) -> void:
	items.append(item)
	item_added.emit(item)
	changed.emit(items, capacity, active_index)

func remove(item: PhysicalItem) -> void:
	items.erase(item)
	active_index = clamp(active_index, 0, max(0, items.size() - 1))
	item_removed.emit(item)
	changed.emit(items, capacity, active_index)

func remove_by_id(id: String) -> PhysicalItem:
	for i in range(items.size() - 1, -1, -1):
		if items[i].item_data and items[i].item_data.id == id:
			var item := items[i]
			items.remove_at(i)
			active_index = clamp(active_index, 0, max(0, items.size() - 1))
			item_removed.emit(item)
			changed.emit(items, capacity, active_index)
			return item
	return null

# ── Active item / cycling ──────────────────────────────────────────────────────

func active() -> PhysicalItem:
	if items.is_empty():
		return null
	active_index = clamp(active_index, 0, items.size() - 1)
	return items[active_index]

func cycle_next() -> void:
	if items.is_empty():
		return
	var current_id := _item_id(items[active_index])
	for i in range(1, items.size()):
		var next := (active_index + i) % items.size()
		if _item_id(items[next]) != current_id:
			active_index = next
			changed.emit(items, capacity, active_index)
			return

# ── Slot counting (respects carry_stack) ──────────────────────────────────────

func used_slots() -> int:
	var counts: Dictionary = {}
	for item in items:
		var id := _item_id(item)
		counts[id] = counts.get(id, 0) + 1
	var total := 0
	for id in counts:
		total += ceili(float(counts[id]) / _carry_stack_for_id(id))
	return total

# Returns the 0-based visual slot index for an item (same type → same slot).
func slot_for(item: PhysicalItem) -> int:
	var slot := 0
	var slot_by_id: Dictionary = {}
	for it in items:
		var id := _item_id(it)
		if id not in slot_by_id:
			slot_by_id[id] = slot
			var count := 0
			for i in items:
				if _item_id(i) == id:
					count += 1
			slot += ceili(float(count) / _carry_stack_for_id(id))
		if it == item:
			return slot_by_id[id]
	return 0

func has_multiple_types() -> bool:
	if items.is_empty():
		return false
	var first := _item_id(items[0])
	for item in items:
		if _item_id(item) != first:
			return true
	return false

# ── Lookups ────────────────────────────────────────────────────────────────────

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
	if GameState.debug_mode:
		return false
	return used_slots() >= capacity

func is_empty() -> bool:
	return items.is_empty()

func size() -> int:
	return items.size()

# ── Helpers ────────────────────────────────────────────────────────────────────

func _item_id(item: PhysicalItem) -> String:
	return item.item_data.id if item.item_data else str(item.get_instance_id())

func _carry_stack_for_id(id: String) -> int:
	var ref := find_by_id(id)
	if ref and ref.item_data:
		return max(1, ref.item_data.carry_stack)
	return 1
