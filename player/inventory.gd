class_name Inventory
extends Node

## Default layout — player inventory. Other inventories override via @export.
const COLS         := 8
const ROWS         := 3
const HOTBAR_COLS  := COLS
const HOTBAR_ROWS  := 1
const MAIN_SLOTS   := ROWS * COLS
const HOTBAR_SLOTS := HOTBAR_ROWS * HOTBAR_COLS
const TOTAL_SLOTS  := MAIN_SLOTS + HOTBAR_SLOTS

signal changed

## Per-instance layout — set via inspector for scene-based nodes, or assign
## before add_child() for programmatic inventories. Derived values are computed
## in _ready().
@export var cols:        int = COLS
@export var rows:        int = ROWS
@export var hotbar_cols: int = HOTBAR_COLS
@export var hotbar_rows: int = HOTBAR_ROWS

## Derived — read-only after _ready().
var main_slots:   int
var hotbar_slots: int
var total_slots:  int
var capacity:     int   # alias for total_slots, kept for InventoryController compat

var active_hotbar_row: int = 0
var active_slot:       int = 0

var container_net_id: int = 0:
	set(v):
		container_net_id = v
		if is_inside_tree():
			if v != 0: add_to_group("synced_inventory")
			else:      remove_from_group("synced_inventory")

var _applying_remote: bool = false

# ── ItemStack ─────────────────────────────────────────────────────────────────
## Unified type for both slot storage and drag-and-drop state.
## Per-instance data (durability, quality, enchantments, etc.) lives in
## [metadata] so new properties never require field additions here.

class ItemStack:
	var item_id:  String     = ""
	var quantity: int        = 0
	var net_ids:  Array[int] = []
	## Arbitrary per-instance data. Well-known keys:
	##   "dur"     int   — current durability (-1 sentinel = no durability system)
	##   "quality" int   — future item quality tier
	var metadata: Dictionary = {}

	func is_empty() -> bool: return item_id.is_empty() or quantity <= 0

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

	# ── Durability helpers ─────────────────────────────────────────────────────

	func get_durability() -> int:
		return metadata.get("dur", -1)

	func has_durability() -> bool:
		return metadata.has("dur")

	func set_durability(v: int) -> void:
		metadata["dur"] = v

	# ── Stack operations ───────────────────────────────────────────────────────

	## Remove one item and return it as a new ItemStack of qty=1.
	func pop_one() -> ItemStack:
		if is_empty(): return ItemStack.new()
		var one      := ItemStack.new()
		one.item_id   = item_id
		one.metadata  = metadata.duplicate()
		one.quantity  = 1
		if not net_ids.is_empty():
			one.net_ids.append(net_ids.pop_back())
		quantity -= 1
		if quantity <= 0:
			item_id = ""
			quantity = 0
			net_ids.clear()
		return one

	## Append another ItemStack into this one (mutates self).
	func merge(other: ItemStack) -> void:
		if other == null or other.is_empty(): return
		if is_empty():
			item_id  = other.item_id
			metadata = other.metadata.duplicate()
		quantity += other.quantity
		net_ids.append_array(other.net_ids)

	func duplicate_stack() -> ItemStack:
		var d      := ItemStack.new()
		d.item_id   = item_id
		d.quantity  = quantity
		d.net_ids   = net_ids.duplicate()
		d.metadata  = metadata.duplicate()
		return d

# ── State ─────────────────────────────────────────────────────────────────────

var _slots: Array[ItemStack] = []

func _ready() -> void:
	main_slots   = rows * cols
	hotbar_slots = hotbar_rows * hotbar_cols
	total_slots  = main_slots + hotbar_slots
	capacity     = total_slots
	_slots.resize(total_slots)
	for i in total_slots:
		_slots[i] = ItemStack.new()
	changed.connect(_on_net_changed)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _active_abs() -> int:
	return main_slots + active_hotbar_row * hotbar_cols + active_slot

var active_index: int:
	get: return _active_abs()

# ── Active slot queries ───────────────────────────────────────────────────────

func active_slot_data() -> ItemStack:
	return _slots[_active_abs()]

func active_item_id() -> String:
	return _slots[_active_abs()].item_id

func active_net_id() -> int:
	return _slots[_active_abs()].active_net_id()

func active_durability() -> int:
	return _slots[_active_abs()].get_durability()

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
	for i in hotbar_slots:
		if not _slots[main_slots + i].is_empty(): n += 1
	return n

func size() -> int:
	var n := 0
	for s in _slots: n += s.quantity
	return n

# ── Mutations ─────────────────────────────────────────────────────────────────

## Add one item by id. Returns true if it fit, false if inventory was full.
## [durability] is a convenience shorthand — pass -1 for items with no durability.
## Add one item by id. [durability] is a convenience shorthand — pass -1 for
## items with no durability. Returns true if it fit, false if inventory was full.
func add(item_id: String, net_id: int = 0, durability: int = -1) -> bool:
	var meta: Dictionary = {}
	if durability >= 0: meta["dur"] = durability
	var s := _find_priority_slot(item_id)
	if s == null: return false
	_slot_add(s, item_id, net_id, meta)
	changed.emit()
	return true

## Find best slot for [item_id] respecting hotbar-first priority.
## Returns null if inventory is full.
func _find_priority_slot(item_id: String) -> ItemStack:
	# 1. Existing hotbar stack
	for r in hotbar_rows:
		for c in hotbar_cols:
			var s := _slots[main_slots + r * hotbar_cols + c]
			if not s.is_empty() and s.can_add(item_id): return s
	# 2. Existing main stack
	for i in main_slots:
		var s := _slots[i]
		if not s.is_empty() and s.can_add(item_id): return s
	# 3. Active hotbar slot
	var active := _slots[_active_abs()]
	if active.is_empty(): return active
	# 4. Empty hotbar (prefer active row)
	for r in hotbar_rows:
		var row := (active_hotbar_row + r) % hotbar_rows
		for c in hotbar_cols:
			var s := _slots[main_slots + row * hotbar_cols + c]
			if s.is_empty(): return s
	# 4. Empty main
	for i in main_slots:
		if _slots[i].is_empty(): return _slots[i]
	return null

func _slot_add(s: ItemStack, item_id: String, net_id: int, meta: Dictionary) -> void:
	s.item_id  = item_id
	s.quantity += 1
	s.net_ids.append(net_id)
	if not meta.is_empty(): s.metadata = meta.duplicate()

## Remove one item from the active slot. Returns an ItemStack (may be empty).
func remove_active_one() -> ItemStack:
	var taken: ItemStack = _take_one_from(_slots[_active_abs()])
	if not taken.is_empty(): changed.emit()
	return taken

## Remove one item matching [id] from any slot. Returns an ItemStack (may be empty).
func remove_one_by_id(id: String) -> ItemStack:
	for s in _slots:
		if s.item_id == id:
			var taken: ItemStack = _take_one_from(s)
			if not taken.is_empty(): changed.emit()
			return taken
	return ItemStack.new()

func _take_one_from(s: ItemStack) -> ItemStack:
	if s.is_empty(): return ItemStack.new()
	var taken     := ItemStack.new()
	taken.item_id  = s.item_id
	taken.metadata = s.metadata.duplicate()
	taken.quantity = 1
	if not s.net_ids.is_empty():
		taken.net_ids.append(s.net_ids.pop_back())
	s.quantity -= 1
	if s.quantity <= 0:
		s.item_id  = ""
		s.quantity = 0
		s.metadata = {}
		s.net_ids.clear()
	return taken

## Take up to [qty] items from slot [idx]. Returns an ItemStack.
func take_items(idx: int, qty: int) -> ItemStack:
	var s := _slots[idx]
	if s.is_empty() or qty <= 0: return ItemStack.new()
	var n     := mini(qty, s.quantity)
	var stack := ItemStack.new()
	stack.item_id  = s.item_id
	stack.metadata = s.metadata.duplicate()
	for _i in n:
		stack.quantity += 1
		stack.net_ids.append(s.net_ids.pop_back() if not s.net_ids.is_empty() else 0)
	s.quantity -= n
	if s.quantity <= 0:
		s.item_id  = ""
		s.quantity = 0
		s.metadata = {}
		s.net_ids.clear()
	changed.emit()
	return stack

## Place an ItemStack into slot [idx]. Returns any leftover as an ItemStack.
func place_items(idx: int, stack: ItemStack) -> ItemStack:
	if stack == null or stack.is_empty(): return ItemStack.new()
	var s := _slots[idx]
	if not s.is_empty() and s.item_id != stack.item_id:
		return stack.duplicate_stack()
	var data  := ItemRegistry.get_item(stack.item_id)
	var cap   := data.carry_stack if data else 1
	var placed := 0
	for i in stack.quantity:
		if s.quantity >= cap: break
		s.item_id  = stack.item_id
		s.metadata = stack.metadata.duplicate()
		s.quantity += 1
		s.net_ids.append(stack.net_ids[i] if i < stack.net_ids.size() else 0)
		placed += 1
	if placed > 0: changed.emit()
	if placed == stack.quantity: return ItemStack.new()
	var leftover      := ItemStack.new()
	leftover.item_id   = stack.item_id
	leftover.metadata  = stack.metadata.duplicate()
	for i in range(placed, stack.quantity):
		leftover.quantity += 1
		if i < stack.net_ids.size(): leftover.net_ids.append(stack.net_ids[i])
	return leftover

## Add all items in an ItemStack back to inventory preserving full metadata.
func add_drag(stack: ItemStack) -> void:
	if stack == null or stack.is_empty(): return
	for i in stack.quantity:
		var nid: int = stack.net_ids[i] if i < stack.net_ids.size() else 0
		var s := _find_priority_slot(stack.item_id)
		if s == null: return   # inventory full
		_slot_add(s, stack.item_id, nid, stack.metadata)
		changed.emit()

## Decrement durability of the active slot. Returns true when the tool breaks.
func use_active_durability(amount: int = 1) -> bool:
	var s := _slots[_active_abs()]
	if not s.has_durability(): return false
	var new_dur := maxi(0, s.get_durability() - amount)
	s.set_durability(new_dur)
	changed.emit()
	return new_dur <= 0

func swap_slots(a: int, b: int) -> void:
	if a == b: return
	var tmp  := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
	changed.emit()

# ── Navigation ────────────────────────────────────────────────────────────────

func cycle_next() -> void:
	active_slot = (active_slot + 1) % hotbar_cols; changed.emit()

func cycle_prev() -> void:
	active_slot = (active_slot - 1 + hotbar_cols) % hotbar_cols; changed.emit()

func next_hotbar_row() -> void:
	active_hotbar_row = (active_hotbar_row + 1) % hotbar_rows; changed.emit()

func prev_hotbar_row() -> void:
	active_hotbar_row = (active_hotbar_row - 1 + hotbar_rows) % hotbar_rows; changed.emit()

func set_active_hotbar_slot(col: int) -> void:
	active_slot = clamp(col, 0, hotbar_cols - 1); changed.emit()

func set_active_hotbar_row(row: int) -> void:
	active_hotbar_row = clamp(row, 0, hotbar_rows - 1); changed.emit()

# ── Slot access ───────────────────────────────────────────────────────────────

func get_slot(idx: int) -> ItemStack:
	return _slots[idx]

func get_hotbar_slot(r: int, c: int) -> ItemStack:
	return _slots[main_slots + r * hotbar_cols + c]

func get_main_slot(r: int, c: int) -> ItemStack:
	return _slots[r * cols + c]

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
			data.append({"id": "", "qty": 0, "nets": []})
		else:
			data.append({"id": s.item_id, "qty": s.quantity,
					"nets": s.net_ids.duplicate(), "meta": s.metadata.duplicate()})
	return data

func apply_remote_state(slots_data: Array) -> void:
	_applying_remote = true
	for i in _slots.size():
		_slots[i] = ItemStack.new()
	for i in mini(slots_data.size(), _slots.size()):
		var entry: Dictionary = slots_data[i]
		var iid: String = entry.get("id", "")
		if iid.is_empty(): continue
		var s      := _slots[i]
		s.item_id   = iid
		s.quantity  = entry.get("qty", 0)
		s.metadata  = entry.get("meta", {}).duplicate()
		for nid in entry.get("nets", []):
			s.net_ids.append(int(nid))
	changed.emit()
	_applying_remote = false
