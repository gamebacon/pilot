extends InventoryWindow
class_name CraftingUI

## Crafting panel — opened by interacting with the Core.
## Three tabs (Materials / Tools / Weapons) with L1/R1 / Page Up / Page Down.
## Controller: stick or D-pad scrolls recipes; ui_accept crafts the selected row.

const ITEM_SCENE := preload("res://items/physical_item.tscn")
const NAV_REPEAT := 0.15

const TABS := [
	["materials", "Materials"],
	["tools",     "Tools"],
	["weapons",   "Weapons"],
]

var _list:       VBoxContainer   = null
var _scroll:     ScrollContainer = null
var _tab_btns:   Dictionary      = {}   # tab_key → Button

var _active_tab: String = "materials"
var _slot_rows:  Array  = []            # Array of Array[ItemSlotWidget|Button]
var _row_recipes: Array[CraftingRecipe] = []
var _row_idx:    int    = 0
var _col_idx:    int    = 0
var _nav_timer:  float  = 0.0

# ── InventoryWindow overrides ──────────────────────────────────────────────────

func _window_title()  -> String:       return "CRAFTING"
func _window_layout() -> Layout:       return Layout.ANCHORED
func _window_anchors() -> Array[float]: return [0.28, 0.08, 0.72, 0.92]

func _build_content(vbox: VBoxContainer) -> void:
	# Tab bar — L1/R1 badges flank tabs on controller
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
		var key: String   = tab_def[0]
		var label: String = tab_def[1]
		var btn := Button.new()
		btn.text                  = label
		btn.toggle_mode           = true
		btn.button_group          = tab_group
		btn.button_pressed        = (key == _active_tab)
		btn.custom_minimum_size   = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		btn.focus_mode            = Control.FOCUS_NONE
		btn.add_theme_font_override("font", UIStyle.FONT)
		btn.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
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

func _on_opened() -> void:
	_row_idx   = 0
	_col_idx   = 0
	_nav_timer = 0.0
	_inv       = _player.inventory if _player else null
	_refresh()
	if _ctrl_nav:
		_update_ctrl_cursor()

func _on_closed() -> void:
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_slot_rows.clear()
	_row_recipes.clear()
	if not _player:
		return
	var inv     := _count_inventory()
	var recipes := CraftingRecipe.by_tab(_active_tab)
	if recipes.is_empty():
		var lbl := UIStyle.make_label("No recipes in this category yet.", UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(lbl)
	else:
		for recipe in recipes:
			_list.add_child(_make_recipe_row(recipe, inv))
	_row_idx = clampi(_row_idx, 0, maxi(_slot_rows.size() - 1, 0))
	_col_idx = clampi(_col_idx, 0, maxi((_slot_rows[_row_idx] as Array).size() - 1, 0) if not _slot_rows.is_empty() else 0)

func _handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up",    true): _move_row(-1); get_viewport().set_input_as_handled(); return true
	if event.is_action_pressed("ui_down",  true): _move_row( 1); get_viewport().set_input_as_handled(); return true
	if event.is_action_pressed("ui_left",  true): _move_col(-1); get_viewport().set_input_as_handled(); return true
	if event.is_action_pressed("ui_right", true): _move_col( 1); get_viewport().set_input_as_handled(); return true
	if event.is_action_pressed("ui_accept"):
		if not _slot_rows.is_empty():
			var row: Array = _slot_rows[_row_idx]
			if row[_col_idx] is ItemSlotWidget and _row_idx < _row_recipes.size():
				_on_craft(_row_recipes[_row_idx])
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("craft_tab_prev"): _cycle_tab(-1); get_viewport().set_input_as_handled(); return true
	if event.is_action_pressed("craft_tab_next"): _cycle_tab( 1); get_viewport().set_input_as_handled(); return true
	return false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("crafting_ui")
	super._ready()

func _process(delta: float) -> void:
	super._process(delta)
	if not visible: return
	_nav_timer = max(0.0, _nav_timer - delta)
	if _nav_timer > 0.0: return
	var stick_y := Input.get_axis("move_forward", "move_back")
	if abs(stick_y) > 0.5:
		_nav_timer = NAV_REPEAT
		_move_row(1 if stick_y > 0 else -1)

# ── Tab switching ──────────────────────────────────────────────────────────────

func _switch_tab(tab: String) -> void:
	_active_tab = tab
	for key in _tab_btns:
		_tab_btns[key].set_pressed_no_signal(key == tab)
	_row_idx = 0; _col_idx = 0
	_refresh()
	if _ctrl_nav: _update_ctrl_cursor()

func _cycle_tab(dir: int) -> void:
	var keys: Array = TABS.map(func(t): return t[0])
	var idx := keys.find(_active_tab)
	_switch_tab(keys[(idx + dir + keys.size()) % keys.size()])

# ── Recipe row ─────────────────────────────────────────────────────────────────

func _make_recipe_row(recipe: CraftingRecipe, inv: Dictionary) -> Control:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 4)

	var result_data := ItemRegistry.get_item(recipe.result_id)
	var lbl := UIStyle.make_label(
		result_data.display_name if result_data else recipe.result_id,
		UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND_DIM)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(lbl)

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = UIStyle.SURFACE_VARIANT
	row_style.set_corner_radius_all(6)
	row_style.set_content_margin_all(8)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", row_style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# Result slot
	var result_slot := ItemSlotWidget.new()
	result_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	if result_data: result_slot.set_item(result_data, recipe.result_count)
	hbox.add_child(result_slot)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# Ingredient slots
	var can_craft  := true
	var row_slots: Array = [result_slot]
	for ing_id: String in recipe.ingredients:
		var need: int = recipe.ingredients[ing_id]
		var have: int = inv.get(ing_id, 0)
		var enough    := have >= need or GameState.debug_mode
		if not enough: can_craft = false
		var ing_data := ItemRegistry.get_item(ing_id)
		var ing_slot := ItemSlotWidget.new()
		ing_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
		if ing_data:
			ing_slot.set_item(ing_data)
			ing_slot.set_badge("%d" % need, UIStyle.STATUS_OK if enough else UIStyle.STATUS_WARN)
		hbox.add_child(ing_slot)
		row_slots.append(ing_slot)

	# Craft button
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

# ── Craft action ───────────────────────────────────────────────────────────────

func _on_craft(recipe: CraftingRecipe) -> void:
	if not _player: return
	if not GameState.debug_mode:
		for ing_id: String in recipe.ingredients:
			if _player.inventory.count_id(ing_id) < (recipe.ingredients[ing_id] as int): return
		for ing_id: String in recipe.ingredients:
			for _i in (recipe.ingredients[ing_id] as int):
				_player.inventory.remove_one_by_id(ing_id)
	var result_data := ItemRegistry.get_item(recipe.result_id)
	if result_data:
		var world := get_tree().get_first_node_in_group("world")
		for _i in recipe.result_count:
			var net_id := 0
			if world and NetworkManager.is_active():
				net_id = world.assign_item_id()
			var dur := (result_data as ToolItemData).durability_max if result_data is ToolItemData else -1
			if not _player.inventory.add(recipe.result_id, net_id, dur):
				# Inventory full — spawn in world
				var spawn_pos : Vector3 = _player.global_position + Vector3(0, 0.6, 0)
				if world:
					world.request_spawn_item(recipe.result_id, spawn_pos)
				else:
					var item := ITEM_SCENE.instantiate() as PhysicalItem
					item.item_data = result_data
					item.current_durability = dur
					get_tree().current_scene.add_child(item)
					item.global_position = spawn_pos
	var scroll_pos := _scroll.scroll_vertical
	_refresh()
	_scroll.scroll_vertical = scroll_pos
	if _ctrl_nav: _update_ctrl_cursor()

# ── Controller cursor ──────────────────────────────────────────────────────────

func _move_row(dir: int) -> void:
	if _slot_rows.is_empty(): return
	_row_idx = (_row_idx + dir + _slot_rows.size()) % _slot_rows.size()
	_col_idx = 0
	_update_ctrl_cursor()

func _move_col(dir: int) -> void:
	if _slot_rows.is_empty(): return
	var row: Array = _slot_rows[_row_idx]
	_col_idx = (_col_idx + dir + row.size()) % row.size()
	_update_ctrl_cursor()

func _update_ctrl_cursor() -> void:
	for row in _slot_rows:
		for el in row:
			if el is ItemSlotWidget:
				(el as ItemSlotWidget).set_cursor(false)
	if _slot_rows.is_empty():
		ItemTooltip.hide(); return
	var row: Array = _slot_rows[_row_idx]
	var el = row[_col_idx]
	_scroll.ensure_control_visible(el as Control)
	if el is ItemSlotWidget:
		if get_viewport().gui_get_focus_owner():
			get_viewport().gui_get_focus_owner().release_focus()
		var slot := el as ItemSlotWidget
		slot.set_cursor(true)
		if slot.item_data: ItemTooltip.show_for(slot.item_data, slot._net_ids, slot._durability, slot)
		else: ItemTooltip.hide()
	elif el is Button:
		(el as Button).grab_focus()
		ItemTooltip.hide()

# ── Inventory helpers ──────────────────────────────────────────────────────────

func _count_inventory() -> Dictionary:
	var counts := {}
	if not _player: return counts
	for i in Inventory.TOTAL_SLOTS:
		var slot : Inventory.Slot = _player.inventory.get_slot(i)
		if not slot.is_empty():
			counts[slot.item_id] = counts.get(slot.item_id, 0) + slot.quantity
	return counts
