class_name UIStyle

# ── Palette ────────────────────────────────────────────────────────────────────
const COL_TEXT          := Color(0.90, 0.92, 0.95, 0.90)
const COL_TEXT_DIM      := Color(0.60, 0.62, 0.65, 0.80)
const COL_TEXT_HEADING  := Color(0.72, 0.72, 0.72, 1.00)
const COL_ACCENT        := Color(0.95, 0.80, 0.30, 1.00)
const COL_PANEL_BG      := Color(0.08, 0.08, 0.10, 0.88)
const COL_PANEL_BORDER  := Color(0.25, 0.25, 0.30, 0.60)

# ── Font ───────────────────────────────────────────────────────────────────────
const FONT := preload("res://ui/fonts/satoshi/Satoshi-Regular.ttf")
const FONT_BOLD := preload("res://ui/fonts/satoshi/Satoshi-Bold.ttf")
const FONT_LIGHT:= preload("res://ui/fonts/satoshi/Satoshi-Light.ttf")

# ── Font sizes ─────────────────────────────────────────────────────────────────
const SIZE_XS      := 9
const SIZE_SM      := 11
const SIZE_BODY    := 14
const SIZE_LG      := 18
const SIZE_HEADING := 22

# ── Controller face-button colors ──────────────────────────────────────────────
# Named after Xbox physical positions. _face_btn_color() swaps them for Nintendo layout.
const COL_BTN_A        := Color(0.18, 0.72, 0.38)  # green  (Xbox A / Nintendo B)
const COL_BTN_B        := Color(0.85, 0.22, 0.22)  # red    (Xbox B / Nintendo A)
const COL_BTN_X        := Color(0.88, 0.70, 0.15)  # yellow (Xbox X / Nintendo Y)
const COL_BTN_Y        := Color(0.22, 0.48, 0.92)  # blue   (Xbox Y / Nintendo X)
const COL_BTN_SHOULDER := Color(0.22, 0.22, 0.28)  # dark grey for L1/R1/L2/R2

# ── Input prompt factory ───────────────────────────────────────────────────────

## Builds a horizontal badge+text row.
## Parts starting with "@" are action names rendered as colored badges; all others are plain text.
static func make_row(parts: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for part in parts:
		var s := str(part)
		if s.begins_with("@"):
			row.add_child(make_prompt(s.substr(1)))
		else:
			var lbl := Label.new()
			lbl.text = s
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_override("font", FONT)
			lbl.add_theme_color_override("font_color", COL_TEXT)
			lbl.add_theme_font_size_override("font_size", SIZE_BODY)
			row.add_child(lbl)
	return row

## Clears [param container]'s children and rebuilds from [param rows].
## Each entry in rows is an Array of parts passed to make_row.
static func set_hint(container: Control, rows: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for parts in rows:
		container.add_child(make_row(parts))

## Returns a Control showing the input badge for [param action].
## Pass [param hint_text] to append a text label to the right.
static func make_prompt(action: String, hint_text: String = "") -> Control:
	var raw := InputHelper.action_label(action).trim_prefix("[").trim_suffix("]")
	return _build_row(_badge(raw), hint_text)

## Parses a pre-formatted hint string like "[E] Interact" into a visual row.
## Falls back to a plain Label if the string does not start with "[key]".
static func make_hint(hint: String) -> Control:
	if hint.begins_with("[") and "]" in hint:
		var end := hint.find("]")
		var raw  := hint.substr(1, end - 1)
		var text := hint.substr(end + 2)
		return _build_row(_badge(raw), text)
	var lbl := Label.new()
	lbl.text = hint
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_color_override("font_color", COL_TEXT)
	lbl.add_theme_font_size_override("font_size", SIZE_BODY)
	return lbl

## Apply standard world-space label styling to a Label3D.
static func style_world_label(lbl: Label3D, size: int = SIZE_BODY * 4) -> void:
	lbl.font_size = size
	lbl.modulate = COL_TEXT
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.double_sided = true
	lbl.no_depth_test = true

# ── Internal helpers ───────────────────────────────────────────────────────────

static func _build_row(badge: Control, hint_text: String) -> Control:
	if hint_text.is_empty():
		return badge
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(badge)
	var lbl := Label.new()
	lbl.text = hint_text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_color_override("font_color", COL_TEXT)
	lbl.add_theme_font_size_override("font_size", SIZE_BODY)
	row.add_child(lbl)
	return row

static func _badge(raw: String) -> Control:
	var pad := Input.get_connected_joypads().size() > 0
	return _controller_badge(raw) if pad else _keyboard_badge(raw)

static func _controller_badge(raw: String) -> Control:
	var is_wide_badge := raw in ["L2", "R2", "L1", "R1", 'View', 'Menu', 'Start']
	var size       := Vector2(30, 18) if is_wide_badge else Vector2(22, 22)
	var radius     := 5 if is_wide_badge else 11
	var style := StyleBoxFlat.new()
	style.bg_color = _face_btn_color(raw)
	style.set_corner_radius_all(radius)
	style.border_width_bottom = 2
	style.border_color = Color(0, 0, 0, 0.4)
	var panel := Panel.new()
	panel.custom_minimum_size = size
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lbl := Label.new()
	lbl.text = raw
	lbl.add_theme_font_override("font", FONT_BOLD)
	lbl.add_theme_font_size_override("font_size", SIZE_XS)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	center.add_child(lbl)
	panel.add_child(center)
	return panel

static func _keyboard_badge(raw: String) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.92)
	style.border_color = Color(0.55, 0.55, 0.62, 0.80)
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.set_corner_radius_all(5)
	var w := maxf(22.0, float(raw.length()) * 8.0 + 10.0)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(w, 22)
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lbl := Label.new()
	lbl.text = raw
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", SIZE_SM)
	lbl.add_theme_color_override("font_color", COL_TEXT)
	center.add_child(lbl)
	panel.add_child(center)
	return panel
static func _face_btn_color(raw: String) -> Color:
	var nintendo := InputHelper.NINTENDO_LAYOUT
	match raw:
		"A": return COL_BTN_B if nintendo else COL_BTN_A
		"B": return COL_BTN_A if nintendo else COL_BTN_B
		"X": return COL_BTN_Y if nintendo else COL_BTN_X
		"Y": return COL_BTN_X if nintendo else COL_BTN_Y
		_:   return COL_BTN_SHOULDER
