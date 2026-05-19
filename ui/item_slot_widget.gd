class_name ItemSlotWidget
extends Control

## Reusable item-slot widget shared by hotbar, inventory, crafting and shop UIs.
##
## Default size: UIStyle.SLOT_SZ × UIStyle.SLOT_SZ.
## Set custom_minimum_size BEFORE adding to the scene tree to use a different size
## (e.g. UIStyle.SLOT_SZ_SM for crafting / shop rows).
##
## API:
##   set_item(data, qty)    — show an item icon and stack count
##   set_active(on)         — gold accent border + thick bottom (active hotbar slot)
##   set_cursor(on)         — cyan border (controller D-pad cursor in inventory)
##   set_badge(text, color) — override the badge text/color (e.g. "2/5" in red)
##   clear()                — empty slot, no highlight

var _panel: Panel        = null
var _icon:  TextureRect  = null
var _count: Label        = null
var _style: StyleBoxFlat = null

var item_data: ItemData = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_built()

## Build internal nodes on first use — called from _ready AND from every public
## API method so it is safe to call set_item() before the widget enters the tree.
func _ensure_built() -> void:
	if _panel != null:
		return

	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(UIStyle.SLOT_SZ, UIStyle.SLOT_SZ)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(5)
	_style.set_border_width_all(2)
	_style.bg_color     = Color(0.09, 0.09, 0.12, 0.80)
	_style.border_color = UIStyle.COL_PANEL_BORDER

	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)

	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left   =  6; _icon.offset_top    =  6
	_icon.offset_right  = -6; _icon.offset_bottom = -6
	_icon.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_icon)

	_count = Label.new()
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left   = -28; _count.offset_top    = -18
	_count.offset_right  =  -3; _count.offset_bottom =  -3
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_override("font", UIStyle.FONT_BOLD)
	_count.add_theme_font_size_override("font_size", UIStyle.SIZE_SM)
	_count.add_theme_color_override("font_color", Color.WHITE)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_count)

# ── Public API ────────────────────────────────────────────────────────────────

## Show [param data] with a stack-count badge.  Pass null to show an empty slot.
func set_item(data: ItemData, qty: int = 0) -> void:
	_ensure_built()
	item_data = data
	if data == null:
		_icon.texture   = null
		_count.text     = ""
		_style.bg_color = Color(0.09, 0.09, 0.12, 0.80)
	else:
		_icon.texture = data.icon
		_count.text   = str(qty) if qty > 1 else ""
		var c := data.color
		_style.bg_color = Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, 0.90)
		_count.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_theme_stylebox_override("panel", _style)

## Gold accent border + thicker bottom edge — marks the active hotbar slot.
func set_active(on: bool) -> void:
	_ensure_built()
	_style.border_color        = UIStyle.COL_ACCENT if on else UIStyle.COL_PANEL_BORDER
	_style.border_width_bottom = 3 if on else 2
	_panel.add_theme_stylebox_override("panel", _style)

## Cyan border — marks the controller D-pad cursor position in the inventory.
func set_cursor(on: bool) -> void:
	_ensure_built()
	_style.border_color        = Color(0.55, 0.88, 1.0, 1.0) if on else UIStyle.COL_PANEL_BORDER
	_style.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", _style)

## Override the badge text and colour — useful for "have / need" in crafting slots.
func set_badge(text: String, color: Color = Color.WHITE) -> void:
	_ensure_built()
	_count.text = text
	_count.add_theme_color_override("font_color", color)

## Reset to an empty, unhighlighted slot.
func clear() -> void:
	set_item(null)
	set_active(false)
