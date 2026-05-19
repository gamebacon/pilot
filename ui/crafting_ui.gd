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

# Controller navigation for recipe rows
var _player:    Node           = null
var _focusable: Array[Button]  = []
var _sel:       int            = 0
var _nav_timer: float          = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("crafting_ui")
	layer = 10
	hide()
	_build_shell()

func open(player: Node) -> void:
	_player    = player
	_sel       = 0
	_nav_timer = 0.0
	_refresh()
	show()
	GameState.push_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if InputHelper.is_joy() else Input.MOUSE_MODE_VISIBLE)
	if not _focusable.is_empty():
		_focusable[0].call_deferred("grab_focus")

func _close() -> void:
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
		_move_sel(1 if stick_y > 0 else -1)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up", true):
		_move_sel(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down", true):
		_move_sel(1)
		get_viewport().set_input_as_handled()
		return
	# L1 / R1 (or PageUp/PageDown on keyboard) cycle tabs
	var joy := event is InputEventJoypadButton
	if joy and (event as InputEventJoypadButton).pressed:
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

func _move_sel(dir: int) -> void:
	if _focusable.is_empty():
		return
	_sel = (_sel + dir + _focusable.size()) % _focusable.size()
	_focusable[_sel].grab_focus()
	_scroll.ensure_control_visible(_focusable[_sel])

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
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60, 1.0))
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

	var _l1 := _shoulder_badge("L1")
	if _l1:
		tab_row.add_child(_l1)

	var tab_bar := HBoxContainer.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_theme_constant_override("separation", 4)
	tab_row.add_child(tab_bar)

	var _r1 := _shoulder_badge("R1")
	if _r1:
		tab_row.add_child(_r1)

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
	_sel = 0
	_refresh()
	if not _focusable.is_empty():
		_focusable[0].call_deferred("grab_focus")

# ── Refresh (called on open and after each craft) ─────────────────────────────

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_focusable.clear()

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

	_sel = clampi(_sel, 0, maxi(_focusable.size() - 1, 0))

# ── Recipe row ────────────────────────────────────────────────────────────────

func _make_row(recipe: CraftingRecipe, inv: Dictionary) -> Control:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.14, 0.18, 1.0)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(10)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", bg)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = false

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# ── Result slot ───────────────────────────────────────────────────────────
	var result_data := ItemRegistry.get_item(recipe.result_id)
	var result_slot := ItemSlotWidget.new()
	result_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ_SM, UIStyle.SLOT_SZ_SM)
	result_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(result_slot)
	if result_data:
		result_slot.set_item(result_data, recipe.result_count)

	# ── Arrow ─────────────────────────────────────────────────────────────────
	var arrow := Label.new()
	arrow.text = "←"
	arrow.add_theme_font_override("font", UIStyle.FONT)
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(arrow)

	# ── Ingredients ───────────────────────────────────────────────────────────
	var ing_vbox := VBoxContainer.new()
	ing_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ing_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(ing_vbox)

	var can_craft := true
	for ing_id: String in recipe.ingredients:
		var need: int = recipe.ingredients[ing_id]
		var have: int = inv.get(ing_id, 0)
		if have < need and not GameState.debug_mode:
			can_craft = false

		var ing_data := ItemRegistry.get_item(ing_id)
		var ing_name := ing_data.display_name if ing_data else ing_id
		var enough   := have >= need or GameState.debug_mode

		var ing_row := HBoxContainer.new()
		ing_row.add_theme_constant_override("separation", 6)
		ing_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		ing_vbox.add_child(ing_row)

		# Small icon slot
		var ing_slot := ItemSlotWidget.new()
		ing_slot.custom_minimum_size = Vector2(UIStyle.SLOT_SZ_SM, UIStyle.SLOT_SZ_SM)
		ing_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ing_data:
			ing_slot.set_item(ing_data)
			ing_slot.set_badge("%d" % need,
				Color(0.50, 0.88, 0.50) if enough else Color(0.90, 0.35, 0.30))
		ing_row.add_child(ing_slot)

		# "Name  (have N)" text
		var text_col := VBoxContainer.new()
		text_col.add_theme_constant_override("separation", 1)
		text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ing_row.add_child(text_col)

		var ing_lbl := Label.new()
		ing_lbl.text = ing_name
		ing_lbl.add_theme_font_override("font", UIStyle.FONT)
		ing_lbl.add_theme_font_size_override("font_size", 13)
		ing_lbl.add_theme_color_override("font_color",
			Color(0.50, 0.88, 0.50) if enough else Color(0.90, 0.35, 0.30))
		text_col.add_child(ing_lbl)

		var have_lbl := Label.new()
		have_lbl.text = "have %d / need %d" % [have, need]
		have_lbl.add_theme_font_override("font", UIStyle.FONT)
		have_lbl.add_theme_font_size_override("font_size", 10)
		have_lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		text_col.add_child(have_lbl)

	# ── Craft button ──────────────────────────────────────────────────────────
	var craft_btn := Button.new()
	craft_btn.text                = "Craft"
	craft_btn.disabled            = not can_craft
	craft_btn.custom_minimum_size = Vector2(90, 0)
	craft_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft_btn.add_theme_stylebox_override("focus", UIStyle.make_focus_style())
	craft_btn.set_meta("recipe_id", recipe.result_id)
	craft_btn.pressed.connect(_on_craft.bind(recipe))
	_focusable.append(craft_btn)
	hbox.add_child(craft_btn)

	return panel

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

	var target_id  := recipe.result_id
	var scroll_pos := _scroll.scroll_vertical
	_refresh()
	_scroll.scroll_vertical = scroll_pos
	# Restore focus without letting follow_focus scroll the list.
	# Disable it first, grab focus (deferred), then re-enable (deferred after,
	# so it runs after grab_focus — call_deferred is FIFO).
	_scroll.follow_focus = false
	var found := false
	for i in _focusable.size():
		if _focusable[i].get_meta("recipe_id", "") == target_id:
			_sel = i
			_focusable[i].call_deferred("grab_focus")
			found = true
			break
	if not found and not _focusable.is_empty():
		_sel = clampi(_sel, 0, _focusable.size() - 1)
		_focusable[_sel].call_deferred("grab_focus")
	(func() -> void: _scroll.follow_focus = true).call_deferred()

# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns a wider, styled shoulder-button badge (L1/R1) when a controller is
## connected, or null on keyboard-only so the caller skips adding it.
func _shoulder_badge(label: String) -> Control:
	if not InputHelper.is_joy():
		return null
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.22, 0.22, 0.28, 1.0)
	bg.set_corner_radius_all(5)
	bg.content_margin_top    = 5
	bg.content_margin_bottom = 5
	bg.content_margin_left   = 14
	bg.content_margin_right  = 14
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", bg)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_override("font", UIStyle.FONT)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	panel.add_child(lbl)
	return panel

func _count_inventory() -> Dictionary:
	var counts := {}
	if not _player:
		return counts
	for item in _player.inventory.items:
		if item.item_data:
			var id: String = item.item_data.id
			counts[id] = counts.get(id, 0) + 1
	return counts

func _remove_one(item_id: String) -> void:
	for item in _player.inventory.items:
		if item.item_data and item.item_data.id == item_id:
			_player.inventory.remove(item)
			item.queue_free()
			_player._reposition_carried()
			return
