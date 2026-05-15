extends Node

const MAX_REACH := 12.0

const COLOR_VALID := Color(0.1, 1.0, 0.2, 0.45)
const COLOR_WRONG := Color(1.0, 0.85, 0.0, 0.45)

var _active             := false
var _current_bp:    BlueprintInstance = null
var _current_slot_index := -1
var _placement_valid    := false
var _place_held         := false  # hysteresis gate: arm ≥ 0.9, disarm ≤ 0.1

var plot:   Plot   = null
var player: Player = null
@onready var _ghost:       MeshInstance3D = $Ghost
@onready var _build_label: HBoxContainer  = $BuildUI/BuildLabel

var _mat_valid: StandardMaterial3D
var _mat_wrong: StandardMaterial3D

func _ready() -> void:
	_mat_valid = _make_overlay_mat(COLOR_VALID)
	_mat_wrong = _make_overlay_mat(COLOR_WRONG)
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.hide()
	_build_label.hide()

func _make_overlay_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if _active: _exit_build()
		else:       _enter_build()
		return

	if not _active:
		return


# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not player:
		player = _local_player()
		return
	if not plot:
		plot = get_tree().get_first_node_in_group("plot")
	if not _active:
		return
	# Auto-exit if the player dropped or consumed every item outside of build mode.
	if not GameState.debug_mode and player.inventory.is_empty():
		_exit_build()
		return
	if Input.is_action_just_pressed("place") and not _place_held:
		_place_held = true
		_try_place()
	elif _place_held and Input.get_action_raw_strength("place") <= 0.1:
		_place_held = false
	_update_build_label()

	var result := _nearest_slot_on_ray()
	if result.is_empty():
		_ghost.hide()
		_current_bp         = null
		_current_slot_index = -1
		_placement_valid    = false
		return

	_current_bp         = result[0]
	var slot: BlueprintSlot = result[1]
	_current_slot_index = result[2]

	var item_data    := _get_item_data(slot.required_item_id)
	var has_item     := player.inventory.has_id(slot.required_item_id)
	_placement_valid  = has_item

	_show_ghost(slot, item_data, _mat_valid if has_item else _mat_wrong)

# Position and orient the ghost using the blueprint instance's world transform
# composed with the slot's local transform, so rotated blueprints work correctly.
func _show_ghost(slot: BlueprintSlot, item_data: ItemData, mat: StandardMaterial3D) -> void:
	var box  := BoxMesh.new()
	box.size = item_data.size if item_data else Vector3.ONE
	_ghost.mesh              = box
	_ghost.material_override = mat
	var slot_t := Transform3D(
		Basis.from_euler(slot.rotation_deg * PI / 180.0),
		slot.position
	)
	_ghost.global_transform = _current_bp.global_transform * slot_t
	_ghost.show()

# ── Build mode ────────────────────────────────────────────────────────────────

func _enter_build() -> void:
	if GameState.active_build_mode != GameConstants.BUILD_NONE:
		return
	GameState.active_build_mode = GameConstants.BUILD_BLUEPRINT
	_active = true
	_build_label.show()

func _exit_build() -> void:
	GameState.active_build_mode = GameConstants.BUILD_NONE
	_active             = false
	_current_bp         = null
	_current_slot_index = -1
	_placement_valid    = false
	_ghost.hide()
	_build_label.hide()

func _update_build_label() -> void:
	if plot.blueprint_instances.is_empty():
		UIStyle.set_hint(_build_label, [[
			"Aim at the plot and press ", "@interact", " to place a blueprint  ", "@build_mode", " Exit"
		]])
		return

	var all_done := plot.blueprint_instances.all(func(bp): return bp.is_complete())
	if all_done:
		UIStyle.set_hint(_build_label, [["ALL BUILDS COMPLETE!  ", "@build_mode", " Exit"]])
		return

	var active_bp: BlueprintInstance = null
	for bp: BlueprintInstance in plot.blueprint_instances:
		if not bp.is_complete():
			active_bp = bp
			break

	if _current_bp == null or _current_slot_index < 0:
		if active_bp:
			var p  := active_bp.current_phase
			var d  := active_bp.blueprint_data
			var pn := d.phase_names[p] if p < d.phase_names.size() else "Phase %d" % p
			var pt := 0; var pd := 0
			for i in range(d.slots.size()):
				if int(d.slots[i].phase) == p:
					pt += 1
					if active_bp.filled.get(i, false): pd += 1
			UIStyle.set_hint(_build_label, [[
				"%s  %d/%d — aim at a glowing slot  " % [pn, pd, pt], "@build_mode", " Exit"
			]])
		else:
			UIStyle.set_hint(_build_label, [["@build_mode", " Exit"]])
		return

	var idx        := _current_bp.current_phase
	var data       := _current_bp.blueprint_data
	var phase_name := data.phase_names[idx] if idx < data.phase_names.size() else "Phase %d" % idx

	var phase_total := 0
	var phase_done  := 0
	for i in range(data.slots.size()):
		var s: BlueprintSlot = data.slots[i]
		if int(s.phase) == idx:
			phase_total += 1
			if _current_bp.filled.get(i, false): phase_done += 1

	var slot: BlueprintSlot = data.slots[_current_slot_index]
	var item_res  := ItemRegistry.get_item(slot.required_item_id)
	var item_name := item_res.display_name if item_res else slot.required_item_id
	var has       := player.inventory.has_id(slot.required_item_id)
	var item_hint := "  →  %s%s" % [item_name, "" if has else " (not carrying)"]

	UIStyle.set_hint(_build_label, [[
		"%s  %d/%d%s  " % [phase_name, phase_done, phase_total, item_hint],
		"@place", " Place  ", "@build_mode", " Exit"
	]])

# ── Placement ────────────────────────────────────────────────────────────────

func _try_place() -> void:
	if not _placement_valid or _current_slot_index == -1 or _current_bp == null:
		return
	if _current_bp.filled.get(_current_slot_index, false):
		return

	var slot: BlueprintSlot = _current_bp.blueprint_data.slots[_current_slot_index]
	var carried_item := player.inventory.find_by_id(slot.required_item_id)
	if not carried_item:
		return

	carried_item.play_place_sound()
	_rumble(0.0, 0.7, 0.12)
	_consume_item_by_id(slot.required_item_id)

	var piece := PlacedPlank.build(carried_item.item_data.size, carried_item.item_data.color)
	plot.get_node("PlacedPieces").add_child(piece)

	# Combine the blueprint instance's world transform with the slot's local transform
	# so pieces land correctly even when the blueprint is rotated.
	var slot_t := Transform3D(
		Basis.from_euler(slot.rotation_deg * PI / 180.0),
		slot.position
	)
	piece.set_deferred("global_transform", _current_bp.global_transform * slot_t)

	_current_bp.fill_slot(_current_slot_index)

	if NetworkManager.is_active():
		var bp_idx := plot.blueprint_instances.find(_current_bp)
		if bp_idx >= 0:
			var world_t := _current_bp.global_transform * slot_t
			if NetworkManager.is_server():
				_sync_fill.rpc(bp_idx, _current_slot_index, world_t, slot.required_item_id)
			else:
				_request_fill.rpc_id(1, bp_idx, _current_slot_index, world_t, slot.required_item_id)

	_current_bp         = null
	_current_slot_index = -1
	_placement_valid    = false
	_ghost.hide()  # always hide immediately; next frame will reshow if still valid

	# Auto-exit build mode when the last item has been consumed.
	if not GameState.debug_mode and player.inventory.is_empty():
		_exit_build()

func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _consume_item_by_id(item_id: String) -> void:
	if GameState.debug_mode:
		return
	var item := player.inventory.remove_by_id(item_id)
	if not item:
		return
	if NetworkManager.is_active() and item.net_id != 0:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			world.sync_item_consume(item.net_id)
	item.queue_free()

# ── Slot picking via camera ray ───────────────────────────────────────────────

# Returns [BlueprintInstance, BlueprintSlot, slot_index] for the closest
# unfilled active slot across all blueprint instances on the plot.
func _nearest_slot_on_ray() -> Array:
	var ray_origin := player.camera.global_position
	var ray_dir    := -player.camera.global_transform.basis.z.normalized()

	const SNAP_DIST := 2.0

	var best_dist  := SNAP_DIST
	var best_bp:     BlueprintInstance = null
	var best_slot:   BlueprintSlot     = null
	var best_idx   := -1

	for bp: BlueprintInstance in plot.blueprint_instances:
		for i in range(bp.blueprint_data.slots.size()):
			var slot: BlueprintSlot = bp.blueprint_data.slots[i]
			if int(slot.phase) != bp.current_phase: continue
			if bp.filled.get(i, false):             continue

			# Slot world position accounts for the instance's rotation.
			var world_pos := bp.to_global(slot.position)
			var to_slot   := world_pos - ray_origin
			var proj      := to_slot.dot(ray_dir)
			if proj < 0.1 or proj > MAX_REACH:      continue

			var dist := (world_pos - (ray_origin + ray_dir * proj)).length()
			if dist < best_dist:
				best_dist = dist
				best_bp   = bp
				best_slot = slot
				best_idx  = i

	if best_slot:
		return [best_bp, best_slot, best_idx]
	return []

# ── Multiplayer ───────────────────────────────────────────────────────────────

func _local_player() -> Player:
	for p in get_tree().get_nodes_in_group("player"):
		if not NetworkManager.is_active() or p.is_multiplayer_authority():
			return p
	return null

# Client → server: "I placed this, please apply and relay to everyone else."
@rpc("any_peer", "reliable")
func _request_fill(bp_idx: int, slot_idx: int, world_transform: Transform3D,
		item_id: String) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_fill_local(bp_idx, slot_idx, world_transform, item_id)
	for pid in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_fill.rpc_id(pid, bp_idx, slot_idx, world_transform, item_id)

# Server → clients: authoritative broadcast of a confirmed placement.
@rpc("authority", "reliable")
func _sync_fill(bp_idx: int, slot_idx: int, world_transform: Transform3D,
		item_id: String) -> void:
	_apply_fill_local(bp_idx, slot_idx, world_transform, item_id)

func _apply_fill_local(bp_idx: int, slot_idx: int, world_transform: Transform3D,
		item_id: String) -> void:
	var plot_node := get_tree().get_first_node_in_group("plot") as Plot
	if not plot_node or bp_idx < 0 or bp_idx >= plot_node.blueprint_instances.size():
		return
	plot_node.blueprint_instances[bp_idx].fill_slot(slot_idx)
	var item_data := ItemRegistry.get_item(item_id)
	if not item_data:
		return
	var piece := PlacedPlank.build(item_data.size, item_data.color)
	plot_node.get_node("PlacedPieces").add_child(piece)
	piece.set_deferred("global_transform", world_transform)

# ── Inventory helpers ─────────────────────────────────────────────────────────

func _get_item_data(item_id: String) -> ItemData:
	var item := player.inventory.find_by_id(item_id)
	if item:
		return item.item_data
	return ItemRegistry.get_item(item_id)
