extends CanvasLayer


const COLS := Inventory.MAIN_COLS

var _inv: Inventory = null

var _slots: Array[ItemSlotWidget] = []

# ── Drag state ─────────────────────────────────────────────────────────────────
# Items are physically lifted from their slot while being dragged.
var _picked_items: Array[PhysicalItem] = []
var _picked_data:  ItemData            = null

# ── Navigation ─────────────────────────────────────────────────────────────────
var _cursor       := 0
var _ctrl_nav     := false
var _hovered_slot := -1   # slot index under the mouse cursor

# ── Double-click detection ─────────────────────────────────────────────────────
const DCLICK_MS      := 250
var _last_click_slot := -1
var _last_click_msec := 0

# ── Drag-split state ───────────────────────────────────────────────────────────
# Holding a mouse button while moving over slots distributes the stack.
# LEFT drag = even share per slot; RIGHT drag = 1 item per slot immediately.
var _split_button       := -1   # MOUSE_BUTTON_LEFT/RIGHT while button is held
var _split_pending_slot := -1   # slot where the button was first pressed
var _split_mode         := false
var _split_slots: Array[int] = []
var _lmb_placed: Dictionary  = {}  # slot_idx -> qty placed during live LMB drag

# ── Floating drag visual ───────────────────────────────────────────────────────
var _drag_root:  Control     = null
var _drag_panel: Panel       = null
var _drag_icon:  TextureRect = null
var _drag_count: Label       = null

# ── Tooltip ────────────────────────────────────────────────────────────────────
var _tooltip:      Panel         = null
var _tooltip_vbox: VBoxContainer = null

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("inventory_hud")
	set_process(false)
	_build()
	hide()

func _process(_d: float) -> void:
	var mp := get_viewport().get_mouse_position()

	if _drag_root and _drag_panel and _drag_panel.visible:
		_drag_root.position = mp - Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)

	if _tooltip and _tooltip.visible:
		_position_tooltip(mp)

	# Detect mouse-button release to commit drag-split or single-slot click.
	if _split_button >= 0 and not Input.is_mouse_button_pressed(_split_button):
		if _split_mode and not _picked_items.is_empty():
			_commit_split()
		elif _split_pending_slot >= 0 and not _picked_items.is_empty() \
				and _split_slots.size() <= 1:
			if _split_button == MOUSE_BUTTON_LEFT:
				_left_activate(_split_pending_slot)
			else:
				_right_activate(_split_pending_slot)
		_clear_split()
		# If all items were placed during LMB drag, clean up the now-stale _picked_data.
		if _picked_items.is_empty():
			_picked_data = null
			_drag_panel.visible = false

# ── Open / close ───────────────────────────────────────────────────────────────
func toggle() -> void:
	if visible: _close()
	else:        _open()

func _open() -> void:
	_connect_inv()
	show()
	GameState.push_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_ctrl_nav = false
	_drag_panel.visible = false
	_hide_tooltip()
	set_process(true)
	_refresh()
	var hb := get_tree().get_first_node_in_group("hotbar_hud")
	if hb: hb.hide()

func _close() -> void:
	_cancel_drag()
	_hide_tooltip()
	hide()
	GameState.pop_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process(false)
	var hb := get_tree().get_first_node_in_group("hotbar_hud")
	if hb: hb.show()

# ── Drag helpers ───────────────────────────────────────────────────────────────
func _clear_split() -> void:
	_split_button       = -1
	_split_pending_slot = -1
	_split_mode         = false
	_split_slots.clear()
	_lmb_placed.clear()

## Return all held items to the inventory without dropping them.
func _cancel_drag() -> void:
	_clear_split()
	if not _picked_items.is_empty() and _inv:
		for item in _picked_items:
			if is_instance_valid(item):
				_inv.add(item)
		_picked_items.clear()
		_picked_data = null
	if _drag_panel:
		_drag_panel.visible = false

## Throw one held item into the world (RMB on overlay while dragging).
func _drop_one_held_item() -> void:
	_clear_split()
	if _picked_items.is_empty():
		return
	var item: PhysicalItem = _picked_items.pop_back()
	if is_instance_valid(item):
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("drop_item"):
			player.drop_item(item)
		else:
			item.visible         = true
			item.reparent(get_tree().current_scene, true)
			item.scale           = Vector3.ONE
			item.collision_layer = 1
			item.collision_mask  = 1
			item.freeze          = false
			item.linear_velocity = Vector3(0, 3, 0)
	if _picked_items.is_empty():
		_picked_data        = null
		_drag_panel.visible = false
	else:
		_update_drag_visual()
	if _inv: _inv.changed.emit()
	_refresh()

## Throw held items into the world in front of the player (multiplayer-synced).
func _drop_held_items() -> void:
	_clear_split()
	if _picked_items.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	for item in _picked_items:
		if not is_instance_valid(item):
			continue
		if player and player.has_method("drop_item"):
			player.drop_item(item)
		else:
			item.visible         = true
			item.reparent(get_tree().current_scene, true)
			item.scale           = Vector3.ONE
			item.collision_layer = 1
			item.collision_mask  = 1
			item.freeze          = false
			item.linear_velocity = Vector3(0, 3, 0)
	_picked_items.clear()
	_picked_data = null
	_drag_panel.visible = false
	if _inv:
		_inv.changed.emit()

func _connect_inv() -> void:
	if _inv:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	_inv = player.inventory
	_inv.changed.connect(func() -> void:
		if visible: _refresh()
	)

# ── Input ──────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Escape / controller B → return held items then close (or just close)
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventJoypadButton and event.pressed \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A):
		if not _picked_items.is_empty():
			_cancel_drag(); _refresh()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return

	# Number keys 1-5: hotswap hovered slot ↔ active-row hotbar slot N
	if event is InputEventKey and event.pressed and not event.echo \
			and _hovered_slot >= 0 and _picked_items.is_empty():
		var slot_num := -1
		match (event as InputEventKey).physical_keycode:
			KEY_1: slot_num = 0
			KEY_2: slot_num = 1
			KEY_3: slot_num = 2
			KEY_4: slot_num = 3
			KEY_5: slot_num = 4
		if slot_num >= 0 and _inv:
			var hotbar_idx := Inventory.MAIN_SLOTS \
				+ _inv.active_hotbar_row * Inventory.HOTBAR_COLS + slot_num
			if _hovered_slot != hotbar_idx:
				var hov := _inv.get_slot(_hovered_slot)
				var hot := _inv.get_slot(hotbar_idx)
				if not hov.is_empty() and not hot.is_empty() \
						and hov.item_data.id == hot.item_data.id \
						and not hot.is_full():
					var items := _inv.take_items(_hovered_slot, hov.quantity)
					var leftover := _inv.place_items(hotbar_idx, items)
					for item in leftover:
						_inv.add(item)
				else:
					_inv.swap_slots(_hovered_slot, hotbar_idx)
			_refresh()
			get_viewport().set_input_as_handled()
			return

	# Q over a slot → drop one item from that slot into the world
	if event.is_action_pressed("drop") and _hovered_slot >= 0 and _picked_items.is_empty() and _inv:
		var slot := _inv.get_slot(_hovered_slot)
		if not slot.is_empty():
			var taken := _inv.take_items(_hovered_slot, 1)
			if not taken.is_empty():
				var player := get_tree().get_first_node_in_group("player")
				if player and player.has_method("drop_item"):
					player.drop_item(taken[0])
				else:
					taken[0].visible         = true
					taken[0].reparent(get_tree().current_scene, true)
					taken[0].scale           = Vector3.ONE
					taken[0].collision_layer = 1
					taken[0].collision_mask  = 1
					taken[0].freeze          = false
					taken[0].linear_velocity = Vector3(0, 3, 0)
			_refresh()
			get_viewport().set_input_as_handled()
			return

	# Controller d-pad navigation (main grid only)
	if event is InputEventJoypadButton and event.pressed:
		var btn := (event as InputEventJoypadButton).button_index
		match btn:
			JOY_BUTTON_DPAD_LEFT:  _nav(-1,  0)
			JOY_BUTTON_DPAD_RIGHT: _nav( 1,  0)
			JOY_BUTTON_DPAD_UP:    _nav( 0, -1)
			JOY_BUTTON_DPAD_DOWN:  _nav( 0,  1)
			JOY_BUTTON_B:
				_clear_split()
				_left_activate(_cursor)
		get_viewport().set_input_as_handled()

func _nav(dx: int, dy: int) -> void:
	var col := _cursor % COLS
	var row := _cursor / COLS
	col    = (col + dx + COLS) % COLS
	row    = clamp(row + dy, 0, Inventory.MAIN_ROWS - 1)
	_cursor   = row * COLS + col
	_ctrl_nav = true
	_refresh()

# ── Slot interaction ───────────────────────────────────────────────────────────

## Left-click: pick up all → or place all / swap types.
func _left_activate(idx: int) -> void:
	if _inv == null:
		return
	var slot := _inv.get_slot(idx)

	if _picked_items.is_empty():
		if not slot.is_empty():
			_hide_tooltip()
			var taken := _inv.take_items(idx, slot.quantity)
			if not taken.is_empty():
				_picked_items = taken
				_picked_data  = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
				_drag_panel.visible = true
				_drag_root.position = get_viewport().get_mouse_position() \
					- Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
	else:
		if slot.is_empty() or slot.item_data.id == _picked_data.id:
			# Place all, keep any overflow in hand
			var leftover := _inv.place_items(idx, _picked_items)
			_picked_items = leftover
			if _picked_items.is_empty():
				_picked_data = null
				_drag_panel.visible = false
			else:
				_update_drag_visual()
		else:
			# Different type → swap: take slot contents, put held items there
			var old_qty  := slot.quantity
			var swapped  := _inv.take_items(idx, old_qty)
			var leftover := _inv.place_items(idx, _picked_items)
			_picked_items = swapped
			_picked_items.append_array(leftover)
			if _picked_items.is_empty():
				_picked_data = null
				_drag_panel.visible = false
			else:
				_picked_data = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
	_refresh()

## Right-click: pick up half → or place one item at a time.
func _right_activate(idx: int) -> void:
	if _inv == null:
		return
	var slot := _inv.get_slot(idx)

	if _picked_items.is_empty():
		if not slot.is_empty():
			_hide_tooltip()
			var qty  := (slot.quantity + 1) / 2
			var taken := _inv.take_items(idx, qty)
			if not taken.is_empty():
				_picked_items = taken
				_picked_data  = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
				_drag_panel.visible = true
				_drag_root.position = get_viewport().get_mouse_position() \
					- Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
	else:
		# Place one item if compatible and slot not full.
		if not _picked_items.is_empty() \
				and (slot.is_empty() or slot.item_data.id == _picked_data.id) and not slot.is_full():
			var one: Array[PhysicalItem] = [_picked_items.pop_back()]
			var leftover := _inv.place_items(idx, one)
			if not leftover.is_empty():
				_picked_items.append(leftover[0])
			if _picked_items.is_empty():
				_picked_data = null
				_drag_panel.visible = false
			else:
				_update_drag_visual()
	_refresh()

## Shift+click: instantly move entire stack to the other section (main ↔ hotbar).
func _shift_click(idx: int) -> void:
	if _inv == null:
		return
	var slot := _inv.get_slot(idx)
	if slot.is_empty():
		return

	var items := _inv.take_items(idx, slot.quantity)
	var leftover: Array[PhysicalItem]

	if idx < Inventory.MAIN_SLOTS:
		leftover = _quick_fill_hotbar(items)
	else:
		leftover = _quick_fill_main(items)

	# Put back anything that didn't fit
	for item in leftover:
		if is_instance_valid(item):
			_inv.add(item)
	_refresh()

## Double-click: collect all matching items from the whole inventory onto the cursor.
func _double_click_collect(data: ItemData) -> void:
	if data == null or _inv == null:
		return
	var max_stack := data.carry_stack
	for idx in Inventory.TOTAL_SLOTS:
		if _picked_items.size() >= max_stack:
			break
		var slot := _inv.get_slot(idx)
		if not slot.is_empty() and slot.item_data.id == data.id:
			var can_take := max_stack - _picked_items.size()
			var taken := _inv.take_items(idx, can_take)
			for item in taken:
				if is_instance_valid(item): item.visible = false
			_picked_items.append_array(taken)
	if not _picked_items.is_empty():
		_picked_data = data
		_update_drag_visual()
		_drag_panel.visible = true
		_drag_root.position = get_viewport().get_mouse_position() \
			- Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
	_refresh()

## Commit a drag-split: distribute _picked_items across _split_slots.
func _commit_split() -> void:
	if _split_slots.is_empty() or _picked_items.is_empty():
		return

	if _split_button == MOUSE_BUTTON_LEFT:
		# Items were already placed live during drag. Any remainder stays in hand.
		pass
	else:
		# Right-drag: one item per slot
		for slot_idx in _split_slots:
			if _picked_items.is_empty():
				break
			var slot := _inv.get_slot(slot_idx)
			if (slot.is_empty() or slot.item_data.id == _picked_data.id) and not slot.is_full():
				var one: Array[PhysicalItem] = [_picked_items.pop_back()]
				var leftover := _inv.place_items(slot_idx, one)
				_picked_items.append_array(leftover)

	if _picked_items.is_empty():
		_picked_data = null
		_drag_panel.visible = false
	else:
		_update_drag_visual()
	_refresh()

# ── Quick-fill helpers for shift-click ────────────────────────────────────────
func _quick_fill_hotbar(items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	var rem: Array[PhysicalItem] = []
	rem.append_array(items)
	if rem.is_empty() or _inv == null: return rem
	var data := rem[0].item_data
	# Stack into existing hotbar slots first (active row preferred)
	for r in Inventory.HOTBAR_ROWS:
		var row := (_inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if rem.is_empty(): return []
			var idx := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			var s := _inv.get_slot(idx)
			if not s.is_empty() and s.item_data.id == data.id and not s.is_full():
				rem = _inv.place_items(idx, rem)
	# Then fill empty slots
	for r in Inventory.HOTBAR_ROWS:
		var row := (_inv.active_hotbar_row + r) % Inventory.HOTBAR_ROWS
		for c in Inventory.HOTBAR_COLS:
			if rem.is_empty(): return []
			var idx := Inventory.MAIN_SLOTS + row * Inventory.HOTBAR_COLS + c
			if _inv.get_slot(idx).is_empty():
				rem = _inv.place_items(idx, rem)
	return rem

func _quick_fill_main(items: Array[PhysicalItem]) -> Array[PhysicalItem]:
	var rem: Array[PhysicalItem] = []
	rem.append_array(items)
	if rem.is_empty() or _inv == null: return rem
	var data := rem[0].item_data
	for i in Inventory.MAIN_SLOTS:
		if rem.is_empty(): return []
		var s := _inv.get_slot(i)
		if not s.is_empty() and s.item_data.id == data.id and not s.is_full():
			rem = _inv.place_items(i, rem)
	for i in Inventory.MAIN_SLOTS:
		if rem.is_empty(): return []
		if _inv.get_slot(i).is_empty():
			rem = _inv.place_items(i, rem)
	return rem

# ── Drag visual ────────────────────────────────────────────────────────────────
func _update_drag_visual() -> void:
	if _picked_data == null or _picked_items.is_empty():
		return
	var c := _picked_data.color
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 0.95)
	s.border_color = UIStyle.COL_ACCENT
	s.set_border_width_all(2)
	_drag_panel.add_theme_stylebox_override("panel", s)
	_drag_count.text   = str(_picked_items.size()) if _picked_items.size() > 1 else ""
	_drag_icon.texture = _picked_data.icon

# ── Tooltip ────────────────────────────────────────────────────────────────────
func _show_tooltip(slot: Inventory.Slot) -> void:
	if slot.is_empty(): return
	_populate_tooltip(slot)
	_tooltip.visible = true
	_position_tooltip(get_viewport().get_mouse_position())

func _hide_tooltip() -> void:
	if _tooltip: _tooltip.visible = false

func _position_tooltip(mp: Vector2) -> void:
	_tooltip.reset_size()
	var sz := _tooltip.size
	var vp := get_viewport().get_visible_rect().size
	var x  := mp.x + 18.0
	var y  := mp.y + 18.0
	if x + sz.x > vp.x - 8.0: x = mp.x - sz.x - 8.0
	if y + sz.y > vp.y - 8.0: y = mp.y - sz.y - 8.0
	_tooltip.position = Vector2(x, y)

func _populate_tooltip(slot: Inventory.Slot) -> void:
	for child in _tooltip_vbox.get_children():
		child.queue_free()
	var data := slot.item_data

	var name_lbl := Label.new()
	name_lbl.text = data.display_name
	name_lbl.add_theme_font_override("font", UIStyle.FONT_BOLD)
	name_lbl.add_theme_font_size_override("font_size", UIStyle.SIZE_LG)
	name_lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_HEADING)
	_tooltip_vbox.add_child(name_lbl)

	if not data.description.is_empty():
		var desc := Label.new()
		desc.text = data.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(200, 0)
		desc.add_theme_font_override("font", UIStyle.FONT_LIGHT)
		desc.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
		desc.add_theme_color_override("font_color", UIStyle.COL_TEXT_DIM)
		_tooltip_vbox.add_child(desc)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_tooltip_vbox.add_child(sep)

	if data.mass > 0.0:       _add_stat("Mass",  "%.1f kg" % data.mass)
	if data.carry_stack > 1:  _add_stat("Stack", "×%d"    % data.carry_stack)
	if data.price > 0:        _add_stat("Value", "$%d"     % data.price)

	if data is ToolItemData:
		var td  := data as ToolItemData
		var cur := slot.physical[0].current_durability if not slot.physical.is_empty() else td.durability_max
		_add_stat("Type",       td.tool_type.capitalize())
		_add_stat("Tier",       td.level_name)
		_add_stat("Durability", "%d / %d" % [cur, td.durability_max])
		if td.attack_damage  > 0.0: _add_stat("Attack",  "%.0f dmg" % td.attack_damage)
		if td.harvest_damage > 0.0: _add_stat("Harvest", "%.0f dmg" % td.harvest_damage)

func _add_stat(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", UIStyle.FONT)
	lbl.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_DIM)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", UIStyle.FONT_BOLD)
	val.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	val.add_theme_color_override("font_color", UIStyle.COL_TEXT)
	row.add_child(val)
	_tooltip_vbox.add_child(row)

# ── Build UI ───────────────────────────────────────────────────────────────────
func _build() -> void:
	const PAD := 16.0
	var grid_w  := float(COLS * (UIStyle.SLOT_SZ + UIStyle.SLOT_GAP) - UIStyle.SLOT_GAP)
	var panel_w := grid_w + PAD * 2.0
	var panel_h := 50.0 \
		+ float(Inventory.MAIN_ROWS)   * (UIStyle.SLOT_SZ + UIStyle.SLOT_GAP) \
		+ 30.0 \
		+ float(Inventory.HOTBAR_ROWS) * (UIStyle.SLOT_SZ + UIStyle.SLOT_GAP) \
		+ PAD * 2.0

	_slots.resize(Inventory.TOTAL_SLOTS)
	for i in Inventory.TOTAL_SLOTS:
		_slots[i] = null

	# Dark overlay
	# LMB held items → drop all;  LMB empty hands → close.
	# RMB held items → drop one.
	var overlay := ColorRect.new()
	overlay.color        = Color(0, 0, 0, 0.50)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				if not _picked_items.is_empty():
					_drop_held_items(); _refresh()
				else:
					_close()
			MOUSE_BUTTON_RIGHT:
				if _picked_items.size() > 1:
					_drop_one_held_item()
	)
	add_child(overlay)

	# Centred panel
	var ps := StyleBoxFlat.new()
	ps.bg_color     = UIStyle.COL_PANEL_BG
	ps.border_color = UIStyle.COL_PANEL_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(PAD)

	var root := Panel.new()
	root.add_theme_stylebox_override("panel", ps)
	root.anchor_left   = 0.5; root.anchor_right  = 0.5
	root.anchor_top    = 0.5; root.anchor_bottom = 0.5
	root.offset_left   = -panel_w / 2.0; root.offset_right  =  panel_w / 2.0
	root.offset_top    = -panel_h / 2.0; root.offset_bottom =  panel_h / 2.0
	root.mouse_filter  = Control.MOUSE_FILTER_STOP
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(PAD))
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	# Title
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "INVENTORY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UIStyle.FONT_BOLD)
	title.add_theme_font_size_override("font_size", UIStyle.SIZE_LG)
	title.add_theme_color_override("font_color", UIStyle.COL_TEXT_HEADING)
	title_row.add_child(title)
	title_row.add_child(UIStyle.make_prompt("open_inventory", "Close"))

	# ── Main 3×8 grid ─────────────────────────────────────────────────────────
	var main_grid := VBoxContainer.new()
	main_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(main_grid)
	for r in Inventory.MAIN_ROWS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		main_grid.add_child(hbox)
		for c in COLS:
			_build_slot(hbox, r * COLS + c)

	# ── Hotbar row (same slots as bottom HUD) ────────────────────────────────
	var hotbar_grid := VBoxContainer.new()
	hotbar_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(hotbar_grid)
	for hr in Inventory.HOTBAR_ROWS:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		hotbar_grid.add_child(hbox)
		for hc in Inventory.HOTBAR_COLS:
			_build_slot(hbox, Inventory.MAIN_SLOTS + hr * Inventory.HOTBAR_COLS + hc)

	# ── Floating drag visual (z=100) ──────────────────────────────────────────
	_drag_root = Control.new()
	_drag_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_root.z_index = 100
	add_child(_drag_root)

	_drag_panel = Panel.new()
	_drag_panel.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	_drag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.visible = false
	_drag_root.add_child(_drag_panel)

	_drag_icon = TextureRect.new()
	_drag_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drag_icon.offset_left  =  6; _drag_icon.offset_top    =  6
	_drag_icon.offset_right = -6; _drag_icon.offset_bottom = -6
	_drag_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.add_child(_drag_icon)

	_drag_count = Label.new()
	_drag_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_drag_count.offset_left = -28; _drag_count.offset_top    = -18
	_drag_count.offset_right = -3; _drag_count.offset_bottom = -3
	_drag_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_drag_count.add_theme_font_override("font", UIStyle.FONT_BOLD)
	_drag_count.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	_drag_count.add_theme_color_override("font_color", Color.WHITE)
	_drag_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.add_child(_drag_count)

	# ── Tooltip (z=200) ───────────────────────────────────────────────────────
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color     = Color(0.05, 0.05, 0.08, 0.96)
	tip_style.border_color = UIStyle.COL_PANEL_BORDER
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(6)
	tip_style.set_content_margin_all(10)

	_tooltip = Panel.new()
	_tooltip.add_theme_stylebox_override("panel", tip_style)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index      = 200
	_tooltip.visible      = false
	add_child(_tooltip)

	_tooltip_vbox = VBoxContainer.new()
	_tooltip_vbox.add_theme_constant_override("separation", 4)
	_tooltip_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tooltip_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_tooltip.add_child(_tooltip_vbox)

## Build one ItemSlotWidget at [idx] and wire up all mouse events.
func _build_slot(parent: Control, idx: int) -> void:
	var w := ItemSlotWidget.new()
	parent.add_child(w)
	_slots[idx] = w

	var i2 := idx
	w.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		_ctrl_nav = false

		var now_ms := Time.get_ticks_msec()

		# ── Fast double-click: collect all matching ───────────────────────────
		if ev.button_index == MOUSE_BUTTON_LEFT \
				and _last_click_slot == i2 \
				and (now_ms - _last_click_msec) <= DCLICK_MS:
			_clear_split()
			_hide_tooltip()
			if _picked_items.is_empty():
				if _inv:
					var src := _inv.get_slot(i2)
					if not src.is_empty():
						var taken := _inv.take_items(i2, src.quantity)
						for item in taken:
							if is_instance_valid(item): item.visible = false
						_picked_items.append_array(taken)
						if not taken.is_empty():
							_picked_data = taken[0].item_data
							_drag_root.position = get_viewport().get_mouse_position() \
								- Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
							_drag_panel.visible = true
			if not _picked_items.is_empty() and _picked_data != null:
				_double_click_collect(_picked_data)
			else:
				_refresh()
			_last_click_slot = -1
			return

		# ── Shift+click: quick transfer ───────────────────────────────────────
		if ev.shift_pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and _picked_items.is_empty():
			_shift_click(i2)
			_last_click_slot = -1
			return

		# Track for fast double-click (left-click only, not shift)
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.shift_pressed:
			_last_click_slot = i2
			_last_click_msec = now_ms

		# ── Normal click or split-start ───────────────────────────────────────
		if _picked_items.is_empty():
			# Hands empty: act immediately on press
			match ev.button_index:
				MOUSE_BUTTON_LEFT:  _left_activate(i2)
				MOUSE_BUTTON_RIGHT: _right_activate(i2)
		else:
			# Holding items: defer action to button release so we can detect drags
			if _split_button < 0 and \
					(ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				_split_button       = ev.button_index
				_split_pending_slot = i2
				_split_slots.clear()
				_split_slots.append(i2)
	)

	w.mouse_entered.connect(func() -> void:
		_hovered_slot = i2
		var rmb_drag := not _picked_items.is_empty() \
				and _split_button == MOUSE_BUTTON_RIGHT \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
				and not _split_slots.has(i2)
		var lmb_drag := _split_button == MOUSE_BUTTON_LEFT \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				and not _split_slots.has(i2) \
				and _picked_data != null \
				and (not _picked_items.is_empty() or not _lmb_placed.is_empty())

		if rmb_drag:
			# RMB drag: place 1 item per slot immediately.
			# On first move away from the initial slot, also place 1 there.
			# (mouse_entered never fires for the slot the cursor was already on.)
			if _split_slots.size() == 1 and not _picked_items.is_empty():
				var init := _inv.get_slot(_split_pending_slot)
				if (init.is_empty() or init.item_data.id == _picked_data.id) and not init.is_full():
					var one: Array[PhysicalItem] = [_picked_items.pop_back()]
					_picked_items.append_array(_inv.place_items(_split_pending_slot, one))
			if not _picked_items.is_empty():
				var rslot := _inv.get_slot(i2)
				if (rslot.is_empty() or rslot.item_data.id == _picked_data.id) and not rslot.is_full():
					var one: Array[PhysicalItem] = [_picked_items.pop_back()]
					_picked_items.append_array(_inv.place_items(i2, one))
			if _picked_items.is_empty():
				_picked_data = null
				_drag_panel.visible = false
			else:
				_update_drag_visual()
			_refresh()
			_split_slots.append(i2)

		elif lmb_drag:
			# LMB drag: live even distribution across all touched slots.
			_split_mode = true
			# Reclaim items from all previously touched slots back into hand.
			for slot_idx in _split_slots:
				var qty: int = _lmb_placed.get(slot_idx, 0)
				if qty > 0:
					_picked_items.append_array(_inv.take_items(slot_idx, qty))
			_lmb_placed.clear()
			# Distribute evenly across all touched slots plus the newly entered one.
			var all_slots := _split_slots.duplicate()
			all_slots.append(i2)
			var per_slot := maxi(1, _picked_items.size() / all_slots.size())
			for slot_idx in all_slots:
				if _picked_items.is_empty():
					break
				var lslot := _inv.get_slot(slot_idx)
				if lslot.is_empty() or lslot.item_data.id == _picked_data.id:
					var n := mini(per_slot, _picked_items.size())
					var to_place: Array[PhysicalItem] = []
					for _ii in n:
						if _picked_items.is_empty(): break
						to_place.append(_picked_items.pop_back())
					var leftover := _inv.place_items(slot_idx, to_place)
					_picked_items.append_array(leftover)
					_lmb_placed[slot_idx] = to_place.size() - leftover.size()
			_split_slots.append(i2)
			if _picked_items.is_empty() and per_slot == 1:
				# 1-per-slot with nothing left — fully distributed, finish immediately.
				_picked_data = null
				_drag_panel.visible = false
				_clear_split()
			else:
				# Items remain, or spread >1 per slot (may still reclaim on next slot).
				_update_drag_visual()
				_drag_panel.visible = true
			_refresh()

		if _inv and not _inv.get_slot(i2).is_empty() and _picked_items.is_empty():
			_show_tooltip(_inv.get_slot(i2))
	)

	w.mouse_exited.connect(func() -> void:
		if _hovered_slot == i2:
			_hovered_slot = -1
		_hide_tooltip()
	)

# ── Refresh ────────────────────────────────────────────────────────────────────
func _refresh() -> void:
	if not _inv:
		return
	for idx in Inventory.TOTAL_SLOTS:
		if _slots[idx] == null:
			continue
		var slot      := _inv.get_slot(idx)
		var is_cursor := idx == _cursor and _ctrl_nav and idx < Inventory.MAIN_SLOTS
		_slots[idx].set_item(slot.item_data if not slot.is_empty() else null, slot.quantity)
		_slots[idx].set_cursor(is_cursor)
