extends CanvasLayer
class_name ShopUI

@onready var panel: Panel                   = $Panel
@onready var scroll: ScrollContainer        = $Panel/VBox/Scroll
@onready var item_list: VBoxContainer       = $Panel/VBox/Scroll/ItemList
@onready var currency_label: Label          = $Panel/VBox/Header/CurrencyLabel
@onready var close_button: Button           = $Panel/VBox/Footer/CloseButton

var _current_shop: Node = null
var _first_button: Button = null

# Controller navigation — ordered list of every focusable button in the panel.
# Buy buttons are added in _add_row; close button is appended in open().
var _focusable: Array[Button] = []
var _sel: int = 0

const NAV_REPEAT := 0.15   # seconds between repeated scroll steps
var   _nav_timer := 0.0

const COL_DIM  := Color(0.60, 0.60, 0.60)
const COL_HEAD := Color(0.72, 0.72, 0.72)

func _ready() -> void:
	add_to_group("shop_ui")
	panel.hide()
	scroll.follow_focus = true
	close_button.pressed.connect(_on_close)
	GameState.currency_changed.connect(_update_currency)

func open(stock: Array[ItemData], shop: Node) -> void:
	_current_shop = shop
	_populate(stock)
	_update_currency(GameState.currency)
	close_button.text = "Close  %s" % InputHelper.action_label("ui_cancel")
	# Close button is always last in the navigation ring.
	_focusable.append(close_button)
	_sel = 0
	_nav_timer = 0.0
	panel.show()
	GameState.push_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not _focusable.is_empty():
		_focusable[0].call_deferred("grab_focus")

func _on_close() -> void:
	panel.hide()
	_current_shop = null
	GameState.pop_ui()

	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()

	call_deferred("_capture_mouse")

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Population ────────────────────────────────────────────────────────────────

func _populate(stock: Array[ItemData]) -> void:
	_first_button = null
	_focusable.clear()
	for child in item_list.get_children():
		child.queue_free()

	var blueprints: Array[ItemData] = []
	var by_category: Dictionary = {}   # category -> Array[ItemData]

	for item in stock:
		if item.is_blueprint:
			blueprints.append(item)
		else:
			var cat := item.category if item.category != "" else "General"
			if not by_category.has(cat):
				by_category[cat] = []
			by_category[cat].append(item)

	blueprints.sort_custom(func(a, b): return a.display_name < b.display_name)

	if blueprints.size() > 0:
		_add_section(GameConstants.CAT_BLUEPRINTS.to_upper())
		for item in blueprints:
			_add_row(item)

	# Emit categories in predefined order, then any unrecognised ones alphabetically
	var ordered: Array[String] = []
	for cat in GameConstants.MATERIAL_CATEGORY_ORDER:
		if by_category.has(cat):
			ordered.append(cat)
	for cat in by_category.keys():
		if not ordered.has(cat):
			ordered.append(cat)

	for cat in ordered:
		var items: Array = by_category[cat]
		items.sort_custom(func(a, b): return a.display_name < b.display_name)
		_add_section(cat.to_upper())
		for item in items:
			_add_row(item)

func _add_section(title: String) -> void:
	var sep := HSeparator.new()
	item_list.add_child(sep)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_HEAD)
	lbl.add_theme_constant_override("outline_size", 0)
	item_list.add_child(lbl)

func _add_row(item: ItemData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# ── Color swatch ──────────────────────────────────────────────────────────
	var swatch := ColorRect.new()
	swatch.color = item.color
	swatch.custom_minimum_size = Vector2(26, 26)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	# ── Name + subtitle ───────────────────────────────────────────────────────
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	col.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = _subtitle(item)
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", COL_DIM)
	col.add_child(sub_lbl)

	row.add_child(col)

	# ── Price ─────────────────────────────────────────────────────────────────
	var price_lbl := Label.new()
	price_lbl.text = "$%d" % item.price
	price_lbl.custom_minimum_size = Vector2(52, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(price_lbl)

	# ── Buy button ────────────────────────────────────────────────────────────
	var btn := Button.new()
	btn.text = "Buy"
	btn.custom_minimum_size = Vector2(58, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: _buy_item(item))
	if _first_button == null:
		_first_button = btn
	_focusable.append(btn)
	row.add_child(btn)

	item_list.add_child(row)

# ── Formatting ────────────────────────────────────────────────────────────────

func _subtitle(item: ItemData) -> String:
	if item.is_blueprint and item.blueprint_data:
		var n := item.blueprint_data.phase_names.size()
		return "%d-phase build" % n
	return _fmt_dims(item.size)

func _fmt_dims(s: Vector3) -> String:
	return "%s × %s × %s" % [_fmt_val(s.x), _fmt_val(s.y), _fmt_val(s.z)]

func _fmt_val(v: float) -> String:
	if v < 0.095:
		return "%d mm" % roundi(v * 1000.0)
	return "%.1f m" % v

# ── Buying ────────────────────────────────────────────────────────────────────

func _buy_item(item: ItemData) -> void:
	if not GameState.spend_currency(item.price):
		push_warning("Not enough money for %s ($%d)" % [item.display_name, item.price])
		return
	if _current_shop and _current_shop.has_method("spawn_item"):
		_current_shop.spawn_item(item)

func _update_currency(amount: int) -> void:
	currency_label.text = "$%d" % amount

# ── Controller navigation ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not panel.visible:
		return
	_nav_timer = max(0.0, _nav_timer - delta)
	if _nav_timer > 0.0:
		return
	# Left stick Y — same axis as player movement, safe because GameState.ui_open
	# blocks the player from consuming it.
	var stick_y := Input.get_axis("move_forward", "move_back")
	if abs(stick_y) > 0.5:
		_nav_timer = NAV_REPEAT
		_move_sel(1 if stick_y > 0 else -1)

func _move_sel(dir: int) -> void:
	if _focusable.is_empty():
		return
	_sel = (_sel + dir + _focusable.size()) % _focusable.size()
	_focusable[_sel].grab_focus()
	scroll.ensure_control_visible(_focusable[_sel])

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	# D-pad up / down — take over so we drive _sel ourselves.
	if event.is_action_pressed("ui_up", true):
		_move_sel(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down", true):
		_move_sel(1)
		get_viewport().set_input_as_handled()
		return
	# B  — always close.
	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()
