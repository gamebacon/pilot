class_name ItemSlotWidget
extends Control

## Reusable item-slot widget shared by hotbar, inventory, crafting and shop UIs.
##
## API:
##   set_item(data, qty, net_ids, durability)
##   set_active(on)     — gold accent border
##   set_cursor(on)     — cyan border (controller D-pad cursor)
##   set_badge(text, color)
##   clear()

var _panel: Panel        = null
var _icon:  TextureRect  = null
var _count: Label        = null
var _style: StyleBoxFlat = null

var item_data:   ItemData    = null
var _net_ids:    Array[int]  = []
var _durability: int         = -1
var _hovered:    bool        = false
var _is_active:  bool        = false
var _is_cursor:  bool        = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _panel != null: return

	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hovered = true
		if item_data:
			ItemTooltip.show_for(item_data, _net_ids, _durability))
	mouse_exited.connect(func() -> void:
		_hovered = false
		ItemTooltip.hide())

	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(5)
	_style.set_border_width_all(2)
	_style.bg_color     = UIStyle.SURFACE
	_style.border_color = UIStyle.SURFACE_BORDER

	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)

	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left  =  6; _icon.offset_top    =  6
	_icon.offset_right = -6; _icon.offset_bottom = -6
	_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_icon)

	_count = UIStyle.make_label("", UIStyle.SIZE_SM, Color.WHITE, true)
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left   = -28; _count.offset_top    = -18
	_count.offset_right  =  -3; _count.offset_bottom =  -3
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_count)

# ── Public API ────────────────────────────────────────────────────────────────

func set_item(data: ItemData, qty: int = 0, net_ids: Array[int] = [],
		durability: int = -1) -> void:
	_ensure_built()
	item_data    = data
	_net_ids     = net_ids
	_durability  = durability
	if data == null:
		_icon.texture   = null
		_count.text     = ""
		_style.bg_color = UIStyle.SURFACE
	else:
		_icon.texture = data.icon
		_count.text   = str(qty) if qty > 1 else ""
		var c := data.color
		_style.bg_color = Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, 0.90)
		_count.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_theme_stylebox_override("panel", _style)
	if _hovered:
		if item_data: ItemTooltip.show_for(item_data, _net_ids, _durability)
		else:         ItemTooltip.hide()

func set_active(on: bool) -> void:
	_is_active = on
	_update_border()

func set_cursor(on: bool) -> void:
	_is_cursor = on
	_update_border()

func _update_border() -> void:
	_ensure_built()
	if _is_active or _is_cursor:
		_style.border_color        = UIStyle.PRIMARY
		_style.border_width_bottom = 3 if _is_active else 2
	else:
		_style.border_color        = UIStyle.SURFACE_BORDER
		_style.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", _style)

func set_badge(text: String, color: Color = Color.WHITE) -> void:
	_ensure_built()
	_count.text = text
	_count.add_theme_color_override("font_color", color)

func clear() -> void:
	set_item(null)
	set_active(false)
