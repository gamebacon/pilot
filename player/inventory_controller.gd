class_name InventoryController
extends RefCounted

## Middle layer between InventoryWindow (UI) and Inventory (data).
## Owns all slot interaction state: drag, split, activate, double-click collect.
## InventoryWindow wires GUI events here and listens to signals for visual updates.

signal drag_changed   # drag state changed — update drag visual
signal needs_refresh  # slot data changed — repaint slot widgets
signal cursor_moved   # controller cursor moved — repaint + tooltip

var inv:        Inventory = null
var player_inv: Inventory = null
var external_slot_count: int = 0

# ── Controller cursor ─────────────────────────────────────────────────────────

var cursor:   int = 0
var nav_rows: int = 0   # 0 = grid nav disabled (e.g. CraftingUI uses its own nav)
var nav_cols: int = 8   # default Inventory.COLS; set before opening if different

func navigate(dx: int, dy: int) -> void:
	if nav_rows == 0: return
	var col: int = cursor % nav_cols
	var row: int = cursor / nav_cols
	col    = (col + dx + nav_cols) % nav_cols
	row    = clamp(row + dy, 0, nav_rows - 1)
	cursor = row * nav_cols + col
	cursor_moved.emit()

func reset_cursor() -> void:
	cursor = 0
	cursor_moved.emit()

# ── Drag state ────────────────────────────────────────────────────────────────

var drag: Inventory.DragStack = null

const DCLICK_MS     := 250
var last_click_slot := -1
var last_click_msec := 0

var split_button:       int        = -1
var split_pending_slot: int        = -1
var split_mode:         bool       = false
var split_slots:        Array[int] = []
var lmb_placed:         Dictionary = {}   # slot_idx -> qty placed during live LMB drag

var hovered_slot: int = -1

# ── Slot routing ──────────────────────────────────────────────────────────────

func sinv(pos: int) -> Inventory:
	if player_inv != null and pos >= external_slot_count:
		return player_inv
	return inv

func sidx(pos: int) -> int:
	if player_inv != null and pos >= external_slot_count:
		return pos - external_slot_count
	return pos

# ── Inventory mutation virtuals ───────────────────────────────────────────────
# Subclasses (e.g. ChestInventoryController) override these to intercept mutations.

func _take_from(sv: Inventory, si: int, qty: int) -> Inventory.DragStack:
	return sv.take_items(si, qty)

func _place_into(sv: Inventory, si: int, d: Inventory.DragStack) -> Inventory.DragStack:
	return sv.place_items(si, d)

func shift_click_transfer(sv: Inventory, si: int, qty: int, from_pos: int) -> void:
	var taken    := _take_from(sv, si, qty)
	var leftover := quick_transfer(taken, from_pos, sv)
	sv.add_drag(leftover)

# ── Permission virtuals ───────────────────────────────────────────────────────

func can_insert(_pos: int, _item_data: ItemData) -> bool:
	return true

func can_take(_pos: int) -> bool:
	return true

## Shift-click handler. Returns leftover DragStack.
func quick_transfer(stack: Inventory.DragStack, _from_pos: int,
		_from_inv: Inventory = null) -> Inventory.DragStack:
	return stack

# ── Drag helpers ──────────────────────────────────────────────────────────────

func clear_split() -> void:
	split_button = -1; split_pending_slot = -1
	split_mode   = false
	split_slots.clear(); lmb_placed.clear()

func cancel_drag() -> void:
	clear_split()
	if drag and not drag.is_empty():
		var fallback := player_inv if player_inv != null else inv
		if fallback: fallback.add_drag(drag)
	drag = null
	drag_changed.emit()

func drop_one(player: Player) -> void:
	clear_split()
	if drag == null or drag.is_empty(): return
	var one: Inventory.DragStack = drag.pop_one()
	if not one.is_empty() and player:
		var nid := one.net_ids[0] if not one.net_ids.is_empty() else 0
		player.drop_item_data(one.item_id, nid, one.durability)
	if drag == null or drag.is_empty(): drag = null
	drag_changed.emit()
	needs_refresh.emit()

func drop_all(player: Player) -> void:
	clear_split()
	if drag == null or drag.is_empty(): return
	while drag and not drag.is_empty():
		var one: Inventory.DragStack = drag.pop_one()
		if player:
			var nid := one.net_ids[0] if not one.net_ids.is_empty() else 0
			player.drop_item_data(one.item_id, nid, one.durability)
	drag = null
	drag_changed.emit()
	needs_refresh.emit()

# ── Slot interactions ─────────────────────────────────────────────────────────

func left_activate(pos: int) -> void:
	var sv := sinv(pos)
	var si := sidx(pos)
	if not sv: return
	var slot := sv.get_slot(si)

	if drag == null or drag.is_empty():
		if not slot.is_empty() and can_take(pos):
			drag = _take_from(sv, si, slot.quantity) as Inventory.DragStack
	else:
		if slot.is_empty() or slot.item_id == drag.item_id:
			if can_insert(pos, drag.get_data()):
				var leftover: Inventory.DragStack = _place_into(sv, si, drag)
				drag = leftover if not leftover.is_empty() else null
		elif can_take(pos) and can_insert(pos, drag.get_data()):
			var swapped:  Inventory.DragStack = _take_from(sv, si, slot.quantity)
			var leftover: Inventory.DragStack = _place_into(sv, si, drag)
			swapped.merge(leftover)
			drag = swapped if not swapped.is_empty() else null

	if drag == null or drag.is_empty(): drag = null
	drag_changed.emit()
	needs_refresh.emit()

func right_activate(pos: int) -> void:
	var sv := sinv(pos)
	var si := sidx(pos)
	if not sv: return
	var slot := sv.get_slot(si)

	if drag == null or drag.is_empty():
		if not slot.is_empty() and can_take(pos):
			drag = _take_from(sv, si, (slot.quantity + 1) / 2) as Inventory.DragStack
	else:
		if not slot.is_full() and (slot.is_empty() or slot.item_id == drag.item_id) \
				and can_insert(pos, drag.get_data()):
			var one:      Inventory.DragStack = drag.pop_one()
			var leftover: Inventory.DragStack = _place_into(sv, si, one)
			drag.merge(leftover)
			if drag == null or drag.is_empty(): drag = null

	drag_changed.emit()
	needs_refresh.emit()

func double_click_collect(item_id: String, total_slots: int) -> void:
	if item_id.is_empty(): return
	var data := ItemRegistry.get_item(item_id)
	if not data: return
	var max_stack := data.carry_stack
	for pos in total_slots:
		if drag and drag.quantity >= max_stack: break
		var sv := sinv(pos)
		if not sv: continue
		var slot := sv.get_slot(sidx(pos))
		if not slot.is_empty() and slot.item_id == item_id:
			var n                          := max_stack - (drag.quantity if drag else 0)
			var taken: Inventory.DragStack  = _take_from(sv, sidx(pos), n)
			if drag == null: drag = taken
			else: drag.merge(taken)
	drag_changed.emit()
	needs_refresh.emit()

func on_slot_enter(pos: int) -> void:
	hovered_slot = pos
	var rmb_drag := drag != null and not drag.is_empty() \
			and split_button == MOUSE_BUTTON_RIGHT \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not split_slots.has(pos)
	var lmb_drag := split_button == MOUSE_BUTTON_LEFT \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not split_slots.has(pos) \
			and drag != null \
			and (not drag.is_empty() or not lmb_placed.is_empty())

	if rmb_drag:
		var drag_data := drag.get_data()
		if split_slots.size() == 1 and not drag.is_empty():
			var ps    := split_pending_slot
			var psinv := sinv(ps)
			var init  := psinv.get_slot(sidx(ps))
			if (init.is_empty() or init.item_id == drag.item_id) \
					and not init.is_full() and can_insert(ps, drag_data):
				var one: Inventory.DragStack = drag.pop_one()
				drag.merge(_place_into(psinv, sidx(ps), one))
		if not drag.is_empty():
			var rsinv := sinv(pos)
			var rs    := rsinv.get_slot(sidx(pos))
			if (rs.is_empty() or rs.item_id == drag.item_id) \
					and not rs.is_full() and can_insert(pos, drag_data):
				var one: Inventory.DragStack = drag.pop_one()
				drag.merge(_place_into(rsinv, sidx(pos), one))
		if drag == null or drag.is_empty(): drag = null
		drag_changed.emit()
		needs_refresh.emit()
		split_slots.append(pos)

	elif lmb_drag:
		split_mode = true
		for slot_pos in split_slots:
			var qty: int = lmb_placed.get(slot_pos, 0)
			if qty > 0:
				var reclaimed: Inventory.DragStack = _take_from(sinv(slot_pos), sidx(slot_pos), qty)
				if drag == null: drag = reclaimed
				else: drag.merge(reclaimed)
		lmb_placed.clear()
		var all_slots := split_slots.duplicate()
		all_slots.append(pos)
		var per_slot := maxi(1, drag.quantity / all_slots.size())
		for slot_pos in all_slots:
			if drag.is_empty(): break
			var lsinv := sinv(slot_pos)
			var ls    := lsinv.get_slot(sidx(slot_pos))
			if (ls.is_empty() or ls.item_id == drag.item_id) \
					and can_insert(slot_pos, drag.get_data()):
				var n := mini(per_slot, drag.quantity)
				var chunk := Inventory.DragStack.new()
				chunk.item_id    = drag.item_id
				chunk.durability = drag.durability
				for _ii in n:
					if drag.is_empty(): break
					chunk.quantity += 1
					chunk.net_ids.append(drag.net_ids.pop_back() if not drag.net_ids.is_empty() else 0)
					drag.quantity -= 1
				var leftover: Inventory.DragStack = _place_into(lsinv, sidx(slot_pos), chunk)
				drag.merge(leftover)
				lmb_placed[slot_pos] = chunk.quantity - leftover.quantity
		split_slots.append(pos)
		if (drag == null or drag.is_empty()) and per_slot == 1:
			drag = null
			clear_split()
		drag_changed.emit()
		needs_refresh.emit()

func commit_split() -> void:
	if split_slots.is_empty() or drag == null or drag.is_empty(): return
	if split_button != MOUSE_BUTTON_LEFT:
		for slot_pos in split_slots:
			if drag.is_empty(): break
			var sv   := sinv(slot_pos)
			var slot := sv.get_slot(sidx(slot_pos))
			if (slot.is_empty() or slot.item_id == drag.item_id) \
					and not slot.is_full() and can_insert(slot_pos, drag.get_data()):
				var one:      Inventory.DragStack = drag.pop_one()
				var leftover: Inventory.DragStack = _place_into(sv, sidx(slot_pos), one)
				drag.merge(leftover)
	if drag == null or drag.is_empty(): drag = null
	drag_changed.emit()
	needs_refresh.emit()
