class_name UIStyle

# ── Inventory / hotbar slot sizing ────────────────────────────────────────────
const SLOT_SZ  := 48
const SLOT_GAP := 4

# ══════════════════════════════════════════════════════════════════════════════
# Color palette — the ONLY place raw Color() values appear in the codebase.
# All other files reference UIStyle.<NAME>. Never construct Color() elsewhere.
# ══════════════════════════════════════════════════════════════════════════════

# ── Primary — gold/amber ───────────────────────────────────────────────────────
# Active slots, focus rings, accent highlights.
const PRIMARY         := Color(0.95, 0.80, 0.30, 1.00)
const PRIMARY_VARIANT := Color(0.78, 0.62, 0.18, 1.00)  # hover / pressed
const ON_PRIMARY      := Color(0.08, 0.06, 0.02, 1.00)  # text on PRIMARY bg

# ── Secondary — sky blue ───────────────────────────────────────────────────────
# Controller d-pad cursor, interactive focus indicator.
const SECONDARY    := Color(0.45, 0.72, 1.00, 1.00)
const ON_SECONDARY := Color(0.04, 0.06, 0.12, 1.00)

# ── Background ─────────────────────────────────────────────────────────────────
const BACKGROUND        := Color(0.05, 0.05, 0.07, 1.00)
const ON_BACKGROUND     := Color(0.90, 0.92, 0.95, 0.90)  # body text / icons
const ON_BACKGROUND_DIM := Color(0.60, 0.62, 0.65, 0.80)  # secondary / hint text

# ── Surface ────────────────────────────────────────────────────────────────────
const SURFACE         := Color(0.08, 0.08, 0.10, 0.88)  # panels, slots, tooltips, badges
const SURFACE_VARIANT := Color(0.14, 0.14, 0.18, 1.00)  # raised cards within a panel
const SURFACE_BORDER  := Color(0.28, 0.28, 0.33, 0.70)
const SCRIM           := Color(0.00, 0.00, 0.00, 0.50)  # full-screen dim overlay
const ON_SURFACE      := Color(0.72, 0.72, 0.72, 1.00)  # heading text
const ON_SURFACE_DIM  := Color(0.45, 0.45, 0.50, 0.80)  # secondary / hint text on a surface

# ── Status — same hues as controller face buttons ──────────────────────────────
const STATUS_OK      := Color(0.25, 0.85, 0.45, 1.00)  # green  — success / A btn
const STATUS_WARN    := Color(0.90, 0.25, 0.25, 1.00)  # red    — danger  / B btn
const STATUS_CAUTION := Color(0.92, 0.78, 0.16, 1.00)  # yellow — caution / X btn
const STATUS_INFO    := Color(0.28, 0.55, 0.95, 1.00)  # blue   — info    / Y btn

const BTN_SHOULDER   := Color(0.22, 0.22, 0.28, 1.00)  # L1 / R1 / L2 / R2

# ── Font ───────────────────────────────────────────────────────────────────────
const FONT       := preload("res://ui/fonts/satoshi/Satoshi-Regular.ttf")
const FONT_BOLD  := preload("res://ui/fonts/satoshi/Satoshi-Bold.ttf")
const FONT_LIGHT := preload("res://ui/fonts/satoshi/Satoshi-Light.ttf")

# ── Font sizes ─────────────────────────────────────────────────────────────────
const SIZE_XS      := 9
const SIZE_SM      := 11
const SIZE_BODY    := 14
const SIZE_LG      := 18
const SIZE_HEADING := 22

# ── Label factory ─────────────────────────────────────────────────────────────

## Create a new Label with font, size, and colour wired up in one call.
## bold=true uses FONT_BOLD; add a FONT_LIGHT override after if needed.
static func make_label(text: String = "", size: int = SIZE_BODY, color: Color = ON_BACKGROUND, bold: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	_apply_label_style(lbl, size, color, bold)
	return lbl

## Apply font / size / colour to an existing Label (e.g. @onready nodes from a scene).
static func apply_label(lbl: Label, size: int = SIZE_BODY, color: Color = ON_BACKGROUND, bold: bool = false) -> void:
	_apply_label_style(lbl, size, color, bold)

static func _apply_label_style(lbl: Label, size: int, color: Color, bold: bool) -> void:
	lbl.add_theme_font_override("font", FONT_BOLD if bold else FONT)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)

# ── Panel style factory ────────────────────────────────────────────────────────

## Create a StyleBoxFlat with the standard panel appearance.
static func make_panel_style(bg: Color = SURFACE, border: Color = SURFACE_BORDER, radius: int = 8, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

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
			var lbl := make_label(s)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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

## Returns a badge using [param raw] directly — bypasses the InputMap lookup.
## Use this for labels that don't map to a Godot action (e.g. "L1", "R1", "B").
static func make_badge(raw: String, hint_text: String = "") -> Control:
	return _build_row(_badge(raw), hint_text)

## Parses a pre-formatted hint string like "[E] Interact" into a visual row.
## Falls back to a plain Label if the string does not start with "[key]".
static func make_hint(hint: String) -> Control:
	if hint.begins_with("[") and "]" in hint:
		var end := hint.find("]")
		var raw  := hint.substr(1, end - 1)
		var text := hint.substr(end + 2)
		return _build_row(_badge(raw), text)
	return make_label(hint)

## Returns a focus StyleBox that draws a bright outline *outside* the button rect
## so it's never clipped by the button's own background or a parent container.
static func make_focus_style(color: Color = PRIMARY) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center      = false
	s.border_color     = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(5)
	s.set_expand_margin_all(2)
	return s

## Create a new Button with standard font/colour wired up in one call.
static func make_button(text: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", FONT_BOLD)
	btn.add_theme_font_size_override("font_size", SIZE_BODY)
	btn.add_theme_color_override("font_color", ON_SURFACE)
	btn.add_theme_stylebox_override("focus", make_focus_style(PRIMARY))
	return btn

## Apply standard font/colour overrides to a LineEdit.
static func apply_line_edit(field: LineEdit) -> void:
	field.add_theme_font_override("font", FONT)
	field.add_theme_font_size_override("font_size", SIZE_BODY)
	field.add_theme_color_override("font_color", ON_SURFACE)
	field.add_theme_color_override("font_placeholder_color", ON_SURFACE_DIM)

## Apply standard world-space label styling to a Label3D.
static func style_world_label(lbl: Label3D, size: int = SIZE_BODY * 4) -> void:
	lbl.font_size          = size
	lbl.modulate           = ON_BACKGROUND
	lbl.outline_size       = 6
	lbl.outline_modulate   = Color(0, 0, 0, 0.85)
	lbl.double_sided       = true
	lbl.no_depth_test      = true

# ── Internal helpers ───────────────────────────────────────────────────────────

static func _build_row(badge: Control, hint_text: String) -> Control:
	if hint_text.is_empty():
		return badge
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(badge)
	var lbl := make_label(hint_text)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row

## Two badges separated by "/" with optional trailing label.
## Use for paired actions like L1/R1 cycle prompts.
static func make_badge_pair(raw_a: String, raw_b: String, hint_text: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_badge(raw_a))
	var sep := make_label("/", SIZE_SM, ON_BACKGROUND_DIM)
	sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sep)
	row.add_child(_badge(raw_b))
	if not hint_text.is_empty():
		var lbl := make_label(hint_text)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
	return row

static func _badge(raw: String) -> Control:
	return _controller_badge(raw) if InputHelper.is_joy() else _keyboard_badge(raw)

static func _controller_badge(raw: String) -> Control:
	var is_wide := raw in ["L2", "R2", "L1", "R1", "View", "Menu", "Start"]
	var sz      := Vector2(30, 18) if is_wide else Vector2(22, 22)
	var radius  := 5 if is_wide else 11
	var style   := StyleBoxFlat.new()
	style.bg_color            = _face_btn_color(raw)
	style.set_corner_radius_all(radius)
	style.border_width_bottom = 2
	style.border_color        = Color(0, 0, 0, 0.40)
	var panel := Panel.new()
	panel.custom_minimum_size = sz
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lbl := make_label(raw, SIZE_XS, Color.WHITE, true)
	center.add_child(lbl)
	panel.add_child(center)
	return panel

static func _keyboard_badge(raw: String) -> Control:
	var w     := maxf(22.0, float(raw.length()) * 8.0 + 10.0)
	var style := StyleBoxFlat.new()
	style.bg_color            = SURFACE
	style.border_color        = SURFACE_BORDER
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.set_corner_radius_all(5)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(w, 22)
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lbl := make_label(raw, SIZE_SM)
	center.add_child(lbl)
	panel.add_child(center)
	return panel

static func _face_btn_color(raw: String) -> Color:
	match raw:
		"A": return STATUS_OK
		"B": return STATUS_WARN
		"X": return STATUS_CAUTION
		"Y": return STATUS_INFO
		_:   return BTN_SHOULDER
