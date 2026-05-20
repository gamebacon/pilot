extends CanvasLayer

@onready var hint_label:         VBoxContainer = $HintLabel
@onready var crosshair:          Label         = $Crosshair
@onready var context_hints:      VBoxContainer = $ContextHints
@onready var notification_label: Label         = $NotificationLabel
@onready var debug_badge:        Label         = $DebugBadge
@onready var shift_label:        Label         = $ShiftLabel

var _player: Node = null
var _notify_tween: Tween = null
var _core_hp_label: Label = null
var _core: Node = null
var _context_bg: Panel = null
var _hint_bg:    Panel = null

# Dirty-check cache so we don't rebuild prompt nodes every frame
var _last_hint := ""
var _last_context_key := ""

# ── FPS / debug overlay ────────────────────────────────────────────────────────
var _fps_label:     Label          = null
var _debug_panel:   PanelContainer = null
var _debug_label:   Label          = null
var _fps_smooth:    float          = 60.0
var _frame_ms:      float          = 16.7

func _ready() -> void:
	hint_label.hide()
	context_hints.hide()
	debug_badge.hide()
	for lbl: Label in [crosshair, notification_label, debug_badge, shift_label]:
		lbl.add_theme_font_override("font", UIStyle.FONT)
	GameState.debug_mode_changed.connect(_on_debug_mode_changed)
	InputHelper.input_changed.connect(func(_joy: bool) -> void: _last_context_key = "")
	if NetworkManager.is_server():
		_add_server_ip_label()
	_add_fps_counter()
	_add_debug_panel()
	_add_core_hp_label()
	_build_context_bg()


func _process(delta: float) -> void:
	_tick_fps(delta)
	_sync_hint_bg()
	_sync_context_bg()
	if _debug_panel and _debug_panel.visible:
		_refresh_debug_panel()
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	_try_connect_core()
	_update_time_label()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint_label.hide()
		crosshair.hide()
		context_hints.hide()
		return

	crosshair.show()

	# Untyped so GDScript doesn't validate on assignment — is_instance_valid handles it below.
	var target = _player.interact_target
	if not is_instance_valid(target):
		_player.interact_target = null
		hint_label.hide()
		_last_hint = ""
	elif target.has_method("get_interact_hint"):
		var hint: String = target.get_interact_hint(_player)
		if hint.is_empty():
			hint_label.hide()
			_last_hint = ""
		else:
			if hint != _last_hint:
				_last_hint = hint
				var hint_rows: Array[Control] = [UIStyle.make_hint(hint)]
				_rebuild_children(hint_label, hint_rows, true)
			hint_label.show()
	else:
		hint_label.hide()
		_last_hint = ""

	_update_context_hints()

# ── Debug badge + panel ────────────────────────────────────────────────────────

func _on_debug_mode_changed(enabled: bool) -> void:
	debug_badge.visible = enabled
	if _debug_panel:
		_debug_panel.visible = enabled

# ── Context hints ──────────────────────────────────────────────────────────────

func _update_context_hints() -> void:
	# ── Build-place mode hints ─────────────────────────────────────────────────
	if GameState.is_building:
		var key := "build"
		if key != _last_context_key:
			_last_context_key = key
			var pairs := [
				["attack",    "Place"],
				["rotate_y",  "Rotate (Y)"],
				["exit_build","Cancel"],
			]
			var rows: Array[Control] = []
			for p in pairs:
				var row: Control = UIStyle.make_prompt(p[0], p[1])
				row.size_flags_horizontal = Control.SIZE_SHRINK_END
				rows.append(row)
			_rebuild_children(context_hints, rows, false)
		context_hints.show()
		return

	# ── Normal gameplay hints ─────────────────────────────────────────────────
	var inv: Inventory = _player.inventory
	var has_placeable: bool = false
	var has_multi: bool     = false
	var has_item_in_hand: bool = false
	if not inv.is_empty():
		for item in inv.items:
			if item.item_data and item.item_data.is_placeable:
				has_placeable = true
				break
		has_multi = inv.has_multiple_types()
		var hand_slot := inv.get_hotbar_slot(inv.active_hotbar_row, inv.active_slot)
		has_item_in_hand = not hand_slot.is_empty()

	var has_joy: bool = InputHelper.is_joy()
	var key := "%s|%d|%d|%d|%d" % [InputHelper.action_label("drop"), int(has_placeable), int(has_multi), int(has_joy), int(has_item_in_hand)]
	if key != _last_context_key:
		_last_context_key = key
		var rows: Array[Control] = []
		if has_placeable:
			var brow: Control = UIStyle.make_prompt("build_mode", "Build")
			brow.size_flags_horizontal = Control.SIZE_SHRINK_END
			rows.append(brow)
		if has_item_in_hand:
			var drow: Control = UIStyle.make_prompt("drop", "Drop")
			drow.size_flags_horizontal = Control.SIZE_SHRINK_END
			rows.append(drow)
		if has_multi:
			var crow: Control = UIStyle.make_badge_pair("L1", "R1", "Cycle") if has_joy \
				else UIStyle.make_prompt("inventory_next", "Cycle")
			crow.size_flags_horizontal = Control.SIZE_SHRINK_END
			rows.append(crow)
		var irow: Control = UIStyle.make_prompt("open_inventory", "Inventory")
		irow.size_flags_horizontal = Control.SIZE_SHRINK_END
		rows.append(irow)
		_rebuild_children(context_hints, rows, false)

	context_hints.show()

func _show_notification(text: String) -> void:
	notification_label.text = text
	if _notify_tween:
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_property(notification_label, "modulate:a", 1.0, 0.25)
	_notify_tween.tween_interval(2.5)
	_notify_tween.tween_property(notification_label, "modulate:a", 0.0, 0.6)

# ── Day/Night/Wave label ───────────────────────────────────────────────────────

func _update_time_label() -> void:
	var dnc := get_tree().get_first_node_in_group("day_night")
	if not dnc:
		return
	var is_night: bool = dnc.time_of_day > 0.75 or dnc.time_of_day < 0.25
	var ws  := get_tree().get_first_node_in_group("wave_spawner")
	var wave: int = ws._wave_num if ws else 0
	if is_night:
		shift_label.text = "NIGHT — WAVE %d" % wave
		shift_label.add_theme_color_override("font_color", UIStyle.STATUS_INFO)
	else:
		var next := wave + 1
		shift_label.text = "DAY — WAVE %d INCOMING" % next if wave > 0 else "DAY — SURVIVE THE NIGHT"
		shift_label.add_theme_color_override("font_color", UIStyle.ON_BACKGROUND)

# ── Server IP display ──────────────────────────────────────────────────────────

func _add_server_ip_label() -> void:
	var lobby_id := NetworkManager.current_lobby()

	# Lobby ID label
	var lbl := UIStyle.make_label("Lobby: %d" % lobby_id, UIStyle.SIZE_BODY, UIStyle.ON_BACKGROUND)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left   = -420
	lbl.offset_right  = -10
	lbl.offset_top    = 10
	lbl.offset_bottom = 34
	add_child(lbl)

	# Copy ID button — pastes lobby ID to clipboard so you can share it in Discord etc.
	var copy_btn := Button.new()
	copy_btn.text = "Copy ID"
	copy_btn.add_theme_font_override("font", UIStyle.FONT)
	copy_btn.anchor_left   = 1.0
	copy_btn.anchor_right  = 1.0
	copy_btn.anchor_top    = 0.0
	copy_btn.anchor_bottom = 0.0
	copy_btn.offset_left   = -210
	copy_btn.offset_right  = -10
	copy_btn.offset_top    = 38
	copy_btn.offset_bottom = 62
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(str(lobby_id))
		copy_btn.text = "Copied!"
		await get_tree().create_timer(1.5).timeout
		copy_btn.text = "Copy ID"
	)
	add_child(copy_btn)

	# Invite Friends button — opens the Steam overlay friend picker directly
	var invite_btn := Button.new()
	invite_btn.text = "Invite Friends"
	invite_btn.add_theme_font_override("font", UIStyle.FONT)
	invite_btn.anchor_left   = 1.0
	invite_btn.anchor_right  = 1.0
	invite_btn.anchor_top    = 0.0
	invite_btn.anchor_bottom = 0.0
	invite_btn.offset_left   = -420
	invite_btn.offset_right  = -214
	invite_btn.offset_top    = 38
	invite_btn.offset_bottom = 62
	invite_btn.pressed.connect(func():
		Steam.activateGameOverlayInviteDialog(lobby_id)
	)
	add_child(invite_btn)

# ── FPS counter ────────────────────────────────────────────────────────────────

func _add_fps_counter() -> void:
	_fps_label = UIStyle.make_label("-- fps", UIStyle.SIZE_SM, UIStyle.ON_BACKGROUND)
	_fps_label.anchor_left   = 0.0
	_fps_label.anchor_right  = 0.0
	_fps_label.anchor_top    = 0.0
	_fps_label.anchor_bottom = 0.0
	_fps_label.offset_left   = 10
	_fps_label.offset_right  = 120
	_fps_label.offset_top    = 10
	_fps_label.offset_bottom = 26
	add_child(_fps_label)

func _tick_fps(delta: float) -> void:
	# Exponential moving average — stable without being laggy
	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.12)
	_frame_ms   = lerpf(_frame_ms,   delta * 1000.0,            0.12)
	if _fps_label:
		var col := _fps_color(_fps_smooth)
		_fps_label.add_theme_color_override("font_color", col)
		_fps_label.text = "%d fps" % roundi(_fps_smooth)

func _fps_color(fps: float) -> Color:
	if fps >= 55.0: return UIStyle.ON_BACKGROUND
	if fps >= 30.0: return UIStyle.STATUS_CAUTION
	return          UIStyle.STATUS_WARN

# ── Debug panel ────────────────────────────────────────────────────────────────

func _add_debug_panel() -> void:
	# Outer panel
	_debug_panel = PanelContainer.new()
	_debug_panel.add_theme_stylebox_override("panel", UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 6, 10))
	_debug_panel.anchor_left   = 0.0
	_debug_panel.anchor_right  = 0.0
	_debug_panel.anchor_top    = 0.0
	_debug_panel.anchor_bottom = 0.0
	_debug_panel.offset_left   = 10
	_debug_panel.offset_right  = 260
	_debug_panel.offset_top    = 30    # sits just below the fps counter
	_debug_panel.offset_bottom = 200
	_debug_panel.visible       = false

	_debug_label = UIStyle.make_label("", UIStyle.SIZE_SM)
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	_debug_panel.add_child(_debug_label)
	add_child(_debug_panel)

func _refresh_debug_panel() -> void:
	var lines := PackedStringArray()

	# Header
	lines.append("── DEBUG  [F3 to close] ──")

	# FPS block
	lines.append("")
	lines.append("FPS     %d   (%.1f ms)" % [roundi(_fps_smooth), _frame_ms])

	# Player block
	if _player:
		var pos: Vector3 = _player.global_position
		lines.append("")
		lines.append("X  %8.2f" % pos.x)
		lines.append("Y  %8.2f" % pos.y)
		lines.append("Z  %8.2f" % pos.z)
		if _player.has_method("get_real_velocity"):
			var speed: float = (_player.get_real_velocity() as Vector3).length()
			lines.append("Speed  %.1f m/s" % speed)

	# Performance monitors
	lines.append("")
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	lines.append("Nodes   %d" % nodes)
	lines.append("Draws   %d" % draws)
	lines.append("VRAM    %.1f MB" % mem_mb)

	# World seed + time of day
	var wgen := get_tree().get_first_node_in_group("world_generator")
	if wgen and wgen.get("_rng"):
		lines.append("")
		lines.append("Seed  %d" % (wgen._rng.seed))
	var dnc := get_tree().get_first_node_in_group("day_night")
	if dnc and dnc.has_method("get_time_string"):
		var t_str: String = dnc.get_time_string()
		var tod: float    = dnc.time_of_day
		var phase := "Night"
		if   tod > 0.22 and tod < 0.28: phase = "Sunrise"
		elif tod >= 0.28 and tod < 0.50: phase = "Morning"
		elif tod >= 0.50 and tod < 0.55: phase = "Noon"
		elif tod >= 0.55 and tod < 0.72: phase = "Afternoon"
		elif tod >= 0.72 and tod < 0.78: phase = "Sunset"
		elif tod >= 0.78 or  tod < 0.22: phase = "Night"
		lines.append("Time  %s  %s" % [t_str, phase])

	_debug_label.text = "\n".join(lines)

	# Auto-size panel height to content
	_debug_panel.offset_bottom = _debug_panel.offset_top + _debug_label.get_line_count() * 15 + 28

# ── Core HP ────────────────────────────────────────────────────────────────────

func _add_core_hp_label() -> void:
	_core_hp_label = UIStyle.make_label("", UIStyle.SIZE_BODY, UIStyle.ON_BACKGROUND)
	_core_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_core_hp_label.anchor_left   = 0.5
	_core_hp_label.anchor_right  = 0.5
	_core_hp_label.anchor_top    = 0.0
	_core_hp_label.anchor_bottom = 0.0
	_core_hp_label.offset_left   = -100
	_core_hp_label.offset_right  = 100
	_core_hp_label.offset_top    = 10
	_core_hp_label.offset_bottom = 30
	_core_hp_label.text          = "CORE: 100"
	add_child(_core_hp_label)

func _try_connect_core() -> void:
	if _core:
		return
	_core = get_tree().get_first_node_in_group("core")
	if _core:
		_core.hp_changed.connect(_on_core_hp_changed)

func _on_core_hp_changed(new_hp: int) -> void:
	if not _core_hp_label:
		return
	_core_hp_label.text = "CORE: %d" % new_hp
	var t := float(new_hp) / 100.0
	_core_hp_label.add_theme_color_override("font_color",
		Color(1.0, t, t * 0.4, 0.9) if t < 0.5 else UIStyle.STATUS_OK)
	if new_hp == 0:
		_show_notification("CORE DESTROYED!")

# ── Context hint background ────────────────────────────────────────────────────

func _build_context_bg() -> void:
	# ── Crosshair / interact hint backdrop ────────────────────────────────────
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = UIStyle.SCRIM
	hint_style.set_corner_radius_all(7)
	_hint_bg = Panel.new()
	_hint_bg.add_theme_stylebox_override("panel", hint_style)
	_hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_bg.hide()
	add_child(_hint_bg)
	move_child(_hint_bg, hint_label.get_index())

## Backdrop for the crosshair interact hint — centered on actual content.
## hint_label rows use SIZE_SHRINK_CENTER so content is narrower than the node.
func _sync_hint_bg() -> void:
	if not _hint_bg:
		return
	if not hint_label.visible:
		_hint_bg.hide()
		return
	var min_sz := hint_label.get_combined_minimum_size()
	if min_sz.y <= 0:
		_hint_bg.hide()
		return
	const PAD_X := 10.0
	const PAD_Y := 4.0
	var r := hint_label.get_rect()
	_hint_bg.size = min_sz + Vector2(PAD_X * 2.0, PAD_Y * 2.0)
	_hint_bg.position = Vector2(
		r.position.x + (r.size.x - _hint_bg.size.x) * 0.5,
		r.position.y - PAD_Y
	)
	_hint_bg.show()

## Runs every frame — sizes the backdrop to wrap only the visible hint rows.
## context_hints uses alignment=END so children sit at the bottom of the node rect;
## get_combined_minimum_size() gives the actual content height.
func _sync_context_bg() -> void:
	if not _context_bg:
		return
	if not context_hints.visible:
		_context_bg.hide()
		return
	var min_sz := context_hints.get_combined_minimum_size()
	if min_sz.y <= 0:
		_context_bg.hide()
		return
	const PAD := 10.0
	var r := context_hints.get_rect()
	_context_bg.size     = Vector2(r.size.x + PAD * 2.0, min_sz.y + PAD * 2.0)
	_context_bg.position = Vector2(r.position.x - PAD,   r.end.y - min_sz.y - PAD)
	_context_bg.show()

# ── Utility ────────────────────────────────────────────────────────────────────

func _rebuild_children(container: Control, rows: Array[Control], center: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	for row in rows:
		if center:
			row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		container.add_child(row)
