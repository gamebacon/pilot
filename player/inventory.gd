class_name Inventory
extends Node

const MAIN_COLS   := 5
const HOTBAR_COLS := 5
const COLS        := HOTBAR_COLS   # backward-compat alias used by cycle functions
const MAIN_ROWS   := 3
const HOTBAR_ROWS := 1
const MAIN_SLOTS  := MAIN_ROWS   * MAIN_COLS    # 24
const HOTBAR_SLOTS := HOTBAR_ROWS * HOTBAR_COLS  # 15
const TOTAL_SLOTS := MAIN_SLOTS + HOTBAR_SLOTS   # 39

signal changed

var capacity: int = TOTAL_SLOTS   # backward compat
var active_hotbar_row: int = 0
var active_slot: int       = 0

# ── Slot ──────────────────────────────────────────────────────────────────────
class Slot:
	var item_data: ItemData        = null
	var quantity:  int             = 0
	var physical:  Array[PhysicalItem] = []

	func is_empty() -> bool: return item_data == null
	func is_full()  -> bool: return item_data != null and quantity >= item_data.carry_stack

	func can_stack(item: PhysicalItem) -> bool:
		return not is_empty() and item.item_data != null \
			and item_data.id == item.item_data.id and not is_full()

	func add(item: PhysicalItem) -> void:
		if is_empty(): item_data = item.item_data
		quantity += 1
		physical.append(item)

	func remove_one() -> PhysicalItem:
		if physical.is_empty(): return null
		var it: PhysicalItem = physical.pop_back()
		quantity -= 1
		if quantity <= 0: item_data = null; quantity = 0
		return it

	func erase(item: PhysicalItem) -> bool:
		if not physical.has(item): return false
		physical.erase(item)
		quantity -= 1
		if quantity <= 0: item_data = null; quantity = 0
		return true

# ── State ─────────────────────────────────────────────────────────────────────
var _slots: Array[Slot] = []

func _ready() -> void:
	_slots.resize(TOTAL_SLOTS)
	for i in TOTAL_SLOTS:
		_slots[i] = Slot.new()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _active_abs() -> int:
	return MAIN_SLOTS + active_hotbar_row * HOTBAR_COLS + active_slot

var active_index: int:   # backward compat
	get: return _active_abs()

# ── Active ────────────────────────────────────────────────────────────────────
func active() -> PhysicalItem:
	var s := _slots[_active_abs()]
	return s.physical[0] if not s.is_empty() else null

# ── Queries ───────────────────────────────────────────────────────────────────
var items: Array[PhysicalItem]:
	get:
		var r: Array[PhysicalItem] = []
		for s in _slots: r.append_array(s.physical)
		return r

func is_full() -> bool:
	if GameState.debug_mode: return false
	for s in _slots:
		if s.is_empty(): return false
	return true

func is_empty() -> bool:
	for s in _slots:
		if not s.is_empty(): return false
	return true

func has_id(id: String) -> bool:
	for s in _slots:
		if s.item_data and s.item_data.id == id: return true
	return false

func find_by_id(id: String) -> PhysicalItem:
	for s in _slots:
		if s.item_data and s.item_data.id == id and not s.physical.is_empty():
			return s.physical[0]
	return null

func last() -> PhysicalItem:
	for i in range(_slots.size() - 1, -1, -1):
		if not _slots[i].physical.is_empty():
			return _slots[i].physical[_slots[i].physical.size() - 1]
	return null

func size() -> int:
	var n := 0
	for s in _slots: n += s.quantity
	return n

func used_slots() -> int:
	var n := 0
	for s in _slots:
		if not s.is_empty(): n += 1
	return n

func has_multiple_types() -> bool:
	var first := ""
	for s in _slots:
		if s.item_data:
			if first.is_empty(): first = s.item_data.id
			elif s.item_data.id != first: return true
	return false

func slot_for(item: PhysicalItem) -> int:
	for i in _slots.size():
		if _slots[i].physical.has(item): return i
	return 0

# ── Mutations ─────────────────────────────────────────────────────────────────
func add(item: PhysicalItem) -> void:
	# 1. Stack into existing hotbar slot
	for r in HOTBAR_ROWS:
		for c in HOTBAR_COLS:
			var s := _slots[MAIN_SLOTS + r * HOTBAR_COLS + c]
			if s.can_stack(item): s.add(item); changed.emit(); return
	# 2. Stack into existing main slot
	for i in MAIN_SLOTS:
		if _slots[i].can_stack(item): _slots[i].add(item); changed.emit(); return
	# 3. Empty hotbar slot (prefer active row)
	for r in HOTBAR_ROWS:
		var row := (active_hotbar_row + r) % HOTBAR_ROWS
		for c in HOTBAR_COLS:
			var s := _slots[MAIN_SLOTS + row * HOTBAR_COLS + c]
			if s.is_empty(): s.add(item); changed.emit(); return
	# 4. Empty main slot
	for i in MAIN_SLOTS:
		if _slots[i].is_empty(): _slots[i].add(item); changed.emit(); return

func remove(item: PhysicalItem) -> void:
	for s in _slots:
		if s.erase(item): changed.emit(); return

func remove_active_one() -> PhysicalItem:
	var it := _slots[_active_abs()].remove_one()
	if it: changed.emit()
	return it

func remove_by_id(id: String) -> PhysicalItem:
	for s in _slots:
		if s.item_data and s.item_data.id == id:
			var it := s.remove_one()
			if it: changed.emit()
			return it
	return null

## Remove up to [qty] items from slot [idx] and return them.
## The slot's quantity and item_data are updated. Emits changed.
func take_items(idx: int, qty: int) -> Array[PhysicalItem]:
	var slot := _slots[idx]
	if slot.is_empty() or qty <= 0:
		return []
	var taken: Array[PhysicalItem] = []
	var n := mini(qty, slot.quantity)
	for _i in n:
		var it: PhysicalItem = slot.physical.pop_back()
		slot.quantity -= 1
		taken.append(it)
	if slot.quantity <= 0:
		slot.item_data = null
		slot.quantity  = 0
	changed.emit()
	return taken

## Place [items] into slot [idx]. Returns items that couldn't fit (full or type mismatch).
func place_items(idx: int, items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	if items.is_empty():
		return []
	var data := items[0].item_data
	var slot := _slots[idx]
	if not slot.is_empty() and slot.item_data.id != data.id:
		var ret: Array[PhysicalItem] = []
		ret.append_array(items)
		return ret
	var placed := false
	var leftover: Array[PhysicalItem] = []
	for item in items:
		if not slot.is_full():
			slot.add(item)
			placed = true
		else:
			leftover.append(item)
	if placed:
		changed.emit()
	return leftover

func swap_slots(a: int, b: int) -> void:
	if a == b: return
	var td := _slots[a].item_data
	var tq := _slots[a].quantity
	var tp: Array[PhysicalItem] = _slots[a].physical.duplicate()
	_slots[a].item_data = _slots[b].item_data
	_slots[a].quantity  = _slots[b].quantity
	_slots[a].physical  = _slots[b].physical.duplicate()
	_slots[b].item_data = td
	_slots[b].quantity  = tq
	_slots[b].physical  = tp
	changed.emit()

# ── Navigation ────────────────────────────────────────────────────────────────
func cycle_next() -> void:
	active_slot = (active_slot + 1) % HOTBAR_COLS; changed.emit()

func cycle_prev() -> void:
	active_slot = (active_slot - 1 + HOTBAR_COLS) % HOTBAR_COLS; changed.emit()

func next_hotbar_row() -> void:
	active_hotbar_row = (active_hotbar_row + 1) % HOTBAR_ROWS; changed.emit()

func prev_hotbar_row() -> void:
	active_hotbar_row = (active_hotbar_row - 1 + HOTBAR_ROWS) % HOTBAR_ROWS; changed.emit()

func set_active_hotbar_slot(col: int) -> void:
	active_slot = clamp(col, 0, HOTBAR_COLS - 1); changed.emit()

func set_active_hotbar_row(row: int) -> void:
	active_hotbar_row = clamp(row, 0, HOTBAR_ROWS - 1); changed.emit()

# ── Slot access ───────────────────────────────────────────────────────────────
func get_slot(idx: int) -> Slot:
	return _slots[idx]

func get_hotbar_slot(r: int, c: int) -> Slot:
	return _slots[MAIN_SLOTS + r * HOTBAR_COLS + c]

func get_main_slot(r: int, c: int) -> Slot:
	return _slots[r * MAIN_COLS + c]
