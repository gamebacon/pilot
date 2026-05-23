extends CanvasLayer
class_name InventoryWindow

## Base class for all inventory-style windows (chests, shops, crafting tables, …).
## Owns the UI shell, drag visual, and slot widget wiring.
## All slot interaction logic lives in InventoryController.

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

var _player:     Node      = null
var _inv:        Inventory = null
var _player_inv: Inventory = null
var _ctrl_nav:   bool      = false

# ── Slot map ───────────────────────────────────────────────────────────────────

var _slots:      Array[ItemSlotWidget] = []
var _slot_count: int                   = 0

# ── Controller ─────────────────────────────────────────────────────────────────

var _controller: InventoryController = null

func _make_controller() -> InventoryController:
	return InventoryController.new()

# ── Drag visual ────────────────────────────────────────────────────────────────

var _drag_root:  Control     = null
var _drag_panel: Panel       = null
var _drag_icon:  TextureRect = null
var _drag_count: Label       = null

# ── Lifecycle ──────────────────────────────────────────────────────────────────

const NAV_INITIAL: float = 0.35
const NAV_REPEAT:  float = 0.09

var _nav_dir:   Vector2i = Vector2i.ZERO
var _nav_timer: float    = 0.0

func _ready() -> void:
	layer = 10
	_controller = _make_controller()
	_controller.drag_changed.connect(_on_drag_changed)
	_controller.needs_refresh.connect(_refresh)
	_controller.cursor_moved.connect(_refresh)
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
	_controller.cancel_drag()
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
func _get_ctrl_cursor_pos() -> Vector2: return get_viewport().get_mouse_position()

func _handle_input(event: InputEvent) -> bool:
	if _controller.nav_rows == 0: return false

	if event.is_action_pressed("ui_left",  false): _start_nav(-1,  0); return true
	if event.is_action_pressed("ui_right", false): _start_nav( 1,  0); return true
	if event.is_action_pressed("ui_up",    false): _start_nav( 0, -1); return true
	if event.is_action_pressed("ui_down",  false): _start_nav( 0,  1); return true

	if event.is_action_pressed("ui_accept"):
		var now := Time.get_ticks_msec()
		var c   := _controller
		if c.last_click_slot == c.cursor \
				and (now - c.last_click_msec) <= InventoryController.DCLICK_MS:
			# Double-tap A: pick up whole stack then collect matching items
			c.clear_split()
			ItemTooltip.hide()
			if c.drag == null or c.drag.is_empty():
				var sv: Inventory = c.sinv(c.cursor)
				if sv:
					var src: Inventory.ItemStack = sv.get_slot(c.sidx(c.cursor))
					if not src.is_empty():
						c.drag = c._take_from(sv, c.sidx(c.cursor), src.quantity) \
								as Inventory.ItemStack
						c.drag_changed.emit()
			if c.drag and not c.drag.is_empty():
				c.double_click_collect(c.drag.item_id, _slot_count)
			c.last_click_slot = -1
		else:
			c.last_click_slot = c.cursor
			c.last_click_msec = now
			c.clear_split()
			c.left_activate(c.cursor)
		return true

	if event.is_action_pressed("inv_split"):
		_controller.clear_split()
		_controller.right_activate(_controller.cursor)
		return true

	if event.is_action_pressed("inv_quick_move"):
		var c := _controller
		if c.drag == null or c.drag.is_empty():
			var sv: Inventory = c.sinv(c.cursor)
			if sv:
				var slot: Inventory.ItemStack = sv.get_slot(c.sidx(c.cursor))
				if not slot.is_empty():
					c.shift_click_transfer(sv, c.sidx(c.cursor), slot.quantity, c.cursor)
		return true

	return false

func _start_nav(dx: int, dy: int) -> void:
	_nav_dir   = Vector2i(dx, dy)
	_nav_timer = NAV_INITIAL
	_ctrl_nav  = true
	_controller.navigate(dx, dy)

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible: return
	# Let mouse button events reach gui_input callbacks on slot widgets and the scrim.
	if event is InputEventMouseButton: return
	if event is InputEventMouseMotion:
		_ctrl_nav = false
		return
	# Intercept before Godot's GUI focus system can move focus to unintended controls.
	if _handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _controller.drag and not _controller.drag.is_empty():
			_controller.cancel_drag()
		else:
			_close()
		get_viewport().set_input_as_handled()

# ── Process ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not visible: return
	if _drag_panel and _drag_panel.visible:
		_drag_root.position = _get_drag_pos()

	# Controller nav repeat — poll held direction and fire at NAV_REPEAT rate.
	if _controller.nav_rows > 0:
		var dir := Vector2i.ZERO
		if   Input.is_action_pressed("ui_left"):  dir.x = -1
		elif Input.is_action_pressed("ui_right"): dir.x =  1
		if   Input.is_action_pressed("ui_up"):    dir.y = -1
		elif Input.is_action_pressed("ui_down"):  dir.y =  1
		if dir == Vector2i.ZERO:
			_nav_dir   = Vector2i.ZERO
			_nav_timer = 0.0
		elif dir != _nav_dir:
			# Direction changed mid-hold — _start_nav already fired for first press,
			# so only update tracking here without an extra navigate call.
			_nav_dir   = dir
			_nav_timer = NAV_INITIAL
		else:
			_nav_timer -= delta
			if _nav_timer <= 0.0:
				_nav_timer = NAV_REPEAT
				_controller.navigate(_nav_dir.x, _nav_dir.y)

	var c := _controller
	if c.split_button >= 0 and not Input.is_mouse_button_pressed(c.split_button):
		if c.split_mode and c.drag and not c.drag.is_empty():
			c.commit_split()
		elif c.split_pending_slot >= 0 and c.drag and not c.drag.is_empty() \
				and c.split_slots.size() <= 1:
			if c.split_button == MOUSE_BUTTON_LEFT:
				c.left_activate(c.split_pending_slot)
			else:
				c.right_activate(c.split_pending_slot)
		c.clear_split()
		if c.drag == null or c.drag.is_empty():
			c.drag = null; _drag_panel.visible = false

# ── Shell ──────────────────────────────────────────────────────────────────────

func _build_shell() -> void:
	var scrim := ColorRect.new()
	scrim.color        = UIStyle.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed): return
		var player := get_tree().get_first_node_in_group("player") as Player
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				if _controller.drag and not _controller.drag.is_empty():
					_controller.drop_all(player)
				else:
					_close()
			MOUSE_BUTTON_RIGHT:
				if _controller.drag and _controller.drag.quantity > 1:
					_controller.drop_one(player)
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
		_panel.anchor_left = a[0]; _panel.anchor_top    = a[1]
		_panel.anchor_right = a[2]; _panel.anchor_bottom = a[3]
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

func _build_slot(parent: Control, pos: int, slots: Array = []) -> ItemSlotWidget:
	var w := ItemSlotWidget.new()
	parent.add_child(w)
	if _slots.size() <= pos: _slots.resize(pos + 1)
	_slots[pos] = w
	_slot_count = maxi(_slot_count, pos + 1)
	if not slots.is_empty() and pos < slots.size():
		slots[pos] = w

	var i2 := pos
	w.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed): return
		_ctrl_nav = false
		var c   := _controller
		var now := Time.get_ticks_msec()

		# Double-click collect
		if ev.button_index == MOUSE_BUTTON_LEFT \
				and c.last_click_slot == i2 \
				and (now - c.last_click_msec) <= InventoryController.DCLICK_MS:
			c.clear_split()
			ItemTooltip.hide()
			if c.drag == null or c.drag.is_empty():
				var sv := c.sinv(i2)
				if sv:
					var src := sv.get_slot(c.sidx(i2))
					if not src.is_empty():
						c.drag = c._take_from(sv, c.sidx(i2), src.quantity) as Inventory.ItemStack
						if c.drag and not c.drag.is_empty():
							_drag_panel.visible = true
							_drag_root.position = _get_drag_pos()
			if c.drag and not c.drag.is_empty():
				c.double_click_collect(c.drag.item_id, _slot_count)
			c.last_click_slot = -1
			return

		# Shift-click transfer
		if ev.shift_pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and (c.drag == null or c.drag.is_empty()):
			var sv := c.sinv(i2)
			if sv:
				var slot := sv.get_slot(c.sidx(i2))
				if not slot.is_empty():
					_controller.shift_click_transfer(sv, c.sidx(i2), slot.quantity, i2)
			c.last_click_slot = -1
			return

		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.shift_pressed:
			c.last_click_slot = i2
			c.last_click_msec = now

		if c.drag == null or c.drag.is_empty():
			match ev.button_index:
				MOUSE_BUTTON_LEFT:  c.left_activate(i2)
				MOUSE_BUTTON_RIGHT: c.right_activate(i2)
		else:
			if c.split_button < 0 and \
					(ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				c.split_button       = ev.button_index
				c.split_pending_slot = i2
				c.split_slots.clear()
				c.split_slots.append(i2)
	)

	w.mouse_entered.connect(func() -> void:
		_controller.on_slot_enter(i2)
		if _controller.drag and not _controller.drag.is_empty():
			ItemTooltip.hide()
		else:
			var sv := _controller.sinv(i2)
			if sv:
				var slot := sv.get_slot(_controller.sidx(i2))
				if not slot.is_empty():
					ItemTooltip.show_for(slot.get_data(), slot.net_ids, slot.get_durability())
				else:
					ItemTooltip.hide()
	)
	w.mouse_exited.connect(func() -> void:
		if _controller.hovered_slot == i2:
			_controller.hovered_slot = -1
			ItemTooltip.hide()
	)
	return w

# ── Player-inventory section ───────────────────────────────────────────────────

func _build_player_section(vbox: VBoxContainer) -> void:
	_controller.external_slot_count = _slot_count
	var base := _slot_count   # first slot index belonging to the player inventory

	vbox.add_child(HSeparator.new())
	vbox.add_child(UIStyle.make_label("INVENTORY", UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM))

	var main_grid := VBoxContainer.new()
	main_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(main_grid)
	for r in Inventory.ROWS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		main_grid.add_child(hbox)
		for c in Inventory.COLS:
			_build_slot(hbox, base + r * Inventory.COLS + c)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var hotbar_grid := VBoxContainer.new()
	hotbar_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(hotbar_grid)
	for hr in Inventory.HOTBAR_ROWS:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		hotbar_grid.add_child(hbox)
		for hc in Inventory.HOTBAR_COLS:
			_build_slot(hbox, base + Inventory.MAIN_SLOTS + hr * Inventory.HOTBAR_COLS + hc)

# ── Refresh ────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	for pos in _slot_count:
		if pos >= _slots.size() or _slots[pos] == null: continue
		var sv := _controller.sinv(pos)
		if not sv: continue
		var slot := sv.get_slot(_controller.sidx(pos))
		_slots[pos].set_item(slot.get_data(), slot.quantity, slot.net_ids, slot.get_durability())
	# Keep tooltip in sync when slot contents change under the cursor
	var hs := _controller.hovered_slot
	if hs >= 0 and hs < _slots.size() and _slots[hs] != null \
			and (_controller.drag == null or _controller.drag.is_empty()):
		var sv := _controller.sinv(hs)
		if sv:
			var slot := sv.get_slot(_controller.sidx(hs))
			if not slot.is_empty():
				ItemTooltip.show_for(slot.get_data(), slot.net_ids, slot.get_durability())
			else:
				ItemTooltip.hide()

# ── Drag visual ────────────────────────────────────────────────────────────────

func _on_drag_changed() -> void:
	var c := _controller
	if c.drag == null or c.drag.is_empty():
		_drag_panel.visible = false
		return
	var data := c.drag.get_data()
	if not data: return
	var col := data.color
	var s   := StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.bg_color     = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.95)
	s.border_color = UIStyle.PRIMARY
	s.set_border_width_all(2)
	_drag_panel.add_theme_stylebox_override("panel", s)
	_drag_count.text   = str(c.drag.quantity) if c.drag.quantity > 1 else ""
	_drag_icon.texture = data.icon
	_drag_panel.visible = true
	_drag_root.position = _get_drag_pos()

func _get_drag_pos() -> Vector2:
	if _ctrl_nav:
		return _get_ctrl_cursor_pos() - Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)
	return get_viewport().get_mouse_position() - Vector2(UIStyle.SLOT_SZ * 0.5, UIStyle.SLOT_SZ * 0.5)

# ── Close hint ─────────────────────────────────────────────────────────────────

func _rebuild_close_hint() -> void:
	if _close_hint:
		_close_hint.get_parent().remove_child(_close_hint)
		_close_hint.queue_free()
		_close_hint = null

	if InputHelper.is_joy():
		_close_hint = UIStyle.make_badge("B", "Close")
		_title_row.add_child(_close_hint)

func _on_input_device_changed(using_joy: bool) -> void:
	if not visible: return
	_ctrl_nav = using_joy
	_apply_mouse_mode()
	_rebuild_close_hint()
