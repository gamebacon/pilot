extends CanvasLayer

@onready var hint_label:         VBoxContainer = $HintLabel
@onready var crosshair:          Label         = $Crosshair
@onready var context_hints:      VBoxContainer = $ContextHints
@onready var notification_label: Label         = $NotificationLabel
@onready var blueprint_list:     Label         = $BlueprintList
@onready var debug_badge:        Label         = $DebugBadge
@onready var shift_label:        Label         = $ShiftLabel
@onready var objective_label:    Label         = $ObjectiveLabel

var _player: Node = null
var _plot:   Node = null
var _day_manager: DayManager = null
var _connected_instances: Array = []
var _notify_tween: Tween = null

# Dirty-check cache so we don't rebuild prompt nodes every frame
var _last_hint := ""
var _last_context_key := ""

func _ready() -> void:
	hint_label.hide()
	context_hints.hide()
	blueprint_list.hide()
	debug_badge.hide()
	for lbl: Label in [crosshair, notification_label, blueprint_list, debug_badge, shift_label, objective_label]:
		lbl.add_theme_font_override("font", UIStyle.FONT)
	GameState.debug_mode_changed.connect(_on_debug_mode_changed)
	GameState.shift_ended.connect(_on_shift_ended)
	_update_shift_label(0.0)

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	_try_connect_plot()
	_try_connect_day_manager()
	_update_objective()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint_label.hide()
		crosshair.hide()
		context_hints.hide()
		blueprint_list.hide()
		return

	var target: Node = _player.interact_target
	if target and target.has_method("get_interact_hint"):
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
			crosshair.show()
	else:
		hint_label.hide()
		_last_hint = ""

	_update_context_hints()
	_update_blueprint_checklist()

# ── Debug badge ────────────────────────────────────────────────────────────────

func _on_debug_mode_changed(enabled: bool) -> void:
	debug_badge.visible = enabled

# ── Context hints ──────────────────────────────────────────────────────────────

func _update_context_hints() -> void:
	if GameState.active_build_mode != GameConstants.BUILD_NONE:
		context_hints.hide()
		_last_context_key = ""
		return
	if _player.inventory.is_empty():
		context_hints.hide()
		_last_context_key = ""
		return

	var has_multi: bool = _player.inventory.has_multiple_types()
	var key := "%s|%s|%s|%d" % [
		InputHelper.action_label("build_mode"),
		InputHelper.action_label("plank_mode"),
		InputHelper.action_label("drop"),
		int(has_multi),
	]
	if key != _last_context_key:
		_last_context_key = key
		var actions := PackedStringArray(["build_mode", "plank_mode", "drop"])
		var labels  := PackedStringArray(["Blueprint",  "Freeplace",  "Drop"])
		if has_multi:
			actions.append("inventory_next")
			labels.append("Cycle")
		var rows: Array[Control] = []
		for i in actions.size():
			var row: Control = UIStyle.make_prompt(actions[i], labels[i])
			row.size_flags_horizontal = Control.SIZE_SHRINK_END
			rows.append(row)
		_rebuild_children(context_hints, rows, false)

	context_hints.show()

# ── Blueprint shopping checklist ───────────────────────────────────────────────

func _update_blueprint_checklist() -> void:
	if GameState.active_build_mode != GameConstants.BUILD_NONE:
		blueprint_list.hide()
		return

	var bp_item: PhysicalItem = null
	for item in _player.inventory.items:
		if item.item_data and item.item_data.is_blueprint and item.item_data.blueprint_data:
			bp_item = item
			break

	if not bp_item:
		blueprint_list.hide()
		return

	var data: BlueprintData = bp_item.item_data.blueprint_data
	var needed: Dictionary = {}
	for slot in data.slots:
		needed[slot.required_item_id] = needed.get(slot.required_item_id, 0) + 1

	var lines := PackedStringArray()
	lines.append(data.display_name + ":")
	for id in needed:
		var item_data: ItemData = ItemRegistry.get_item(id)
		var iname: String = item_data.display_name if item_data else id
		var have := 0
		for it in _player.inventory.items:
			if it.item_data and it.item_data.id == id:
				have += 1
		var total: int = needed[id]
		var marker := "✓" if have >= total else "%d/%d" % [have, total]
		lines.append("[%s] %s ×%d" % [marker, iname, total])

	blueprint_list.text = "\n".join(lines)
	blueprint_list.show()

# ── Phase / build completion notifications ─────────────────────────────────────

func _try_connect_plot() -> void:
	if _plot:
		return
	_plot = get_tree().get_first_node_in_group("plot")
	if _plot:
		_plot.blueprint_added.connect(_on_blueprint_added)

func _try_connect_day_manager() -> void:
	if _day_manager:
		return
	_day_manager = get_tree().get_first_node_in_group("day_manager") as DayManager
	if _day_manager:
		_day_manager.timer_updated.connect(_update_shift_label)
		_update_shift_label(0.0)

func _on_blueprint_added(instance: BlueprintInstance) -> void:
	if instance in _connected_instances:
		return
	_connected_instances.append(instance)
	instance.phase_completed.connect(_on_phase_completed.bind(instance))
	instance.build_completed.connect(_on_build_completed.bind(instance))

func _on_phase_completed(phase_idx: int, instance: BlueprintInstance) -> void:
	var data := instance.blueprint_data
	var done_name := data.phase_names[phase_idx] if phase_idx < data.phase_names.size() else "Phase %d" % (phase_idx + 1)
	var next_idx  := phase_idx + 1
	var next_name := data.phase_names[next_idx] if next_idx < data.phase_names.size() else ""
	var text := "%s\n%s complete!" % [data.display_name, done_name]
	if not next_name.is_empty():
		text += "  →  %s" % next_name
	_show_notification(text)

func _on_build_completed(instance: BlueprintInstance) -> void:
	_show_notification("%s\nBUILD COMPLETE!" % instance.blueprint_data.display_name)

func _show_notification(text: String) -> void:
	notification_label.text = text
	if _notify_tween:
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_property(notification_label, "modulate:a", 1.0, 0.25)
	_notify_tween.tween_interval(2.5)
	_notify_tween.tween_property(notification_label, "modulate:a", 0.0, 0.6)

# ── Shift timer ────────────────────────────────────────────────────────────────

func _update_shift_label(seconds: float) -> void:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	if GameState.shift_active:
		shift_label.text = "DAY %d  |  %02d:%02d" % [GameState.day, mins, secs]
		var urgency := seconds / 480.0
		shift_label.add_theme_color_override("font_color",
			Color(1.0, urgency, urgency * 0.6, 0.9) if urgency < 0.3 else UIStyle.COL_TEXT)
	else:
		shift_label.text = "DAY %d" % GameState.day
		shift_label.add_theme_color_override("font_color", UIStyle.COL_TEXT)

func _on_shift_ended(pay: int) -> void:
	_update_shift_label(0.0)
	_show_notification("SHIFT OVER\n+%d SEK" % pay)

# ── Objective ──────────────────────────────────────────────────────────────────

func _update_objective() -> void:
	var bp_name: String = _day_manager.get_target_blueprint_name() if _day_manager else "Blueprint"
	var bp_id:   String = _day_manager.get_target_blueprint_id()   if _day_manager else ""

	var text := ""
	if GameState.shift_active:
		text = "▶  Build the %s before time runs out" % bp_name
	elif GameState.shift_done:
		text = "▶  Go home and sleep"
	elif _player and _player.inventory.has_id(bp_id):
		text = "▶  Go to the factory and clock in"
	else:
		text = "▶  Buy the %s blueprint from the store" % bp_name
	objective_label.text = text

# ── Utility ────────────────────────────────────────────────────────────────────

func _rebuild_children(container: Control, rows: Array[Control], center: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	for row in rows:
		if center:
			row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		container.add_child(row)
