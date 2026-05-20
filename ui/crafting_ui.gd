extends CanvasLayer
class_name CraftingUI

## Minecraft-style crafting panel opened by interacting with the core.
## Three tabs: Materials | Tools | Weapons.
## Controller: L1/R1 switches tabs, stick/D-pad scrolls recipes, B closes.

const ITEM_SCENE := preload("res://items/physical_item.tscn")

const NAV_REPEAT := 0.15

# UI references built once in _build_shell
var _list:      VBoxContainer   = null
var _scroll:    ScrollContainer = null
var _close_btn: Button          = null

# Tab state
const TABS := [
	["materials", "Materials"],
	["tools",     "Tools"],
	["weapons",   "Weapons"],
]
var _active_tab: String = "materials"
var _tab_btns: Dictionary = {}   # tab_key -> Button

# Controller navigation — 2D slot grid
var _player:       Node                  = null
var _slot_rows:    Array                 = []   # Array of Array[ItemSlotWidget]
var _row_recipes:  Array[CraftingRecipe] = []
var _row_idx:      int                   = 0
var _col_idx:      int                   = 0
var _nav_timer:    float                 = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("crafting_ui")
	layer = 10
	hide()
	_build_shell()

func open(player: Node) -> void:
	_player    = player
	_row_idx   = 0
	_col_idx   = 0
	_nav_timer = 0.0
	_refresh()
	show()
	GameState.push_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if InputHelper.is_joy() else Input.MOUSE_MODE_VISIBLE)
	if InputHelper.is_joy():
		_update_ctrl_cursor()

func _close() -> void:
	ItemTooltip.hide()
	hide()
	GameState.pop_ui()
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
	call_deferred("_capture_mouse")

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Controller input ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not visible:
		return
	_nav_timer = max(0.0, _nav_timer - delta)
	if _nav_timer > 0.0:
		return
	var stick_y := Input.get_axis("move_forward", "move_back")
	if abs(stick_y) > 0.5:
		_nav_timer = NAV_REPEAT
		_move_row(1 if stick_y > 0 else -1)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up", true):
		_move_row(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down", true):
		_move_row(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left", true):
		_move_col(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right", true):
		_move_col(1)
		get_viewport().set_input_as_handled()
		return
	# L1 / R1 (or PageUp/PageDown on keyboard) cycle tabs
	var joy := event is InputEventJoypadButton
	if joy and (event as InputEventJoypadButton).pressed:
		# TODO: There should be no hardcoded input
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_B:
				_close()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_A:
				# Craft button with focus handles A natively; only fire here for slot nav
				if not _slot_rows.is_empty():
					var row: Array = _slot_rows[_row_idx]
					if row[_col_idx] is ItemSlotWidget and _row_idx < _row_recipes.size():
						_on_craft(_row_recipes[_row_idx])
				get_viewport().set_input_as_handled()
				return
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_tab(-1)
			get_viewport().set_input_as_handled()
			return
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_tab(1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_page_up"):
		_cycle_tab(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_page_down"):
		_cycle_tab(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _move_row(dir: int) -> void:
	if _slot_rows.is_empty():
		return
	_row_idx = (_row_idx + dir + _slot_rows.size()) % _slot_rows.size()
	_col_idx = 0
	_update_ctrl_cursor()

func _move_col(dir: int) -> void:
	if _slot_rows.is_empty():
		return
	var row: Array = _slot_rows[_row_idx]
	_col_idx = (_col_idx + dir + row.size()) % row.size()
	_update_ctrl_cursor()

func _cycle_tab(dir: int) -> void:
	var keys: Array = TABS.map(func(t): return t[0])
	var idx := keys.find(_active_tab)
	idx = (idx + dir + keys.size()) % keys.size()
	_switch_tab(keys[idx])

# ── Shell (built once) ────────────────────────────────────────────────────────

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.48)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.12, 0.97)
	style.border_color = Color(0.38, 0.38, 0.46, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left   = 0.28
	panel.anchor_right  = 0.72
	panel.anchor_top    = 0.08
	panel.anchor_bottom = 0.92
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "CRAFTING"
	title.add_theme_font_override("font", UIStyle.FONT)
	title.add_theme_font_size_override("font_size", UIStyle.SIZE_LG)
	title.add_theme_color_override("font_color", UIStyle.COL_TEXT_HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# Close button — focusable by mouse only; B closes from anywhere without focus.
	# Shows the B badge on controller, plain text on keyboard.
	_close_btn = Button.new()
	_close_btn.flat        = true
	_close_btn.focus_mode  = Control.FOCUS_NONE
	_close_btn.custom_minimum_size = Vector2(80, 32)
	_close_btn.pressed.connect(_close)
	if InputHelper.is_joy():
		_close_btn.text = ""
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		cc.clip_contents = false
		cc.add_child(UIStyle.make_badge("B", "Back"))
		_close_btn.add_child(cc)
	else:
		_close_btn.text = "Close"
	header.add_child(_close_btn)

	vbox.add_child(HSeparator.new())

	# Tab bar — L1/R1 shoulder badges (controller only) flank the tab buttons
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tab_row)

	if InputHelper.is_joy():
		tab_row.add_child(UIStyle._badge("L1"))

	var tab_bar := HBoxContainer.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_theme_constant_override("separation", 4)
	tab_row.add_child(tab_bar)

	if InputHelper.is_joy():
		tab_row.add_child(UIStyle._badge("R1"))

	var tab_group := ButtonGroup.new()
	for tab_def: Array in TABS:
		var key: String = tab_def[0]
		var label: String = tab_def[1]
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.button_group = tab_group
		btn.button_pressed = (key == _active_tab)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", UIStyle.FONT)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_switch_tab.bind(key))
		tab_bar.add_child(btn)
		_tab_btns[key] = btn

	vbox.add_child(HSeparator.new())

	# Scrollable recipe list
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus        = true
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)

# ── Tab switching ─────────────────────────────────────────────────────────────

func _switch_tab(tab: String) -> void:
	_active_tab = tab
	for key in _tab_btns:
		_tab_btns[key].set_pressed_no_signal(key == tab)
	_row_idx = 0
	_col_idx = 0
	_refresh()
	if InputHelper.is_joy():
		_update_ctrl_cursor()

# ── Refresh (called on open and after each craft) ─────────────────────────────

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_slot_rows.clear()
	_row_recipes.clear()

	if not _player:
		return

	var inv := _count_inventory()
	var recipes := CraftingRecipe.by_tab(_active_tab)

	if recipes.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No recipes in this category yet."
		empty_lbl.add_theme_font_override("font", UIStyle.FONT)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty_lbl)
	else:
		for recipe in recipes:
			_list.add_child(_make_row(recipe, inv))

	_row_idx = clampi(_row_idx, 0, maxi(_slot_rows.size() - 1, 0))
	_col_idx = clampi(_col_idx, 0, maxi((_slot_rows[_row_idx] as Array).size() - 1, 0) if not _slot_rows.is_empty() else 0)

# ── Recipe row ────────────────────────────────────────────────────────────────

func _make_row(recipe: CraftingRecipe, inv: Dictionary) -> Control:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 4)

	# Title label — result item name
	var result_data := ItemRegistry.get_item(recipe.result_id)
	var title := Label.new()
	title.text = result_data.display_name if result_data else recipe.result_id
	title.add_theme_font_override("font", UIStyle.FONT)
	title.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	title.add_theme_color_override("font_color", UIStyle.COL_TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(title)

	# Slot row
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.14, 0.18, 1.0)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(8)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", bg)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# Result slot
	var result_slot := ItemSlotWidget.new()
	result_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	if result_data:
		result_slot.set_item(result_data, recipe.result_count)
	hbox.add_child(result_slot)

	# Spacer between result and ingredients
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# Ingredient slots
	var can_craft := true
	var row_slots: Array = [result_slot]
	for ing_id: String in recipe.ingredients:
		var need: int = recipe.ingredients[ing_id]
		var have: int = inv.get(ing_id, 0)
		var enough    := have >= need or GameState.debug_mode
		if not enough:
			can_craft = false
		var ing_data  := ItemRegistry.get_item(ing_id)
		var ing_slot  := ItemSlotWidget.new()
		ing_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
		if ing_data:
			ing_slot.set_item(ing_data)
			ing_slot.set_badge("%d" % need,
				Color(0.50, 0.88, 0.50) if enough else Color(0.90, 0.35, 0.30))
		hbox.add_child(ing_slot)
		row_slots.append(ing_slot)

	# Craft button — last navigable element in the row
	var craft_btn := Button.new()
	craft_btn.text                  = "Craft"
	craft_btn.disabled              = not can_craft
	craft_btn.custom_minimum_size   = Vector2(72, 0)
	craft_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	craft_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	craft_btn.focus_mode            = Control.FOCUS_ALL
	craft_btn.add_theme_stylebox_override("focus", UIStyle.make_focus_style())
	craft_btn.pressed.connect(_on_craft.bind(recipe))
	hbox.add_child(craft_btn)

	row_slots.append(craft_btn)
	_slot_rows.append(row_slots)
	_row_recipes.append(recipe)

	return outer

# ── Craft action ──────────────────────────────────────────────────────────────

func _on_craft(recipe: CraftingRecipe) -> void:
	if not _player:
		return

	if not GameState.debug_mode:
		var inv := _count_inventory()
		for ing_id: String in recipe.ingredients:
			if inv.get(ing_id, 0) < (recipe.ingredients[ing_id] as int):
				return
		for ing_id: String in recipe.ingredients:
			for i in (recipe.ingredients[ing_id] as int):
				_remove_one(ing_id)

	var result_data := ItemRegistry.get_item(recipe.result_id)
	if result_data:
		for i in recipe.result_count:
			var item := ITEM_SCENE.instantiate() as PhysicalItem
			item.item_data = result_data
			get_tree().current_scene.add_child(item)
			item.global_position = _player.global_position + Vector3(0, 0.6, 0)
			if not _player.pick_up(item):
				item.scale           = Vector3.ONE
				item.collision_layer = 1
				item.collision_mask  = 1
				item.freeze          = false

	var scroll_pos := _scroll.scroll_vertical
	_refresh()
	_scroll.scroll_vertical = scroll_pos
	if InputHelper.is_joy():
		_update_ctrl_cursor()

# ── Controller cursor + tooltip ───────────────────────────────────────────────

func _update_ctrl_cursor() -> void:
	for row in _slot_rows:
		for el in row:
			if el is ItemSlotWidget:
				(el as ItemSlotWidget).set_cursor(false)
	if _slot_rows.is_empty():
		ItemTooltip.hide()
		return
	var row: Array = _slot_rows[_row_idx]
	var el = row[_col_idx]
	_scroll.ensure_control_visible(el as Control)
	if el is ItemSlotWidget:
		var focused := get_viewport().gui_get_focus_owner()
		if focused: focused.release_focus()
		var slot := el as ItemSlotWidget
		slot.set_cursor(true)
		if slot.item_data:
			ItemTooltip.show_for(slot.item_data, [], slot)
		else:
			ItemTooltip.hide()
	elif el is Button:
		(el as Button).grab_focus()
		ItemTooltip.hide()

# ── Helpers ───────────────────────────────────────────────────────────────────

# TODO: wtf is this? shouldn't be an internal inv func?
func _count_inventory() -> Dictionary:
	var counts := {}
	if not _player:
		return counts
	for item in _player.inventory.items:
		if item.item_data:
			var id: String = item.item_data.id
			counts[id] = counts.get(id, 0) + 1
	return counts

# TODO: wtf is this? shouldn't be an internal inv func?
func _remove_one(item_id: String) -> void:
	for item in _player.inventory.items:
		if item.item_data and item.item_data.id == item_id:
			_player.inventory.remove(item)
			item.queue_free()
			_player._reposition_carried()
			return
