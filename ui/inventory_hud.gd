extends InventoryWindow

## Player's own inventory window — single-inventory, controller-navigable.
## All drag/slot logic lives in InventoryController (via InventoryWindow).

func _window_title()  -> String: return "INVENTORY"
func _window_layout() -> Layout: return Layout.CENTERED

func _make_controller() -> InventoryController:
	return PlayerInventoryController.new()

func _ready() -> void:
	add_to_group("inventory_hud")
	super._ready()

# ── Open / close ───────────────────────────────────────────────────────────────

func toggle() -> void:
	if visible: _close()
	else:       open(get_tree().get_first_node_in_group("player"))

# ── Content ────────────────────────────────────────────────────────────────────

func _build_content(vbox: VBoxContainer) -> void:
	var main_grid := VBoxContainer.new()
	main_grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(main_grid)
	for r in Inventory.ROWS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		main_grid.add_child(hbox)
		for c in Inventory.COLS:
			_build_slot(hbox, r * Inventory.COLS + c)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
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
			_build_slot(hbox, Inventory.MAIN_SLOTS + hr * Inventory.HOTBAR_COLS + hc)

func _on_opened() -> void:
	_inv = _player.inventory if _player else null
	_controller.inv      = _inv
	_controller.nav_rows = Inventory.ROWS + Inventory.HOTBAR_ROWS
	_controller.nav_cols = Inventory.COLS
	_controller.reset_cursor()
	if _inv and not _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.connect(_on_inv_changed)
	_refresh()
	var hb := get_tree().get_first_node_in_group("hotbar_hud")
	if hb: hb.hide()

func _on_closed() -> void:
	if _inv and _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.disconnect(_on_inv_changed)
	var hb := get_tree().get_first_node_in_group("hotbar_hud")
	if hb: hb.show()

func _on_inv_changed() -> void:
	if visible: _refresh()

# ── Input ──────────────────────────────────────────────────────────────────────

func _handle_input(event: InputEvent) -> bool:
	# open_inventory also closes
	if event.is_action_pressed("open_inventory"):
		if _controller.drag and not _controller.drag.is_empty():
			_controller.cancel_drag()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return true

	var hs := _controller.hovered_slot
	# Hotbar number keys while hovering a slot
	if hs >= 0 and (_controller.drag == null or _controller.drag.is_empty()) and _inv:
		for slot_num in Inventory.HOTBAR_COLS:
			if event.is_action_pressed("hotbar_slot_%d" % (slot_num + 1)):
				var hotbar_idx := Inventory.MAIN_SLOTS \
					+ _inv.active_hotbar_row * Inventory.HOTBAR_COLS + slot_num
				if hs != hotbar_idx:
					var hov := _inv.get_slot(hs)
					var hot := _inv.get_slot(hotbar_idx)
					if not hov.is_empty() and not hot.is_empty() \
							and hov.item_id == hot.item_id and not hot.is_full():
						var taken:    Inventory.ItemStack = _inv.take_items(hs, hov.quantity)
						var leftover: Inventory.ItemStack = _inv.place_items(hotbar_idx, taken)
						_inv.add_drag(leftover)
					else:
						_inv.swap_slots(hs, hotbar_idx)
				_refresh()
				get_viewport().set_input_as_handled()
				return true

	# Q to drop hovered item
	if event.is_action_pressed("drop") and hs >= 0 \
			and (_controller.drag == null or _controller.drag.is_empty()) and _inv:
		var slot := _inv.get_slot(hs)
		if not slot.is_empty():
			var taken: Inventory.ItemStack = _inv.take_items(hs, 1)
			if not taken.is_empty():
				var player := get_tree().get_first_node_in_group("player") as Player
				if player:
					var nid := taken.net_ids[0] if not taken.net_ids.is_empty() else 0
					player.drop_item_data(taken.item_id, nid, taken.get_durability())
		_refresh()
		get_viewport().set_input_as_handled()
		return true

	return super._handle_input(event)

func _get_ctrl_cursor_pos() -> Vector2:
	var cur := _controller.cursor
	if cur >= 0 and cur < _slots.size() and _slots[cur] != null:
		return _slots[cur].global_position
	return get_viewport().get_mouse_position()

# ── Refresh ────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	super._refresh()
	if not _inv or not _ctrl_nav: return
	var cur := _controller.cursor
	for i: int in _slots.size():
		if _slots[i] != null:
			_slots[i].set_cursor(i == cur)
	var slot: Inventory.ItemStack = _inv.get_slot(cur)
	if not slot.is_empty() and cur < _slots.size() and _slots[cur] != null:
		ItemTooltip.show_for(slot.get_data(), slot.net_ids, slot.get_durability(), _slots[cur])
	else:
		ItemTooltip.hide()
