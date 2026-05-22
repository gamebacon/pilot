class_name Inventory
extends Node

const COLS         := 8
const ROWS         := 3
const HOTBAR_COLS  := COLS
const HOTBAR_ROWS  := 1
const MAIN_SLOTS   := ROWS * COLS
const HOTBAR_SLOTS := HOTBAR_ROWS * HOTBAR_COLS
const TOTAL_SLOTS  := MAIN_SLOTS + HOTBAR_SLOTS

signal changed

var capacity: int = TOTAL_SLOTS   # kept for InventoryController compat
var active_hotbar_row: int = 0
var active_slot: int       = 0

var container_net_id: int = 0:
	set(v):
		container_net_id = v
		if is_inside_tree():
			if v != 0: add_to_group("synced_inventory")
			else:      remove_from_group("synced_inventory")

var _applying_remote: bool = false

# ── Slot ──────────────────────────────────────────────────────────────────────

class Slot:
	var item_id:   String       = ""
	var quantity:  int          = 0
	var durability: int         = -1
	var net_ids:   Array[int]   = []

	func is_empty() -> bool: return item_id.is_empty()

	func get_data() -> ItemData:
		if item_id.is_empty(): return null
		return ItemRegistry.get_item(item_id)

	func is_full() -> bool:
		if is_empty(): return false
		var d := get_data()
		return d != null and quantity >= d.carry_stack

	func can_add(iid: String) -> bool:
		return is_empty() or (item_id == iid and not is_full())

	func active_net_id() -> int:
		return net_ids[0] if not net_ids.is_empty() else 0

# ── DragStack — item(s) detached from any slot, used by drag-and-drop ─────────

class DragStack:
	var item_id:    String     = ""
	var quantity:   int        = 0
	var net_ids:    Array[int] = []
	var durability: int        = -1

	func is_empty() -> bool: return item_id.is_empty() or quantity <= 0

	func get_data() -> ItemData:
		if item_id.is_empty(): return null
		return ItemRegistry.get_item(item_id)

	## Remove one item from this stack and return it as a new DragStack of qty=1.
	func pop_one() -> DragStack:
		if is_empty(): return DragStack.new()
		var one      := DragStack.new()
		one.item_id   = item_id
		one.durability = durability
		one.quantity  = 1
		if not net_ids.is_empty():
			one.net_ids.append(net_ids.pop_back())
		quantity -= 1
		if quantity <= 0:
			item_id  = ""
			quantity = 0
			net_ids.clear()
		return one

	## Append another DragStack into this one (mutates self).
	func merge(other: DragStack) -> void:
		if other == null or other.is_empty(): return
		if is_empty():
			item_id    = other.item_id
			durability = other.durability
		quantity += other.quantity
		net_ids.append_array(other.net_ids)

	func duplicate_stack() -> DragStack:
		var d      := DragStack.new()
		d.item_id   = item_id
		d.quantity  = quantity
		d.net_ids   = net_ids.duplicate()
		d.durability = durability
		return d

# ── State ─────────────────────────────────────────────────────────────────────

var _slots: Array[Slot] = []

func _ready() -> void:
	_slots.resize(TOTAL_SLOTS)
	for i in TOTAL_SLOTS:
		_slots[i] = Slot.new()
	changed.connect(_on_net_changed)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _active_abs() -> int:
	return MAIN_SLOTS + active_hotbar_row * HOTBAR_COLS + active_slot

var active_index: int:
	get: return _active_abs()

# ── Active slot queries ───────────────────────────────────────────────────────

func active_slot_data() -> Slot:
	return _slots[_active_abs()]

func active_item_id() -> String:
	return _slots[_active_abs()].item_id

func active_net_id() -> int:
	return _slots[_active_abs()].active_net_id()

func active_durability() -> int:
	return _slots[_active_abs()].durability

# ── General queries ───────────────────────────────────────────────────────────

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
		if s.item_id == id: return true
	return false

func count_id(id: String) -> int:
	var n := 0
	for s in _slots:
		if s.item_id == id: n += s.quantity
	return n

func total_mass() -> float:
	var m := 0.0
	for s in _slots:
		if s.is_empty(): continue
		var d := s.get_data()
		if d: m += d.mass * s.quantity
	return m

func used_slots() -> int:
	var n := 0
	for s in _slots:
		if not s.is_empty(): n += 1
	return n

func occupied_hotbar_slots() -> int:
	var n := 0
	for i in HOTBAR_SLOTS:
		if not _slots[MAIN_SLOTS + i].is_empty(): n += 1
	return n

func size() -> int:
	var n := 0
	for s in _slots: n += s.quantity
	return n

# ── Mutations ─────────────────────────────────────────────────────────────────

## Add one item by data. Returns true if it fit, false if inventory was full.
func add(item_id: String, net_id: int = 0, durability: int = -1) -> bool:
	# 1. Stack into existing hotbar
	for r in HOTBAR_ROWS:
		for c in HOTBAR_COLS:
			var s := _slots[MAIN_SLOTS + r * HOTBAR_COLS + c]
			if not s.is_empty() and s.can_add(item_id):
				_slot_add(s, item_id, net_id, durability)
				changed.emit(); return true
	# 2. Stack into existing main
	for i in MAIN_SLOTS:
		if not _slots[i].is_empty() and _slots[i].can_add(item_id):
			_slot_add(_slots[i], item_id, net_id, durability)
			changed.emit(); return true
	# 3. Empty hotbar (prefer active row)
	for r in HOTBAR_ROWS:
		var row := (active_hotbar_row + r) % HOTBAR_ROWS
		for c in HOTBAR_COLS:
			var s := _slots[MAIN_SLOTS + row * HOTBAR_COLS + c]
			if s.is_empty():
				_slot_add(s, item_id, net_id, durability)
				changed.emit(); return true
	# 4. Empty main
	for i in MAIN_SLOTS:
		if _slots[i].is_empty():
			_slot_add(_slots[i], item_id, net_id, durability)
			changed.emit(); return true
	return false

func _slot_add(s: Slot, item_id: String, net_id: int, durability: int) -> void:
	s.item_id   = item_id
	s.quantity  += 1
	s.net_ids.append(net_id)
	if durability >= 0: s.durability = durability

## Remove one item from the active slot. Returns a DragStack (may be empty).
func remove_active_one() -> DragStack:
	var drag: DragStack = _take_one_from(_slots[_active_abs()])
	if not drag.is_empty(): changed.emit()
	return drag

## Remove one item matching [id] from any slot. Returns a DragStack (may be empty).
func remove_one_by_id(id: String) -> DragStack:
	for s in _slots:
		if s.item_id == id:
			var drag: DragStack = _take_one_from(s)
			if not drag.is_empty(): changed.emit()
			return drag
	return DragStack.new()

func _take_one_from(s: Slot) -> DragStack:
	if s.is_empty(): return DragStack.new()
	var drag      := DragStack.new()
	drag.item_id   = s.item_id
	drag.durability = s.durability
	drag.quantity  = 1
	if not s.net_ids.is_empty():
		drag.net_ids.append(s.net_ids.pop_back())
	s.quantity -= 1
	if s.quantity <= 0:
		s.item_id    = ""
		s.quantity   = 0
		s.durability = -1
		s.net_ids.clear()
	return drag

## Take up to [qty] items from slot [idx]. Returns a DragStack.
func take_items(idx: int, qty: int) -> DragStack:
	var s := _slots[idx]
	if s.is_empty() or qty <= 0: return DragStack.new()
	var n    := mini(qty, s.quantity)
	var drag := DragStack.new()
	drag.item_id    = s.item_id
	drag.durability = s.durability
	for _i in n:
		drag.quantity += 1
		drag.net_ids.append(s.net_ids.pop_back() if not s.net_ids.is_empty() else 0)
	s.quantity -= n
	if s.quantity <= 0:
		s.item_id    = ""
		s.quantity   = 0
		s.durability = -1
		s.net_ids.clear()
	changed.emit()
	return drag

## Place a DragStack into slot [idx]. Returns any leftover as a DragStack.
func place_items(idx: int, drag: DragStack) -> DragStack:
	if drag == null or drag.is_empty(): return DragStack.new()
	var s := _slots[idx]
	if not s.is_empty() and s.item_id != drag.item_id:
		return drag.duplicate_stack()
	var data := ItemRegistry.get_item(drag.item_id)
	var cap  := data.carry_stack if data else 1
	var placed := 0
	for i in drag.quantity:
		if s.quantity >= cap: break
		s.item_id   = drag.item_id
		s.quantity  += 1
		s.net_ids.append(drag.net_ids[i] if i < drag.net_ids.size() else 0)
		if drag.durability >= 0: s.durability = drag.durability
		placed += 1
	if placed > 0: changed.emit()
	if placed == drag.quantity: return DragStack.new()
	var leftover      := DragStack.new()
	leftover.item_id   = drag.item_id
	leftover.durability = drag.durability
	for i in range(placed, drag.quantity):
		leftover.quantity += 1
		if i < drag.net_ids.size(): leftover.net_ids.append(drag.net_ids[i])
	return leftover

## Add all items in a DragStack back to inventory using normal priority.
func add_drag(drag) -> void:   # drag: DragStack
	if drag == null or drag.is_empty(): return
	for i in drag.quantity:
		var nid: int = drag.net_ids[i] if i < drag.net_ids.size() else 0
		add(drag.item_id, nid, drag.durability)

## Decrement durability of the active slot. Returns true when the tool breaks.
func use_active_durability(amount: int = 1) -> bool:
	var s := _slots[_active_abs()]
	if s.durability < 0: return false
	s.durability -= amount
	if s.durability <= 0: s.durability = 0
	changed.emit()
	return s.durability <= 0

func swap_slots(a: int, b: int) -> void:
	if a == b: return
	var tmp  := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
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
	return _slots[r * COLS + c]

# ── Multiplayer container sync ────────────────────────────────────────────────

func _on_net_changed() -> void:
	if _applying_remote or not NetworkManager.is_active() or container_net_id == 0:
		return
	if not multiplayer.is_server(): return
	var world := get_tree().get_first_node_in_group("world")
	if not world: return
	world.sync_inventory_state(container_net_id, _net_encode())

func _net_encode() -> Array:
	var data := []
	for s in _slots:
		if s.is_empty():
			data.append(["", 0, [], -1])
		else:
			data.append([s.item_id, s.quantity, s.net_ids.duplicate(), s.durability])
	return data

func apply_remote_state(slots_data: Array) -> void:
	_applying_remote = true
	for i in _slots.size():
		_slots[i] = Slot.new()
	for i in mini(slots_data.size(), _slots.size()):
		var entry: Array = slots_data[i]
		if entry.size() < 4: continue
		var iid: String = entry[0]
		if iid.is_empty(): continue
		var s      := _slots[i]
		s.item_id   = iid
		s.quantity  = entry[1]
		s.durability = entry[3]
		for nid in entry[2]:
			s.net_ids.append(int(nid))
	changed.emit()
	_applying_remote = false
