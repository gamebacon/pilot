class_name ChestInventoryController
extends PlayerInventoryController

## Intercepts take/place calls on the chest inventory (inv) and routes them
## through the server. Player-inventory slots pass through unchanged.
## Optimistic local apply gives immediate visual feedback; chest_take_denied
## cancels the drag if the server rejects a take (concurrent race).

var chest_net_id: int = 0

func _is_chest(sv: Inventory) -> bool:
	return sv == inv and NetworkManager.is_active() and not _server()

func _server() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree == null or tree.root.multiplayer.is_server()

func _world() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("world") if tree else null

# ── Overrides ─────────────────────────────────────────────────────────────────

func _take_from(sv: Inventory, si: int, qty: int) -> Inventory.DragStack:
	if not _is_chest(sv):
		return sv.take_items(si, qty)
	var taken: Inventory.DragStack = sv.take_items(si, qty)
	if not taken.is_empty():
		var w := _world()
		if w: w.request_chest_take(chest_net_id, si, qty)
	return taken

func _place_into(sv: Inventory, si: int, d: Inventory.DragStack) -> Inventory.DragStack:
	if not _is_chest(sv):
		return sv.place_items(si, d)
	var leftover: Inventory.DragStack = sv.place_items(si, d)
	var qty_placed := d.quantity - (leftover.quantity if leftover and not leftover.is_empty() else 0)
	if qty_placed > 0:
		var w := _world()
		if w:
			w.request_chest_place(chest_net_id, si, d.item_id, qty_placed,
					d.net_ids.slice(0, qty_placed), d.durability)
	return leftover

func quick_transfer(stack: Inventory.DragStack, from_pos: int,
		from_inv: Inventory = null) -> Inventory.DragStack:
	# Shift-click FROM player inv → chest: must route each placement through server.
	if player_inv != null and from_inv == player_inv and _is_chest(inv):
		return _fill_into_chest(stack)
	return super.quick_transfer(stack, from_pos, from_inv)

func _fill_into_chest(stack: Inventory.DragStack) -> Inventory.DragStack:
	var remainder: Inventory.DragStack = stack.duplicate_stack()
	for i in inv.capacity:
		if remainder.is_empty(): return Inventory.DragStack.new()
		var slot := inv.get_slot(i)
		if not slot.is_empty() and slot.item_id == remainder.item_id and not slot.is_full():
			remainder = _place_into(inv, i, remainder)
	for i in inv.capacity:
		if remainder.is_empty(): return Inventory.DragStack.new()
		if inv.get_slot(i).is_empty():
			remainder = _place_into(inv, i, remainder)
	return remainder

func shift_click_transfer(sv: Inventory, si: int, qty: int, from_pos: int) -> void:
	if not _is_chest(sv):
		super.shift_click_transfer(sv, si, qty, from_pos)
		return
	var taken: Inventory.DragStack = _take_from(sv, si, qty)
	if taken.is_empty(): return
	var leftover: Inventory.DragStack = quick_transfer(taken, from_pos, sv)
	if leftover and not leftover.is_empty():
		# Return excess to the chest via server (player inventory was full).
		var w := _world()
		if w:
			w.request_chest_place(chest_net_id, si, leftover.item_id,
					leftover.quantity, leftover.net_ids, leftover.durability)

# ── Called by ChestUI when the server denies the take ─────────────────────────

func on_take_denied() -> void:
	drag = null
	drag_changed.emit()
	needs_refresh.emit()
