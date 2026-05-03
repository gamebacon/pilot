extends Node

@export var plot_path: NodePath
@export var player_path: NodePath

const MAX_REACH := 12.0

const COLOR_VALID   := Color(0.1, 1.0, 0.2, 0.45)
const COLOR_WRONG   := Color(1.0, 0.85, 0.0, 0.45)
const COLOR_INVALID := Color(1.0, 0.1, 0.1, 0.40)

# ── Piece dimensions  (FLOOR=0  WALL=1  ROOF=2) ───────────────────────────────
# All walls are full-cell (1 × 2.2 × 1 m) — corners join with zero gap, no rotation.
const PLACED_SIZE: Array[Vector3] = [
	Vector3(1.0, 0.12, 1.0),  # FLOOR
	Vector3(1.0, 2.20, 1.0),  # WALL
	Vector3(1.0, 0.20, 1.0),  # ROOF
]
# Y of the piece's centre above the plot surface
const PLACED_Y: Array[float] = [
	0.06,   # FLOOR  (half of 0.12)
	1.10,   # WALL   (half of 2.2)
	2.30,   # ROOF   (2.2 walls + half of 0.2)
]

# ── Plank counts per type ──────────────────────────────────────────────────────
const PLANK_COUNT: Array[int] = [5, 8, 5]  # FLOOR / WALL / ROOF

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
	_plot  = get_node(plot_path)  as Plot
	_player = get_node(player_path) as CharacterBody3D

	_mat_valid   = _make_overlay_mat(COLOR_VALID)
	_mat_wrong   = _make_overlay_mat(COLOR_WRONG)
	_mat_invalid = _make_overlay_mat(COLOR_INVALID)

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

	var hit := _raycast_plot_surface()
	if hit == Vector3.INF:
		_ghost.hide()
		return

	var cell: Vector2i = _plot.world_to_cell(hit)
	_current_cell = cell
	_current_slot_index = -1
	_placement_valid    = false

	var bp := _plot.blueprint_instance
	if not bp:
		_show_ghost(cell, 0, _mat_invalid)
		return

	var result: Array = bp.get_active_slot_at(cell)
	if result.is_empty():
		_show_ghost(cell, 0, _mat_invalid)
		return

	var slot: BlueprintSlot = result[0]
	_current_slot_index  = result[1]
	var pt: int          = int(slot.placement_type)
	var has_item: bool   = _carrying_item_id(slot.required_item_id)
	_placement_valid     = has_item

	_show_ghost(cell, pt, _mat_valid if has_item else _mat_wrong)

func _show_ghost(cell: Vector2i, pt: int, mat: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = PLACED_SIZE[pt]
	_ghost.mesh = box
	_ghost.material_override = mat
	_ghost.global_position    = _plot.cell_to_world_center(cell)
	_ghost.global_position.y  = _plot.get_surface_y() + PLACED_Y[pt]
	_ghost.rotation_degrees   = Vector3.ZERO
	_ghost.show()

# ── Build mode ────────────────────────────────────────────────────────────────

func _enter_build() -> void:
	_active = true
	_build_label.show()
	_plot.show_grid()

func _exit_build() -> void:
	_active = false
	_ghost.hide()
	_build_label.hide()
	_plot.hide_grid()

func _update_build_label() -> void:
	var bp := _plot.blueprint_instance
	if not bp:
		_build_label.text = "Carry a blueprint to the plot and press [E]    [B] Cancel"
		return
	if bp.is_complete():
		_build_label.text = "BUILD COMPLETE!    [B] Exit"
		return
	var idx: int         = bp.current_phase
	var data: BlueprintData = bp.blueprint_data
	var phase_name: String  = data.phase_names[idx] if idx < data.phase_names.size() else "Phase %d" % idx
	_build_label.text = "BUILD MODE — %s    [LMB] Place    [B] Cancel" % phase_name

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
	var slot_idx: int       = result[1]
	var pt: int             = int(slot.placement_type)

	var item := _get_item(slot.required_item_id)
	item.play_place_sound()

	var item_color := _get_item_color(slot.required_item_id)
	_consume_item_by_id(slot.required_item_id)

	var piece := _create_placed_piece(pt, item_color)
	_plot.get_node("PlacedPieces").add_child(piece)
	piece.global_position   = _plot.cell_to_world_center(_current_cell)
	piece.global_position.y = _plot.get_surface_y() + PLACED_Y[pt]

	_plot.place(_current_cell, piece)
	bp.fill_slot(slot_idx)

# ── Piece mesh generation ─────────────────────────────────────────────────────

func _create_placed_piece(pt: int, base_color: Color) -> StaticBody3D:
	var body  := StaticBody3D.new()
	var size  := PLACED_SIZE[pt]
	var count := PLANK_COUNT[pt]

	# Single collision shape covering the full cell volume
	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape  = shape
	body.add_child(col)

	match pt:
		0: _add_floor_boards(body, size, base_color, count)  # lengthwise boards
		1: _add_wall_logs(body, size, base_color, count)      # stacked log courses
		2: _add_roof_boards(body, size, base_color, count)    # crosswise boards
		_: _add_single_mesh(body, size, base_color)

	return body

# Floor: planks running along Z, side-by-side in X
func _add_floor_boards(parent: Node3D, size: Vector3, base: Color, n: int) -> void:
	var bw := size.x / n          # board width in X
	for i in range(n):
		var mesh_inst := MeshInstance3D.new()
		var box       := BoxMesh.new()
		box.size = Vector3(bw * 0.88, size.y, size.z)
		mesh_inst.mesh     = box
		mesh_inst.position = Vector3((i - n / 2.0 + 0.5) * bw, 0.0, 0.0)
		mesh_inst.material_override = _wood_mat(base)
		parent.add_child(mesh_inst)

# Wall: horizontal log courses stacked in Y
func _add_wall_logs(parent: Node3D, size: Vector3, base: Color, n: int) -> void:
	var lh := size.y / n          # log course height
	for i in range(n):
		var mesh_inst := MeshInstance3D.new()
		var box       := BoxMesh.new()
		box.size = Vector3(size.x, lh * 0.88, size.z)
		mesh_inst.mesh     = box
		mesh_inst.position = Vector3(0.0, (i - n / 2.0 + 0.5) * lh, 0.0)
		mesh_inst.material_override = _wood_mat(base)
		parent.add_child(mesh_inst)

# Roof: boards running along X, side-by-side in Z
func _add_roof_boards(parent: Node3D, size: Vector3, base: Color, n: int) -> void:
	var bw := size.z / n          # board width in Z
	for i in range(n):
		var mesh_inst := MeshInstance3D.new()
		var box       := BoxMesh.new()
		box.size = Vector3(size.x, size.y, bw * 0.88)
		mesh_inst.mesh     = box
		mesh_inst.position = Vector3(0.0, 0.0, (i - n / 2.0 + 0.5) * bw)
		mesh_inst.material_override = _wood_mat(base)
		parent.add_child(mesh_inst)

func _add_single_mesh(parent: Node3D, size: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box       := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = _wood_mat(color)
	parent.add_child(mesh_inst)

# Slight random tonal variation per plank to suggest wood grain
func _wood_mat(base: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var v   := randf_range(-0.07, 0.07)
	mat.albedo_color = Color(
		clampf(base.r + v,        0.0, 1.0),
		clampf(base.g + v * 0.55, 0.0, 1.0),
		clampf(base.b + v * 0.30, 0.0, 1.0)
	)
	return mat

# ── Helpers ───────────────────────────────────────────────────────────────────

func _raycast_plot_surface() -> Vector3:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var from := camera.global_position
	var dir  := -camera.global_transform.basis.z.normalized()
	var sy   := _plot.get_surface_y()
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t := (sy - from.y) / dir.y
	if t < 0.1 or t > MAX_REACH:
		return Vector3.INF
	return from + dir * t

func _carrying_item_id(item_id: String) -> bool:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return true
	return false

func _get_item_color(item_id: String) -> Color:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi.item_data.color
	return Color(0.65, 0.42, 0.15)

func _get_item(item_id: String) -> PhysicalItem:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi
	return null


func _consume_item_by_id(item_id: String) -> void:
	for i in range(_player.carried_items.size() - 1, -1, -1):
		var item := _player.carried_items[i] as PhysicalItem
		if item.item_data and item.item_data.id == item_id:
			_player.carried_items.remove_at(i)
			item.queue_free()
			return
