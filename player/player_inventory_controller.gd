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

func quick_transfer(stack: Inventory.ItemStack, from_pos: int,
		from_inv: Inventory = null) -> Inventory.ItemStack:
	if player_inv != null:
		# Shift-click from player_inv → push into external inv, and vice versa.
		return _fill_into(inv if from_inv == player_inv else player_inv, stack)
	if from_pos < inv.main_slots:
		return _fill_hotbar(stack)
	return _fill_main(stack)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _fill_into(target: Inventory, stack: Inventory.ItemStack) -> Inventory.ItemStack:
	if stack == null or stack.is_empty() or target == null:
		return stack
	var remainder: Inventory.ItemStack = stack.duplicate_stack()
	for i in target.capacity:
		if remainder.is_empty(): return Inventory.ItemStack.new()
		var slot := target.get_slot(i)
		if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
			remainder = target.place_items(i, remainder)
	for i in target.capacity:
		if remainder.is_empty(): return Inventory.ItemStack.new()
		if target.get_slot(i).is_empty():
			remainder = target.place_items(i, remainder)
	return remainder

func _fill_hotbar(stack: Inventory.ItemStack) -> Inventory.ItemStack:
	if stack == null or stack.is_empty() or not inv:
		return stack
	var remainder: Inventory.ItemStack = stack.duplicate_stack()
	for r in inv.hotbar_rows:
		var row := (inv.active_hotbar_row + r) % inv.hotbar_rows
		for c in inv.hotbar_cols:
			if remainder.is_empty(): return Inventory.ItemStack.new()
			var idx  := inv.main_slots + row * inv.hotbar_cols + c
			var slot := inv.get_slot(idx)
			if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
				remainder = inv.place_items(idx, remainder)
	for r in inv.hotbar_rows:
		var row := (inv.active_hotbar_row + r) % inv.hotbar_rows
		for c in inv.hotbar_cols:
			if remainder.is_empty(): return Inventory.ItemStack.new()
			var idx := inv.main_slots + row * inv.hotbar_cols + c
			if inv.get_slot(idx).is_empty():
				remainder = inv.place_items(idx, remainder)
	return remainder

func _fill_main(stack: Inventory.ItemStack) -> Inventory.ItemStack:
	if stack == null or stack.is_empty() or not inv:
		return stack
	var remainder: Inventory.ItemStack = stack.duplicate_stack()
	for i in inv.main_slots:
		if remainder.is_empty(): return Inventory.ItemStack.new()
		var slot := inv.get_slot(i)
		if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
			remainder = inv.place_items(i, remainder)
	for i in inv.main_slots:
		if remainder.is_empty(): return Inventory.ItemStack.new()
		if inv.get_slot(i).is_empty():
			remainder = inv.place_items(i, remainder)
	return remainder
