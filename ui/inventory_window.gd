class_name InventoryWindow
extends CanvasLayer

## Base class for all inventory-style windows (player inventory panel, chests,
## shops, crafting tables, …).  Provides:
##   • Window shell (scrim + panel + title bar + close badge)
##   • Full drag-and-drop system (pick, place, swap, split RMB/LMB, double-click collect)
##   • Per-slot inventory routing (_sinv / _sidx) — supports dual-inventory layouts
##     where the external inventory is shown above the player's own inventory
##   • InventoryController hook for slot rules and shift-click transfer logic
##   • Mouse-mode and controller-badge management
##
## ─── Subclass API ────────────────────────────────────────────────────────────
##
##   _window_title()    → String           panel title
##   _window_layout()   → Layout           CENTERED or ANCHORED
##   _window_anchors()  → Array[float]     [l,t,r,b] for ANCHORED mode
##   _make_controller() → InventoryController   override for custom transfer rules
##   _build_content(vbox) → void           populate below the header;
##                                         call _build_player_section(vbox) at the
##                                         bottom to add the player inv automatically
##   _on_opened()       → void             after show(); connect _inv / _player_inv
##   _on_closed()       → void             before hide(); cleanup
##   _handle_input(ev)  → bool             true = event consumed
##   _refresh()         → void             redraw slot contents
##   _get_ctrl_cursor_pos() → Vector2      drag-ghost origin in controller mode
##
## ─── Dual-inventory pattern ───────────────────────────────────────────────────
##
##   func _build_content(vbox):
##       # --- external section (e.g. chest) ---
##       for r in 3:
##           var hbox = …
##           for c in Inventory.COLS:
##               _build_slot(hbox, r * Inventory.COLS + c)
##       _build_player_section(vbox)   # seals external count, adds separator + player grid
##
##   func _on_opened():
##       _inv        = _chest_node.inventory
##       _player_inv = _player.inventory
##       _controller.inv        = _inv
##       _controller.player_inv = _player_inv
##       _inv.changed.connect(func(): if visible: _refresh())
##       _player_inv.changed.connect(func(): if visible: _refresh())
##       _refresh()

# ── Layout ─────────────────────────────────────────────────────────────────────

enum Layout { CENTERED, ANCHORED }

func _window_title()   -> String:       return ""
func _window_layout()  -> Layout:       return Layout.ANCHORED
func _window_anchors() -> Array[float]: return [0.28, 0.08, 0.72, 0.92]

# ── Shared UI nodes ────────────────────────────────────────────────────────────

var _panel:        PanelContainer = null
var _content_vbox: VBoxContainer  = null
var _title_row:    HBoxContainer  = null
var _close_hint:   Control        = null

# ── State ──────────────────────────────────────────────────────────────────────

var _player:      Node      = null
var _inv:         Inventory = null   # primary / external inventory
var _player_inv:  Inventory = null   # player inventory (dual-mode only)
var _ctrl_nav:    bool      = false
var _hovered_slot: int      = -1

# ── Slot map ───────────────────────────────────────────────────────────────────
# Every _build_slot() call registers its widget here.
# _sinv(pos) / _sidx(pos) resolve which Inventory and which index a position maps to.

var _slots:               Array[ItemSlotWidget] = []
var _slot_count:          int                   = 0
var _external_slot_count: int                   = 0   # set by _build_player_section()

## Which inventory owns the slot at position [pos].
## Default: external slots → _inv; player slots (pos >= _external_slot_count) → _player_inv.
## If _player_inv is null, all slots belong to _inv.
func _sinv(pos: int) -> Inventory:
	if _player_inv != null and pos >= _external_slot_count:
		return _player_inv
	return _inv

## Index within the owning inventory for slot at position [pos].
func _sidx(pos: int) -> int:
	if _player_inv != null and pos >= _external_slot_count:
		return pos - _external_slot_count
	return pos

# ── Controller ─────────────────────────────────────────────────────────────────

var _controller: InventoryController = null

## Override to return a subclass of InventoryController with custom slot rules.
func _make_controller() -> InventoryController:
	return InventoryController.new()

# ── Drag system ────────────────────────────────────────────────────────────────

var _picked_items:      Array[PhysicalItem] = []
var _picked_data:       ItemData            = null
var _drag_root:         Control             = null
var _drag_panel:        Panel               = null
var _drag_icon:         TextureRect         = null
var _drag_count:        Label               = null

const DCLICK_MS      := 250
var _last_click_slot := -1
var _last_click_msec := 0

var _split_button:       int        = -1
var _split_pending_slot: int        = -1
var _split_mode:         bool       = false
var _split_slots:        Array[int] = []
var _lmb_placed:         Dictionary = {}

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_controller = _make_controller()
	hide()
	_build_shell()
	_build_drag_overlay()
	InputHelper.input_changed.connect(_on_input_device_changed)

func open(player: Node) -> void:
	_player   = player
	_ctrl_nav = InputHelper.is_joy()
	show()
	GameState.push_ui()
	_apply_mouse_mode()
	_rebuild_close_hint()
	_on_opened()

func _close() -> void:
	_cancel_drag()
	ItemTooltip.hide()
	_on_closed()
	hide()
	GameState.pop_ui()
	call_deferred("_recapture_mouse")

func _recapture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_mouse_mode() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if _ctrl_nav else Input.MOUSE_MODE_VISIBLE)

# ── Virtuals ───────────────────────────────────────────────────────────────────

func _build_content(_vbox: VBoxContainer) -> void: pass
func _on_opened()  -> void: pass
func _on_closed()  -> void: pass

## Refresh all slot widgets.  Base implementation updates every slot in _slots[].
## Subclasses with custom layouts (e.g. CraftingUI) should override.
func _refresh() -> void:
	for pos in _slot_count:
		if pos >= _slots.size() or _slots[pos] == null:
			continue
		var sinv := _sinv(pos)
		if not sinv:
			continue
		var slot := sinv.get_slot(_sidx(pos))
		_slots[pos].set_item(
			slot.item_data if not slot.is_empty() else null,
			slot.quantity,
			slot.physical if not slot.is_empty() else [])

## Handle window-specific input.  Return true to consume the event.
func _handle_input(_event: InputEvent) -> bool: return false

## Override to snap the drag ghost to the controller cursor slot.
func _get_ctrl_cursor_pos() -> Vector2:
	return get_viewport().get_mouse_position()

# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_ctrl_nav = false
		return
	if _handle_input(event):
		return
	if event.is_action_pressed("ui_cancel"):
		if not _picked_items.is_empty():
			_cancel_drag()
			_refresh()
		else:
			_close()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	if _drag_panel and _drag_panel.visible:
		_drag_root.position = _get_drag_pos()
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
		if _picked_items.is_empty():
			_picked_data        = null
			_drag_panel.visible = false

# ── Shell ──────────────────────────────────────────────────────────────────────

func _build_shell() -> void:
	var scrim := ColorRect.new()
	scrim.color        = UIStyle.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				if not _picked_items.is_empty(): _drop_held_items(); _refresh()
				else: _close()
			MOUSE_BUTTON_RIGHT:
				if _picked_items.size() > 1: _drop_one_held_item(); _refresh()
	)
	add_child(scrim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 8, 18))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	if _window_layout() == Layout.CENTERED:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.add_child(_panel)
	else:
		var a := _window_anchors()
		_panel.anchor_left   = a[0]; _panel.anchor_top    = a[1]
		_panel.anchor_right  = a[2]; _panel.anchor_bottom = a[3]
		add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	if _window_layout() == Layout.ANCHORED:
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)

	_title_row = HBoxContainer.new()
	_title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_title_row)
	var title_lbl := UIStyle.make_label(_window_title(), UIStyle.SIZE_LG, UIStyle.ON_SURFACE, true)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_row.add_child(title_lbl)

	vbox.add_child(HSeparator.new())

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 8)
	if _window_layout() == Layout.ANCHORED:
		_content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_vbox)
	_build_content(_content_vbox)

func _build_drag_overlay() -> void:
	_drag_root = Control.new()
	_drag_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_root.z_index      = 100
	add_child(_drag_root)

	_drag_panel = Panel.new()
	_drag_panel.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	_drag_panel.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_drag_panel.visible             = false
	_drag_root.add_child(_drag_panel)

	_drag_icon = TextureRect.new()
	_drag_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drag_icon.offset_left  =  6; _drag_icon.offset_top    =  6
	_drag_icon.offset_right = -6; _drag_icon.offset_bottom = -6
	_drag_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.add_child(_drag_icon)

	_drag_count = UIStyle.make_label("", UIStyle.SIZE_SM, Color.WHITE, true)
	_drag_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_drag_count.offset_left  = -28; _drag_count.offset_top    = -18
	_drag_count.offset_right =  -3; _drag_count.offset_bottom =  -3
	_drag_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_drag_count.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_drag_panel.add_child(_drag_count)

# ── Slot builder ───────────────────────────────────────────────────────────────

## Build one slot widget at [pos], register it in the base _slots[] array, and
## wire all mouse events.  Optionally also writes it into a subclass [slots] array
## at the same index (pass [] to skip).
##
## Call from _build_content().  For the player-inventory section use
## _build_player_section() instead; it calls _build_slot() internally.
func _build_slot(parent: Control, pos: int, slots: Array = []) -> ItemSlotWidget:
	var w := ItemSlotWidget.new()
	parent.add_child(w)

	# Register in base array.
	if _slots.size() <= pos:
		_slots.resize(pos + 1)
	_slots[pos] = w
	_slot_count = maxi(_slot_count, pos + 1)

	# Optional subclass array (legacy callers pass their own _slots array).
	if not slots.is_empty() and pos < slots.size():
		slots[pos] = w

	var i2 := pos
	w.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		_ctrl_nav = false
		var now_ms := Time.get_ticks_msec()

		# Double-click: pick up slot then collect all matching.
		if ev.button_index == MOUSE_BUTTON_LEFT \
				and _last_click_slot == i2 \
				and (now_ms - _last_click_msec) <= DCLICK_MS:
			_clear_split()
			ItemTooltip.hide()
			if _picked_items.is_empty():
				var sinv := _sinv(i2)
				if sinv:
					var src := sinv.get_slot(_sidx(i2))
					if not src.is_empty():
						var taken := sinv.take_items(_sidx(i2), src.quantity)
						for item in taken:
							if is_instance_valid(item): item.visible = false
						_picked_items.append_array(taken)
						if not taken.is_empty():
							_picked_data        = taken[0].item_data
							_drag_panel.visible = true
							_drag_root.position = _get_drag_pos()
			if not _picked_items.is_empty() and _picked_data != null:
				_double_click_collect(_picked_data)
			_last_click_slot = -1
			return

		# Shift+click: quick transfer via controller.
		if ev.shift_pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and _picked_items.is_empty():
			var sinv := _sinv(i2)
			if sinv:
				var slot := sinv.get_slot(_sidx(i2))
				if not slot.is_empty():
					var items := sinv.take_items(_sidx(i2), slot.quantity)
					var leftover := _quick_transfer(items, i2)
					for item in leftover:
						if is_instance_valid(item): sinv.add(item)
					_refresh()
			_last_click_slot = -1
			return

		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.shift_pressed:
			_last_click_slot = i2
			_last_click_msec = now_ms

		if _picked_items.is_empty():
			match ev.button_index:
				MOUSE_BUTTON_LEFT:  _left_activate(i2)
				MOUSE_BUTTON_RIGHT: _right_activate(i2)
		else:
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
			# On first move away from the source slot, also place one there.
			if _split_slots.size() == 1 and not _picked_items.is_empty():
				var ps   := _split_pending_slot
				var psinv := _sinv(ps)
				var init := psinv.get_slot(_sidx(ps))
				if (init.is_empty() or init.item_data.id == _picked_data.id) \
						and not init.is_full() and _controller.can_insert(ps, _picked_data):
					_picked_items.append_array(psinv.place_items(_sidx(ps),
						[_picked_items.pop_back()] as Array[PhysicalItem]))
			if not _picked_items.is_empty():
				var rsinv := _sinv(i2)
				var rs    := rsinv.get_slot(_sidx(i2))
				if (rs.is_empty() or rs.item_data.id == _picked_data.id) \
						and not rs.is_full() and _controller.can_insert(i2, _picked_data):
					_picked_items.append_array(rsinv.place_items(_sidx(i2),
						[_picked_items.pop_back()] as Array[PhysicalItem]))
			if _picked_items.is_empty(): _picked_data = null; _drag_panel.visible = false
			else: _update_drag_visual()
			_refresh()
			_split_slots.append(i2)

		elif lmb_drag:
			_split_mode = true
			for slot_pos in _split_slots:
				var qty: int = _lmb_placed.get(slot_pos, 0)
				if qty > 0:
					_picked_items.append_array(_sinv(slot_pos).take_items(_sidx(slot_pos), qty))
			_lmb_placed.clear()
			var all_slots := _split_slots.duplicate()
			all_slots.append(i2)
			var per_slot := maxi(1, _picked_items.size() / all_slots.size())
			for slot_pos in all_slots:
				if _picked_items.is_empty(): break
				var lsinv := _sinv(slot_pos)
				var ls    := lsinv.get_slot(_sidx(slot_pos))
				if (ls.is_empty() or ls.item_data.id == _picked_data.id) \
						and _controller.can_insert(slot_pos, _picked_data):
					var n := mini(per_slot, _picked_items.size())
					var to_place: Array[PhysicalItem] = []
					for _ii in n:
						if _picked_items.is_empty(): break
						to_place.append(_picked_items.pop_back())
					var leftover := lsinv.place_items(_sidx(slot_pos), to_place)
					_picked_items.append_array(leftover)
					_lmb_placed[slot_pos] = to_place.size() - leftover.size()
			_split_slots.append(i2)
			if _picked_items.is_empty() and per_slot == 1:
				_picked_data = null; _drag_panel.visible = false; _clear_split()
			else:
				_update_drag_visual(); _drag_panel.visible = true
			_refresh()

		if not _picked_items.is_empty():
			ItemTooltip.hide()
	)

	w.mouse_exited.connect(func() -> void:
		if _hovered_slot == i2:
			_hovered_slot = -1
	)
	return w

# ── Player-inventory section ───────────────────────────────────────────────────

## Append a separator + full player inventory grid (main 3×8 + hotbar) to [vbox].
## Call at the END of _build_content() after building all external slots.
##
## This method seals _external_slot_count to the current slot count, so
## _sinv() / _sidx() automatically route subsequent slot positions to _player_inv.
## Connect _player_inv in _on_opened() after calling open().
func _build_player_section(vbox: VBoxContainer) -> void:
	_external_slot_count = _slot_count   # everything built so far = external

	vbox.add_child(HSeparator.new())

	var lbl := UIStyle.make_label("INVENTORY", UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM)
	vbox.add_child(lbl)

	# Main 3×8 grid
	var main_grid := VBoxContainer.new()
	main_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(main_grid)
	for r in Inventory.ROWS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		main_grid.add_child(hbox)
		for c in Inventory.COLS:
			_build_slot(hbox, _external_slot_count + r * Inventory.COLS + c)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Hotbar row(s)
	var hotbar_grid := VBoxContainer.new()
	hotbar_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(hotbar_grid)
	for hr in Inventory.HOTBAR_ROWS:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		hotbar_grid.add_child(hbox)
		for hc in Inventory.HOTBAR_COLS:
			_build_slot(hbox, _external_slot_count + Inventory.MAIN_SLOTS + hr * Inventory.HOTBAR_COLS + hc)

# ── Drag helpers ───────────────────────────────────────────────────────────────

func _clear_split() -> void:
	_split_button       = -1
	_split_pending_slot = -1
	_split_mode         = false
	_split_slots.clear()
	_lmb_placed.clear()

func _cancel_drag() -> void:
	_clear_split()
	if not _picked_items.is_empty():
		# Return held items to the player inventory if available, otherwise primary.
		var fallback := _player_inv if _player_inv != null else _inv
		if fallback:
			for item in _picked_items:
				if is_instance_valid(item): fallback.add(item)
		_picked_items.clear()
		_picked_data = null
	if _drag_panel:
		_drag_panel.visible = false

func _drop_item(item: PhysicalItem) -> void:
	if not is_instance_valid(item):
		return
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

func _drop_one_held_item() -> void:
	_clear_split()
	if _picked_items.is_empty():
		return
	_drop_item(_picked_items.pop_back())
	if _picked_items.is_empty():
		_picked_data = null; _drag_panel.visible = false
	else:
		_update_drag_visual()
	_refresh()

func _drop_held_items() -> void:
	_clear_split()
	for item in _picked_items:
		_drop_item(item)
	_picked_items.clear()
	_picked_data        = null
	_drag_panel.visible = false
	_refresh()

func _get_drag_pos() -> Vector2:
	if _ctrl_nav:
		return _get_ctrl_cursor_pos() - Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
	return get_viewport().get_mouse_position() - Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)

func _update_drag_visual() -> void:
	if _picked_data == null or _picked_items.is_empty():
		return
	var c := _picked_data.color
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 0.95)
	s.border_color = UIStyle.PRIMARY
	s.set_border_width_all(2)
	_drag_panel.add_theme_stylebox_override("panel", s)
	_drag_count.text   = str(_picked_items.size()) if _picked_items.size() > 1 else ""
	_drag_icon.texture = _picked_data.icon

## Shift-click routing — calls controller with the source inventory so it knows
## which direction to transfer (external→player or player→external).
func _quick_transfer(items: Array[PhysicalItem], from_pos: int) -> Array[PhysicalItem]:
	if _controller:
		return _controller.quick_transfer(items, from_pos, _sinv(from_pos))
	return items

# ── Slot interactions ──────────────────────────────────────────────────────────

func _left_activate(pos: int) -> void:
	var sinv := _sinv(pos)
	var sidx := _sidx(pos)
	if not sinv: return
	var slot := sinv.get_slot(sidx)

	if _picked_items.is_empty():
		if not slot.is_empty() and _controller.can_take(pos):
			ItemTooltip.hide()
			var taken := sinv.take_items(sidx, slot.quantity)
			if not taken.is_empty():
				_picked_items = taken
				_picked_data  = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
				_drag_panel.visible = true
				_drag_root.position = _get_drag_pos()
	else:
		if slot.is_empty() or slot.item_data.id == _picked_data.id:
			if _controller.can_insert(pos, _picked_data):
				_picked_items = sinv.place_items(sidx, _picked_items)
				if _picked_items.is_empty(): _picked_data = null; _drag_panel.visible = false
				else: _update_drag_visual()
		elif _controller.can_take(pos) and _controller.can_insert(pos, _picked_data):
			# Different type — swap.
			var swapped  := sinv.take_items(sidx, slot.quantity)
			var leftover := sinv.place_items(sidx, _picked_items)
			_picked_items = swapped
			_picked_items.append_array(leftover)
			if _picked_items.is_empty():
				_picked_data = null; _drag_panel.visible = false
			else:
				_picked_data = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
	_refresh()

func _right_activate(pos: int) -> void:
	var sinv := _sinv(pos)
	var sidx := _sidx(pos)
	if not sinv: return
	var slot := sinv.get_slot(sidx)

	if _picked_items.is_empty():
		if not slot.is_empty() and _controller.can_take(pos):
			ItemTooltip.hide()
			var taken := sinv.take_items(sidx, (slot.quantity + 1) / 2)
			if not taken.is_empty():
				_picked_items = taken
				_picked_data  = _picked_items[0].item_data
				for item in _picked_items:
					if is_instance_valid(item): item.visible = false
				_update_drag_visual()
				_drag_panel.visible = true
				_drag_root.position = _get_drag_pos()
	else:
		if (slot.is_empty() or slot.item_data.id == _picked_data.id) \
				and not slot.is_full() and _controller.can_insert(pos, _picked_data):
			var one: Array[PhysicalItem] = [_picked_items.pop_back()]
			var leftover := sinv.place_items(sidx, one)
			if not leftover.is_empty(): _picked_items.append(leftover[0])
			if _picked_items.is_empty(): _picked_data = null; _drag_panel.visible = false
			else: _update_drag_visual()
	_refresh()

func _double_click_collect(data: ItemData) -> void:
	if not data: return
	var max_stack := data.carry_stack
	for pos in _slot_count:
		if _picked_items.size() >= max_stack: break
		var sinv := _sinv(pos)
		if not sinv: continue
		var slot := sinv.get_slot(_sidx(pos))
		if not slot.is_empty() and slot.item_data.id == data.id:
			var taken := sinv.take_items(_sidx(pos), max_stack - _picked_items.size())
			for item in taken:
				if is_instance_valid(item): item.visible = false
			_picked_items.append_array(taken)
	if not _picked_items.is_empty():
		_picked_data = data
		_update_drag_visual()
		_drag_panel.visible = true
		_drag_root.position = _get_drag_pos()
	_refresh()

func _commit_split() -> void:
	if _split_slots.is_empty() or _picked_items.is_empty(): return
	if _split_button != MOUSE_BUTTON_LEFT:
		for slot_pos in _split_slots:
			if _picked_items.is_empty(): break
			var sinv := _sinv(slot_pos)
			var slot := sinv.get_slot(_sidx(slot_pos))
			if (slot.is_empty() or slot.item_data.id == _picked_data.id) \
					and not slot.is_full() and _controller.can_insert(slot_pos, _picked_data):
				var leftover := sinv.place_items(_sidx(slot_pos),
					[_picked_items.pop_back()] as Array[PhysicalItem])
				_picked_items.append_array(leftover)
	if _picked_items.is_empty(): _picked_data = null; _drag_panel.visible = false
	else: _update_drag_visual()
	_refresh()

# ── Close hint ─────────────────────────────────────────────────────────────────

func _rebuild_close_hint() -> void:
	if _close_hint:
		_close_hint.get_parent().remove_child(_close_hint)
		_close_hint.queue_free()
		_close_hint = null
	_close_hint = UIStyle.make_badge("B" if InputHelper.is_joy() else "Esc", "Close")
	_title_row.add_child(_close_hint)

func _on_input_device_changed(using_joy: bool) -> void:
	if not visible: return
	_ctrl_nav = using_joy
	_apply_mouse_mode()
	_rebuild_close_hint()
