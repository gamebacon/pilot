extends CanvasLayer

@onready var hint_label:        Label = $HintLabel
@onready var crosshair:         Label = $Crosshair
@onready var context_hints:     Label = $ContextHints
@onready var notification_label:Label = $NotificationLabel
@onready var blueprint_list:    Label = $BlueprintList
@onready var debug_badge:       Label = $DebugBadge

var _player: Node = null
var _plot:   Node = null
var _connected_instances: Array = []
var _notify_tween: Tween = null

func _ready() -> void:
	hint_label.hide()
	context_hints.hide()
	blueprint_list.hide()
	debug_badge.hide()
	GameState.debug_mode_changed.connect(_on_debug_mode_changed)

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	_try_connect_plot()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint_label.hide()
		crosshair.hide()
		context_hints.hide()
		blueprint_list.hide()
		return

	# Interact hint
	var target: Node = _player.interact_target
	if target and target.has_method("get_interact_hint"):
		var hint: String = target.get_interact_hint(_player)
		if hint.is_empty():
			hint_label.hide()
		else:
			hint_label.text = hint
			hint_label.show()
			crosshair.show()
	else:
		hint_label.hide()

	_update_context_hints()
	_update_blueprint_checklist()

# ── Debug badge ────────────────────────────────────────────────────────────────

func _on_debug_mode_changed(enabled: bool) -> void:
	debug_badge.visible = enabled

# ── Context hints ──────────────────────────────────────────────────────────────

func _update_context_hints() -> void:
	if GameState.active_build_mode != GameConstants.BUILD_NONE:
		context_hints.hide()
		return
	if _player.inventory.is_empty():
		context_hints.hide()
		return

	var b := InputHelper.action_label("build_mode")
	var v := InputHelper.action_label("plank_mode")
	var y := InputHelper.action_label("drop")
	var parts := PackedStringArray([
		"%s Blueprint" % b,
		"%s Freeplace" % v,
		"%s Drop" % y,
	])
	if _player.inventory.has_multiple_types():
		var t := InputHelper.action_label("inventory_next")
		parts.append("%s Cycle" % t)

	context_hints.text = "\n".join(parts)
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
