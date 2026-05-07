extends Node

@export var plot_path: NodePath
@export var player_path: NodePath

const MAX_REACH := 12.0

const COLOR_VALID   := Color(0.1, 1.0, 0.2, 0.45)
const COLOR_WRONG   := Color(1.0, 0.85, 0.0, 0.45)

var _plot: Plot = null
var _player: CharacterBody3D = null
var _active := false
var _current_slot_index := -1
var _placement_valid    := false

@onready var _ghost: MeshInstance3D = $Ghost
@onready var _build_label: Label    = $BuildUI/BuildLabel

var _mat_valid: StandardMaterial3D
var _mat_wrong: StandardMaterial3D

func _ready() -> void:
	_plot   = get_node(plot_path)   as Plot
	_player = get_node(player_path) as CharacterBody3D

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

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_try_place()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _active:
		return

	_update_build_label()

	var bp := _plot.blueprint_instance
	if not bp:
		_ghost.hide()
		_current_slot_index = -1
		return

	var result: Array = _nearest_slot_on_ray(bp)
	if result.is_empty():
		_ghost.hide()
		_current_slot_index = -1
		_placement_valid    = false
		return

	var slot: BlueprintSlot = result[0]
	_current_slot_index = result[1]

	var item_data := _get_item_data(slot.required_item_id)
	var has_item  := _carrying_item_id(slot.required_item_id)
	_placement_valid = has_item

	_show_ghost(slot, item_data, _mat_valid if has_item else _mat_wrong)

func _show_ghost(slot: BlueprintSlot, item_data: ItemData,
		mat: StandardMaterial3D) -> void:
	var box  := BoxMesh.new()
	box.size = item_data.size if item_data else Vector3.ONE
	_ghost.mesh              = box
	_ghost.material_override = mat
	_ghost.global_position   = _plot.to_global(slot.position)
	_ghost.rotation_degrees  = slot.rotation_deg
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
	_active = false
	_ghost.hide()
	_build_label.hide()
	_current_slot_index = -1
	_placement_valid    = false

func _update_build_label() -> void:
	var bp := _plot.blueprint_instance
	var e_key  := InputHelper.action_label("interact")
	var b_key  := InputHelper.action_label("build_mode")
	var lmb    := InputHelper.action_label("place")
	if not bp:
		_build_label.text = "Carry a blueprint to the plot, walk up and press %s    %s Exit" % [e_key, b_key]
		return
	if bp.is_complete():
		_build_label.text = "BUILD COMPLETE!    %s Exit" % b_key
		return
	var idx: int            = bp.current_phase
	var data: BlueprintData = bp.blueprint_data
	var phase_name: String  = data.phase_names[idx] if idx < data.phase_names.size() \
		else "Phase %d" % idx

	var item_hint := ""
	if _current_slot_index >= 0:
		var slot: BlueprintSlot = data.slots[_current_slot_index]
		var item_res := ItemRegistry.get_item(slot.required_item_id)
		var item_name: String = item_res.display_name if item_res else slot.required_item_id
		var has: bool = _carrying_item_id(slot.required_item_id)
		item_hint = "  →  %s%s" % [item_name, "" if has else " (not carrying)"]

	_build_label.text = "%s%s    %s Place    %s Exit" % [phase_name, item_hint, lmb, b_key]

# ── Placement ────────────────────────────────────────────────────────────────

func _try_place() -> void:
	if not _placement_valid or _current_slot_index == -1:
		return
	var bp := _plot.blueprint_instance
	if not bp:
		return
	if bp.filled.get(_current_slot_index, false):
		return

	var slot: BlueprintSlot = bp.blueprint_data.slots[_current_slot_index]
	var carried_item := _get_carried_item(slot.required_item_id)
	if not carried_item:
		return

	carried_item.play_place_sound()
	_consume_item_by_id(slot.required_item_id)

	var piece := _create_placed_piece(carried_item)
	_plot.get_node("PlacedPieces").add_child(piece)
	piece.global_position  = _plot.to_global(slot.position)
	piece.rotation_degrees = slot.rotation_deg

	bp.fill_slot(_current_slot_index)
	_current_slot_index = -1
	_placement_valid    = false

func _create_placed_piece(carried: PhysicalItem) -> PlacedPlank:
	var piece   := PlacedPlank.new()
	piece.size  = carried.item_data.size
	piece.color = carried.item_data.color

	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = carried.item_data.size
	col.shape  = shape
	piece.add_child(col)

	var box := BoxMesh.new()
	box.size = carried.item_data.size
	var mi  := MeshInstance3D.new()
	mi.mesh              = box
	mi.material_override = _wood_mat(carried.item_data.color)
	piece.add_child(mi)

	return piece

func _wood_mat(base: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var v   := randf_range(-0.07, 0.07)
	mat.albedo_color = Color(
		clampf(base.r + v,        0.0, 1.0),
		clampf(base.g + v * 0.55, 0.0, 1.0),
		clampf(base.b + v * 0.30, 0.0, 1.0)
	)
	return mat

# ── Slot picking via camera ray ───────────────────────────────────────────────

# Returns [BlueprintSlot, index] of the active slot whose world position is
# closest to the camera ray, within MAX_REACH and a 1.2 m snap radius.
func _nearest_slot_on_ray(bp: BlueprintInstance) -> Array:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var ray_origin := camera.global_position
	var ray_dir    := -camera.global_transform.basis.z.normalized()

	const SNAP_DIST := 1.2

	var best_dist := SNAP_DIST
	var best_slot: BlueprintSlot = null
	var best_idx  := -1

	for i in range(bp.blueprint_data.slots.size()):
		var slot: BlueprintSlot = bp.blueprint_data.slots[i]
		if int(slot.phase) != bp.current_phase: continue
		if bp.filled.get(i, false):             continue

		var world_pos := _plot.to_global(slot.position)
		var to_slot   := world_pos - ray_origin
		var proj      := to_slot.dot(ray_dir)
		if proj < 0.1 or proj > MAX_REACH:      continue

		# perpendicular distance from slot centre to the ray
		var closest := ray_origin + ray_dir * proj
		var dist    := (world_pos - closest).length()
		if dist < best_dist:
			best_dist = dist
			best_slot = slot
			best_idx  = i

	if best_slot:
		return [best_slot, best_idx]
	return []

# ── Inventory helpers ─────────────────────────────────────────────────────────

func _carrying_item_id(item_id: String) -> bool:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return true
	return false

func _get_carried_item(item_id: String) -> PhysicalItem:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi
	return null

func _get_item_data(item_id: String) -> ItemData:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi.item_data
	return ItemRegistry.get_item(item_id)

func _consume_item_by_id(item_id: String) -> void:
	return;
	for i in range(_player.carried_items.size() - 1, -1, -1):
		var item := _player.carried_items[i] as PhysicalItem
		if item.item_data and item.item_data.id == item_id:
			_player.carried_items.remove_at(i)
			item.queue_free()
			return
