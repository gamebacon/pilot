extends Node

@export var plot_path: NodePath
@export var player_path: NodePath

const COLOR_VALID := Color(0.1, 1.0, 0.2, 0.45)
const COLOR_INVALID := Color(1.0, 0.1, 0.1, 0.45)
const MAX_REACH := 12.0

var _plot: Plot = null
var _player: CharacterBody3D = null
var _active := false
var _current_cell := Vector2i(-1, -1)
var _placement_valid := false

@onready var _ghost: MeshInstance3D = $Ghost
@onready var _build_label: Label = $BuildUI/BuildLabel

var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D

func _ready() -> void:
	_plot = get_node(plot_path) as Plot
	_player = get_node(player_path) as CharacterBody3D

	_mat_valid = StandardMaterial3D.new()
	_mat_valid.albedo_color = COLOR_VALID
	_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mat_invalid = StandardMaterial3D.new()
	_mat_invalid.albedo_color = COLOR_INVALID
	_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.hide()
	_build_label.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if _active:
			_exit_build()
		elif not (_player.carried_items as Array).is_empty():
			_enter_build()
		return

	if not _active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place()

func _process(_delta: float) -> void:
	if not _active:
		return

	var hit := _raycast_plot_surface()
	if hit == Vector3.INF:
		_ghost.hide()
		return

	var cell := _plot.world_to_cell(hit)
	_current_cell = cell
	_placement_valid = _plot.is_in_bounds(cell) and not _plot.is_occupied(cell)

	_ghost.show()
	_ghost.global_position = _plot.cell_to_world_center(cell)
	_ghost.global_position.y = _plot.get_surface_y()
	_ghost.material_override = _mat_valid if _placement_valid else _mat_invalid

func _enter_build() -> void:
	_active = true
	_refresh_ghost_mesh()
	_ghost.show()
	_build_label.show()

func _exit_build() -> void:
	_active = false
	_ghost.hide()
	_build_label.hide()

func _refresh_ghost_mesh() -> void:
	var items: Array = _player.carried_items
	if items.is_empty():
		return
	var item = items.back()
	if item and item.item_data:
		var box := BoxMesh.new()
		box.size = item.item_data.size
		_ghost.mesh = box

# Math-based ray vs. horizontal plane — no physics needed
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

func _try_place() -> void:
	if not _placement_valid:
		return

	var items: Array = _player.carried_items
	if items.is_empty():
		_exit_build()
		return

	var item: PhysicalItem = items.pop_back()
	var data: ItemData = item.item_data
	item.queue_free()

	# Spawn placed piece
	var piece := _create_placed_piece(data)
	_plot.get_node("PlacedPieces").add_child(piece)
	piece.global_position = _plot.cell_to_world_center(_current_cell)
	piece.global_position.y = _plot.get_surface_y() + data.size.y * 0.5

	_plot.place(_current_cell, piece)

	if items.is_empty():
		_exit_build()
	else:
		_refresh_ghost_mesh()

func _create_placed_piece(data: ItemData) -> StaticBody3D:
	var body := StaticBody3D.new()

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = data.size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.color
	if data.color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = data.size
	col.shape = shape
	body.add_child(col)

	return body
