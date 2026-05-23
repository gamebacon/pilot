extends CanvasLayer

var _inv: Inventory = null
var _player_found := false

var _slots: Array[ItemSlotWidget] = []

func _ready() -> void:
	add_to_group("hotbar_hud")
	_build()

func _process(_d: float) -> void:
	if not _player_found:
		var player := get_tree().get_first_node_in_group("player")
		if not player: return
		_player_found = true
		_inv = player.inventory
		_inv.changed.connect(_refresh)
		_refresh()

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
					ItemTooltip.show_for(slot.get_data(), slot.net_ids, slot.get_durability())
				else:
					ItemTooltip.hide()
		)
		w.mouse_exited.connect(func() -> void: ItemTooltip.hide())

	_refresh()

func _refresh() -> void:
	if not _inv: return
	var active_row := _inv.active_hotbar_row
	var active_col := _inv.active_slot
	for col in Inventory.HOTBAR_COLS:
		var slot := _inv.get_hotbar_slot(active_row, col)
		var data := slot.get_data() if not slot.is_empty() else null
		_slots[col].set_item(data, slot.quantity, slot.net_ids, slot.get_durability())
		_slots[col].set_active(col == active_col)

