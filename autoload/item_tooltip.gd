extends Node

## Singleton tooltip for ItemData.
## show_for(data, net_ids, durability, anchor) — net_ids shown in debug mode only.

var _panel:  Panel         = null
var _vbox:   VBoxContainer = null
var _anchor: Control       = null

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	_build(layer)

func show_for(data: ItemData, net_ids: Array[int] = [], durability: int = -1,
		anchor: Control = null) -> void:
	if not data: return
	_anchor = anchor
	_populate(data, net_ids, durability)
	_panel.visible = true

func hide() -> void:
	if _panel:
		_panel.visible = false
	_anchor = null

func _process(_d: float) -> void:
	if not _panel or not _panel.visible: return
	if _anchor and is_instance_valid(_anchor):
		_position_near(_anchor)
	else:
		_position_mouse(get_viewport().get_mouse_position())

# ── Positioning ────────────────────────────────────────────────────────────────

func _position_mouse(mp: Vector2) -> void:
	_panel.reset_size()
	var sz := _panel.size
	var vp := get_viewport().get_visible_rect().size
	var x  := mp.x + 18.0
	var y  := mp.y + 18.0
	if x + sz.x > vp.x - 8.0: x = mp.x - sz.x - 8.0
	if y + sz.y > vp.y - 8.0: y = mp.y - sz.y - 8.0
	_panel.position = Vector2(x, y)

func _position_near(ctrl: Control) -> void:
	_panel.reset_size()
	var sz := _panel.size
	var vp := get_viewport().get_visible_rect().size
	var r  := ctrl.get_global_rect()
	var x  := r.end.x + 12.0
	if x + sz.x > vp.x - 8.0: x = r.position.x - sz.x - 12.0
	var y  := r.position.y
	if y + sz.y > vp.y - 8.0: y = vp.y - sz.y - 8.0
	_panel.position = Vector2(x, y)

# ── Content ────────────────────────────────────────────────────────────────────

func _populate(data: ItemData, net_ids: Array[int], durability: int) -> void:
	for c in _vbox.get_children():
		c.queue_free()

	var name_lbl := Label.new()
	name_lbl.text = data.display_name
	name_lbl.add_theme_font_override("font", UIStyle.FONT_BOLD)
	name_lbl.add_theme_font_size_override("font_size", UIStyle.SIZE_LG)
	name_lbl.add_theme_color_override("font_color", UIStyle.ON_SURFACE)
	_vbox.add_child(name_lbl)

	if not data.description.is_empty():
		var desc := Label.new()
		desc.text = data.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(200, 0)
		desc.add_theme_font_override("font", UIStyle.FONT_LIGHT)
		desc.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
		desc.add_theme_color_override("font_color", UIStyle.ON_BACKGROUND_DIM)
		_vbox.add_child(desc)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_vbox.add_child(sep)

	if data.mass > 0.0:      _stat("Mass",  "%.1f kg" % data.mass)
	if data.carry_stack > 1: _stat("Stack", "×%d"     % data.carry_stack)
	if data.price > 0:       _stat("Value", "$%d"      % data.price)

	if data is ToolItemData:
		var td  := data as ToolItemData
		var cur := durability if durability >= 0 else td.durability_max
		_stat("Type",       td.tool_type.capitalize())
		_stat("Tier",       td.level_name)
		_stat("Durability", "%d / %d" % [cur, td.durability_max])
		if td.attack_damage  > 0.0: _stat("Attack",  "%.0f dmg" % td.attack_damage)
		if td.harvest_damage > 0.0: _stat("Harvest", "%.0f dmg" % td.harvest_damage)

	if GameState.debug_mode:
		var dbg_sep := HSeparator.new()
		dbg_sep.add_theme_constant_override("separation", 4)
		_vbox.add_child(dbg_sep)
		if net_ids.is_empty():
			_stat("net_id", "— (no ids)")
		else:
			for i in net_ids.size():
				var nid_str := str(net_ids[i]) if net_ids[i] != 0 else "0  ⚠ untracked"
				_stat("[%d] net_id" % i, nid_str)

func _stat(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", UIStyle.FONT)
	lbl.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	lbl.add_theme_color_override("font_color", UIStyle.ON_BACKGROUND_DIM)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", UIStyle.FONT_BOLD)
	val.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	val.add_theme_color_override("font_color", UIStyle.ON_BACKGROUND)
	row.add_child(val)
	_vbox.add_child(row)

# ── Build ──────────────────────────────────────────────────────────────────────

func _build(layer: CanvasLayer) -> void:
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel",
		UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 6, 10))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible      = false
	layer.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_vbox)
