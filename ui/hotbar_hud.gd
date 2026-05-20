extends CanvasLayer

var _inv: Inventory = null
var _player_found := false

var _slots: Array[ItemSlotWidget] = []

var _tooltip:      Panel         = null
var _tooltip_vbox: VBoxContainer = null

func _ready() -> void:
	add_to_group("hotbar_hud")
	_build()

func _process(_d: float) -> void:
	if not _player_found:
		var player := get_tree().get_first_node_in_group("player")
		if not player:
			return
		_player_found = true
		_inv = player.inventory
		_inv.changed.connect(_refresh)
		_refresh()

	if _tooltip and _tooltip.visible:
		_position_tooltip(get_viewport().get_mouse_position())

func _build() -> void:
	var cols    := Inventory.HOTBAR_COLS
	var total_w := float(cols * (UIStyle.SLOT_SZ + UIStyle.SLOT_GAP) - UIStyle.SLOT_GAP)

	var slot_row := HBoxContainer.new()
	slot_row.anchor_left   = 0.5; slot_row.anchor_right  = 0.5
	slot_row.anchor_top    = 1.0; slot_row.anchor_bottom = 1.0
	slot_row.offset_left   = -total_w / 2.0; slot_row.offset_right  =  total_w / 2.0
	slot_row.offset_top    = -UIStyle.SLOT_SZ - 8; slot_row.offset_bottom = -8
	slot_row.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	slot_row.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(slot_row)

	for col in cols:
		var w := ItemSlotWidget.new()
		slot_row.add_child(w)
		_slots.append(w)

		var c2 := col
		w.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if _inv: _inv.set_active_hotbar_slot(c2)
		)
		w.mouse_entered.connect(func() -> void:
			if _inv:
				var slot := _inv.get_hotbar_slot(_inv.active_hotbar_row, c2)
				if not slot.is_empty():
					_show_tooltip(slot)
		)
		w.mouse_exited.connect(func() -> void:
			_hide_tooltip()
		)

	_tooltip = Panel.new()
	_tooltip.add_theme_stylebox_override("panel", UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 6, 10))
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index      = 100
	_tooltip.visible      = false
	add_child(_tooltip)

	_tooltip_vbox = VBoxContainer.new()
	_tooltip_vbox.add_theme_constant_override("separation", 4)
	_tooltip_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tooltip_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_tooltip.add_child(_tooltip_vbox)

	_refresh()

func _refresh() -> void:
	if not _inv:
		return
	var active_row := _inv.active_hotbar_row
	var active_col := _inv.active_slot
	for col in Inventory.HOTBAR_COLS:
		var slot := _inv.get_hotbar_slot(active_row, col)
		_slots[col].set_item(slot.item_data if not slot.is_empty() else null, slot.quantity)
		_slots[col].set_active(col == active_col)

# ── Tooltip ────────────────────────────────────────────────────────────────────
func _show_tooltip(slot: Inventory.Slot) -> void:
	_populate_tooltip(slot)
	_tooltip.visible = true
	_position_tooltip(get_viewport().get_mouse_position())

func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false

func _position_tooltip(mp: Vector2) -> void:
	_tooltip.reset_size()
	var sz := _tooltip.size
	var vp := get_viewport().get_visible_rect().size
	var x  := mp.x + 18.0
	var y  := mp.y - sz.y - 12.0
	if x + sz.x > vp.x - 8.0:
		x = mp.x - sz.x - 8.0
	y = clamp(y, 8.0, vp.y - sz.y - 8.0)
	_tooltip.position = Vector2(x, y)

func _populate_tooltip(slot: Inventory.Slot) -> void:
	for child in _tooltip_vbox.get_children():
		child.queue_free()
	var data := slot.item_data
	var name_lbl := UIStyle.make_label(data.display_name, UIStyle.SIZE_LG, UIStyle.ON_SURFACE, true)
	_tooltip_vbox.add_child(name_lbl)
	if not data.description.is_empty():
		var desc := UIStyle.make_label(data.description, UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM)
		desc.add_theme_font_override("font", UIStyle.FONT_LIGHT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(180, 0)
		_tooltip_vbox.add_child(desc)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_tooltip_vbox.add_child(sep)
	if data.mass > 0.0:      _add_stat("Mass",  "%.1f kg" % data.mass)
	if data.carry_stack > 1: _add_stat("Stack", "×%d"     % data.carry_stack)
	if data.price > 0:       _add_stat("Value", "$%d"      % data.price)
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
	var lbl := UIStyle.make_label(label, UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(UIStyle.make_label(value, UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND, true))
	_tooltip_vbox.add_child(row)
