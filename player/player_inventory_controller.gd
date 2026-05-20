class_name PlayerInventoryController
extends InventoryController

## Shift-click transfer rules for the player's inventory.
##
## Single-inventory mode (player_inv == null):
##   Main grid  → try hotbar first, then remaining main slots.
##   Hotbar     → try main grid.
##
## Dual-inventory mode (player_inv set, e.g. chest window):
##   External slot → try to fill player_inv.
##   Player slot   → try to fill inv (external).

func quick_transfer(items: Array[PhysicalItem], from_pos: int, from_inv: Inventory = null) -> Array[PhysicalItem]:
	if player_inv != null:
		# Dual mode: move to the OTHER inventory.
		if from_inv == player_inv:
			return _fill_into(inv, items)
		else:
			return _fill_into(player_inv, items)
	# Single mode: hotbar ↔ main within player inv.
	if from_pos < Inventory.MAIN_SLOTS:
		return _fill_hotbar(items)
	return _fill_main(items)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Fill [items] into [target], stacking first then using empty slots.
func _fill_into(target: Inventory, items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	if items.is_empty() or target == null:
		return items
	var rem: Array[PhysicalItem] = items.duplicate()
	var data := rem[0].item_data
	for i in target.capacity:
		if rem.is_empty(): return []
		var s := target.get_slot(i)
		if not s.is_empty() and s.item_data.id == data.id and not s.is_full():
			rem = target.place_items(i, rem)
	for i in target.capacity:
		if rem.is_empty(): return []
		if target.get_slot(i).is_empty():
			rem = target.place_items(i, rem)
	return rem

func _fill_hotbar(items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	var rem: Array[PhysicalItem] = items.duplicate()
	if rem.is_empty() or not inv: return rem
	var data := rem[0].item_data
	# Stack into matching hotbar slots first (active row preferred).
	for r in Inventory.HOTBAR_ROWS:
		var row := (inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if rem.is_empty(): return []
			var idx := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			var s := inv.get_slot(idx)
			if not s.is_empty() and s.item_data.id == data.id and not s.is_full():
				rem = inv.place_items(idx, rem)
	# Then empty hotbar slots.
	for r in Inventory.HOTBAR_ROWS:
		var row := (inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if rem.is_empty(): return []
			var idx := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			if inv.get_slot(idx).is_empty():
				rem = inv.place_items(idx, rem)
	return rem

func _fill_main(items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	var rem: Array[PhysicalItem] = items.duplicate()
	if rem.is_empty() or not inv: return rem
	var data := rem[0].item_data
	for i in Inventory.MAIN_SLOTS:
		if rem.is_empty(): return []
		var s := inv.get_slot(i)
		if not s.is_empty() and s.item_data.id == data.id and not s.is_full():
			rem = inv.place_items(i, rem)
	for i in Inventory.MAIN_SLOTS:
		if rem.is_empty(): return []
		if inv.get_slot(i).is_empty():
			rem = inv.place_items(i, rem)
	return rem
