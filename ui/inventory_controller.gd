class_name InventoryController
extends RefCounted

## Middle layer between Inventory (data) and InventoryWindow (UI).
## Owns all drag/split state and the rules for pick, place, split, and transfer.
## Subclass and override quick_transfer to implement panel-specific shift-click logic.

signal drag_changed
signal refresh_needed

var inv: Inventory = null

var picked_items:       Array[PhysicalItem] = []
var picked_data:        ItemData            = null
var split_button:       int                 = -1
var split_pending_slot: int                 = -1
var split_mode:         bool               = false
var split_slots:        Array[int]          = []
var lmb_placed:         Dictionary          = {}

# ── Pick / place ──────────────────────────────────────────────────────────────

func left_activate(idx: int) -> void:
	if not inv: return
	var slot := inv.get_slot(idx)
	if picked_items.is_empty():
		if not slot.is_empty():
			ItemTooltip.hide()
			var taken := inv.take_items(idx, slot.quantity)
			if not taken.is_empty():
				picked_items = taken
				picked_data  = picked_items[0].item_data
				for item in picked_items:
					if is_instance_valid(item): item.visible = false
				drag_changed.emit()
	else:
		if slot.is_empty() or slot.item_data.id == picked_data.id:
			picked_items = inv.place_items(idx, picked_items)
			if picked_items.is_empty(): picked_data = null
			drag_changed.emit()
		else:
			var swapped  := inv.take_items(idx, slot.quantity)
			var leftover := inv.place_items(idx, picked_items)
			picked_items = swapped
			picked_items.append_array(leftover)
			if not picked_items.is_empty():
				picked_data = picked_items[0].item_data
				for item in picked_items:
					if is_instance_valid(item): item.visible = false
			else:
				picked_data = null
			drag_changed.emit()
	refresh_needed.emit()


func right_activate(idx: int) -> void:
	if not inv: return
	var slot := inv.get_slot(idx)
	if picked_items.is_empty():
		if not slot.is_empty():
			ItemTooltip.hide()
			var taken := inv.take_items(idx, (slot.quantity + 1) / 2)
			if not taken.is_empty():
				picked_items = taken
				picked_data  = picked_items[0].item_data
				for item in picked_items:
					if is_instance_valid(item): item.visible = false
				drag_changed.emit()
	else:
		if (slot.is_empty() or slot.item_data.id == picked_data.id) and not slot.is_full():
			var one: Array[PhysicalItem] = [picked_items.pop_back()]
			var leftover := inv.place_items(idx, one)
			if not leftover.is_empty(): picked_items.append(leftover[0])
			if picked_items.is_empty(): picked_data = null
			drag_changed.emit()
	refresh_needed.emit()


## Picks up prime_slot (if nothing held) then collects all matching stacks.
func double_click_collect(prime_slot: int) -> void:
	if not inv: return
	if picked_items.is_empty():
		var src := inv.get_slot(prime_slot)
		if not src.is_empty():
			var taken := inv.take_items(prime_slot, src.quantity)
			for item in taken:
				if is_instance_valid(item): item.visible = false
			picked_items.append_array(taken)
			if not taken.is_empty():
				picked_data = taken[0].item_data
	if picked_items.is_empty() or picked_data == null:
		return
	var max_stack := picked_data.carry_stack
	for idx in inv.capacity:
		if picked_items.size() >= max_stack: break
		if idx == prime_slot: continue
		var slot := inv.get_slot(idx)
		if not slot.is_empty() and slot.item_data.id == picked_data.id:
			var taken := inv.take_items(idx, max_stack - picked_items.size())
			for item in taken:
				if is_instance_valid(item): item.visible = false
			picked_items.append_array(taken)
	drag_changed.emit()
	refresh_needed.emit()

# ── Drag-spread hover handlers ────────────────────────────────────────────────

func on_slot_enter_rmb(slot_idx: int) -> void:
	if split_slots.size() == 1 and not picked_items.is_empty():
		var init_slot := inv.get_slot(split_pending_slot)
		if (init_slot.is_empty() or init_slot.item_data.id == picked_data.id) and not init_slot.is_full():
			picked_items.append_array(inv.place_items(split_pending_slot,
				[picked_items.pop_back()] as Array[PhysicalItem]))
	if not picked_items.is_empty():
		var rs := inv.get_slot(slot_idx)
		if (rs.is_empty() or rs.item_data.id == picked_data.id) and not rs.is_full():
			picked_items.append_array(inv.place_items(slot_idx,
				[picked_items.pop_back()] as Array[PhysicalItem]))
	if picked_items.is_empty(): picked_data = null
	split_slots.append(slot_idx)
	drag_changed.emit()
	refresh_needed.emit()


func on_slot_enter_lmb(slot_idx: int) -> void:
	split_mode = true
	for s_idx in split_slots:
		var qty: int = lmb_placed.get(s_idx, 0)
		if qty > 0:
			picked_items.append_array(inv.take_items(s_idx, qty))
	lmb_placed.clear()
	var all_slots := split_slots.duplicate()
	all_slots.append(slot_idx)
	var per_slot := maxi(1, picked_items.size() / all_slots.size())
	for s_idx in all_slots:
		if picked_items.is_empty(): break
		var ls := inv.get_slot(s_idx)
		if ls.is_empty() or ls.item_data.id == picked_data.id:
			var n := mini(per_slot, picked_items.size())
			var to_place: Array[PhysicalItem] = []
			for _ii in n:
				if picked_items.is_empty(): break
				to_place.append(picked_items.pop_back())
			var leftover := inv.place_items(s_idx, to_place)
			picked_items.append_array(leftover)
			lmb_placed[s_idx] = to_place.size() - leftover.size()
	split_slots.append(slot_idx)
	if picked_items.is_empty() and per_slot == 1:
		picked_data = null
	drag_changed.emit()
	refresh_needed.emit()

# ── Split lifecycle ───────────────────────────────────────────────────────────

func clear_split() -> void:
	split_button       = -1
	split_pending_slot = -1
	split_mode         = false
	split_slots.clear()
	lmb_placed.clear()


func commit_split() -> void:
	if split_slots.is_empty() or picked_items.is_empty(): return
	if split_button != MOUSE_BUTTON_LEFT:
		for slot_idx in split_slots:
			if picked_items.is_empty(): break
			var slot := inv.get_slot(slot_idx)
			if (slot.is_empty() or slot.item_data.id == picked_data.id) and not slot.is_full():
				var leftover := inv.place_items(slot_idx, [picked_items.pop_back()] as Array[PhysicalItem])
				picked_items.append_array(leftover)
	if picked_items.is_empty(): picked_data = null
	drag_changed.emit()
	refresh_needed.emit()


func cancel_drag() -> void:
	clear_split()
	if not picked_items.is_empty() and inv:
		for item in picked_items:
			if is_instance_valid(item): inv.add(item)
		picked_items.clear()
		picked_data = null
	drag_changed.emit()

# ── Transfer rules (override in subclasses) ───────────────────────────────────

## Called on shift-click. Return any items that couldn't be transferred.
func quick_transfer(items: Array[PhysicalItem], _from_idx: int) -> Array[PhysicalItem]:
	return items
