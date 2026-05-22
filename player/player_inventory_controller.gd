class_name PlayerInventoryController
extends InventoryController

## Shift-click transfer for the player inventory.
##
## Dual mode (player_inv set, e.g. chest):
##   External slot → fill player_inv.
##   Player slot   → fill inv (external).
##
## Single mode (player_inv == null):
##   Main grid ↔ hotbar within inv.

func quick_transfer(stack: Inventory.DragStack, from_pos: int,
		from_inv: Inventory = null) -> Inventory.DragStack:
	if player_inv != null:
		# Shift-click from player_inv → push into external inv, and vice versa.
		return _fill_into(inv if from_inv == player_inv else player_inv, stack)
	if from_pos < Inventory.MAIN_SLOTS:
		return _fill_hotbar(stack)
	return _fill_main(stack)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _fill_into(target: Inventory, stack: Inventory.DragStack) -> Inventory.DragStack:
	if stack == null or stack.is_empty() or target == null:
		return stack
	var remainder: Inventory.DragStack = stack.duplicate_stack()
	for i in target.capacity:
		if remainder.is_empty(): return Inventory.DragStack.new()
		var slot := target.get_slot(i)
		if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
			remainder = target.place_items(i, remainder)
	for i in target.capacity:
		if remainder.is_empty(): return Inventory.DragStack.new()
		if target.get_slot(i).is_empty():
			remainder = target.place_items(i, remainder)
	return remainder

func _fill_hotbar(stack: Inventory.DragStack) -> Inventory.DragStack:
	if stack == null or stack.is_empty() or not inv:
		return stack
	var remainder: Inventory.DragStack = stack.duplicate_stack()
	for r in Inventory.HOTBAR_ROWS:
		var row := (inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if remainder.is_empty(): return Inventory.DragStack.new()
			var idx  := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			var slot := inv.get_slot(idx)
			if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
				remainder = inv.place_items(idx, remainder)
	for r in Inventory.HOTBAR_ROWS:
		var row := (inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if remainder.is_empty(): return Inventory.DragStack.new()
			var idx := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			if inv.get_slot(idx).is_empty():
				remainder = inv.place_items(idx, remainder)
	return remainder

func _fill_main(stack: Inventory.DragStack) -> Inventory.DragStack:
	if stack == null or stack.is_empty() or not inv:
		return stack
	var remainder: Inventory.DragStack = stack.duplicate_stack()
	for i in Inventory.MAIN_SLOTS:
		if remainder.is_empty(): return Inventory.DragStack.new()
		var slot := inv.get_slot(i)
		if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
			remainder = inv.place_items(i, remainder)
	for i in Inventory.MAIN_SLOTS:
		if remainder.is_empty(): return Inventory.DragStack.new()
		if inv.get_slot(i).is_empty():
			remainder = inv.place_items(i, remainder)
	return remainder
