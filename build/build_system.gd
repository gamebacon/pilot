extends Node

@export var plot_path: NodePath
@export var player_path: NodePath

const MAX_REACH := 12.0

# Ghost overlay materials
const COLOR_VALID   := Color(0.1, 1.0, 0.2, 0.50)   # right item
const COLOR_WRONG   := Color(1.0, 0.85, 0.0, 0.50)  # slot exists, wrong item
const COLOR_INVALID := Color(1.0, 0.1, 0.1, 0.45)   # no slot here

# Placed piece dimensions by PlacementType int (FLOOR=0, WALL=1, ROOF=2)
const PLACED_SIZE: Array[Vector3] = [
	Vector3(1.0, 0.08, 1.0),  # FLOOR
	Vector3(1.0, 1.0, 0.15),  # WALL
	Vector3(1.0, 0.12, 1.0),  # ROOF
]
# Y centre of placed piece above plot surface, by PlacementType int
const PLACED_Y: Array[float] = [
	0.04,  # FLOOR
	0.50,  # WALL
	1.06,  # ROOF
]

var _plot: Plot = null
var _player: CharacterBody3D = null
var _active := false
var _current_cell := Vector2i(-1, -1)
var _current_slot_index := -1
var _placement_valid := false

@onready var _ghost: MeshInstance3D = $Ghost
@onready var _build_label: Label = $BuildUI/BuildLabel

var _mat_valid: StandardMaterial3D
var _mat_wrong: StandardMaterial3D
var _mat_invalid: StandardMaterial3D

func _ready() -> void:
	_plot = get_node(plot_path) as Plot
	_player = get_node(player_path) as CharacterBody3D

	_mat_valid   = _make_mat(COLOR_VALID)
	_mat_wrong   = _make_mat(COLOR_WRONG)
	_mat_invalid = _make_mat(COLOR_INVALID)

	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.hide()
	_build_label.hide()

func _make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if _active:
			_exit_build()
		else:
			_enter_build()
		return

	if not _active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place()

# ── Per-frame update ─────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _active:
		return

	_update_build_label()

	var hit := _raycast_plot_surface()
	if hit == Vector3.INF:
		_ghost.hide()
		return

	var cell: Vector2i = _plot.world_to_cell(hit)
	_current_cell = cell
	_current_slot_index = -1
	_placement_valid = false

	var bp := _plot.blueprint_instance
	if not bp:
		_ghost.show()
		_ghost.global_position = _plot.cell_to_world_center(cell)
		_ghost.global_position.y = _plot.get_surface_y()
		_set_ghost_size(0)  # floor-sized placeholder
		_ghost.material_override = _mat_invalid
		return

	var result: Array = bp.get_active_slot_at(cell)
	if result.is_empty():
		_ghost.show()
		_ghost.global_position = _plot.cell_to_world_center(cell)
		_ghost.global_position.y = _plot.get_surface_y()
		_set_ghost_size(0)
		_ghost.material_override = _mat_invalid
		return

	var slot: BlueprintSlot = result[0]
	_current_slot_index = result[1]

	var pt: int = int(slot.placement_type)
	_ghost.show()
	_ghost.global_position = _plot.cell_to_world_center(cell)
	_ghost.global_position.y = _plot.get_surface_y() + PLACED_Y[pt]
	_ghost.rotation_degrees.y = slot.rotation_y_deg
	_set_ghost_size(pt)

	var has_item: bool = _carrying_item_id(slot.required_item_id)
	_placement_valid = has_item
	_ghost.material_override = _mat_valid if has_item else _mat_wrong

# ── Build mode ───────────────────────────────────────────────────────────────

func _enter_build() -> void:
	_active = true
	_ghost.show()
	_build_label.show()

func _exit_build() -> void:
	_active = false
	_ghost.hide()
	_build_label.hide()

func _update_build_label() -> void:
	var bp := _plot.blueprint_instance
	if not bp:
		_build_label.text = "No blueprint placed — carry one here and press [E]    [B] Cancel"
		return
	if bp.is_complete():
		_build_label.text = "BUILD COMPLETE!    [B] Exit"
		return
	var phase_idx: int = bp.current_phase
	var data: BlueprintData = bp.blueprint_data
	var name: String = data.phase_names[phase_idx] if phase_idx < data.phase_names.size() else "Phase %d" % phase_idx
	_build_label.text = "BUILD MODE — %s    [LMB] Place    [B] Cancel" % name

func _set_ghost_size(placement_type_int: int) -> void:
	var box := BoxMesh.new()
	box.size = PLACED_SIZE[placement_type_int]
	_ghost.mesh = box

# ── Placement ────────────────────────────────────────────────────────────────

func _try_place() -> void:
	if not _placement_valid or _current_slot_index == -1:
		return

	var bp := _plot.blueprint_instance
	if not bp:
		return

	var result: Array = bp.get_active_slot_at(_current_cell)
	if result.is_empty():
		return

	var slot: BlueprintSlot = result[0]
	var slot_index: int = result[1]

	# Grab item color before consuming
	var item_color: Color = _get_item_color(slot.required_item_id)
	_consume_item_by_id(slot.required_item_id)

	var pt: int = int(slot.placement_type)
	var piece := _create_placed_piece(pt, item_color)
	_plot.get_node("PlacedPieces").add_child(piece)
	piece.global_position = _plot.cell_to_world_center(_current_cell)
	piece.global_position.y = _plot.get_surface_y() + PLACED_Y[pt]
	piece.rotation_degrees.y = slot.rotation_y_deg

	_plot.place(_current_cell, piece)
	bp.fill_slot(slot_index)

func _create_placed_piece(pt: int, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PLACED_SIZE[pt]
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = PLACED_SIZE[pt]
	col.shape = shape
	body.add_child(col)

	return body

# ── Helpers ──────────────────────────────────────────────────────────────────

func _raycast_plot_surface() -> Vector3:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z.normalized()
	var surface_y := _plot.get_surface_y()

	if abs(dir.y) < 0.001:
		return Vector3.INF

	var t := (surface_y - from.y) / dir.y
	if t < 0.1 or t > MAX_REACH:
		return Vector3.INF

	return from + dir * t

func _carrying_item_id(item_id: String) -> bool:
	for item in _player.carried_items:
		if (item as PhysicalItem).item_data and (item as PhysicalItem).item_data.id == item_id:
			return true
	return false

func _get_item_color(item_id: String) -> Color:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi.item_data.color
	return Color(0.65, 0.42, 0.15)  # fallback wood colour

func _consume_item_by_id(item_id: String) -> void:
	for i in range(_player.carried_items.size() - 1, -1, -1):
		var item := _player.carried_items[i] as PhysicalItem
		if item.item_data and item.item_data.id == item_id:
			_player.carried_items.remove_at(i)
			item.queue_free()
			return
