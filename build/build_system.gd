extends Node

@export var plot_path: NodePath
@export var player_path: NodePath

const MAX_REACH := 12.0

const COLOR_VALID   := Color(0.1, 1.0, 0.2, 0.45)
const COLOR_WRONG   := Color(1.0, 0.85, 0.0, 0.45)
const COLOR_INVALID := Color(1.0, 0.1, 0.1, 0.40)

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
		_ghost.hide()
		return

	var result: Array = bp.get_active_slot_at(cell)
	if result.is_empty():
		_ghost.hide()
		return

	var slot: BlueprintSlot = result[0]
	_current_slot_index  = result[1]
	var item_data: ItemData = _get_item_data(slot.required_item_id)
	var has_item: bool   = _carrying_item_id(slot.required_item_id)
	_placement_valid     = has_item

	_show_ghost(cell, item_data, _mat_valid if has_item else _mat_wrong)

func _show_ghost(cell: Vector2i, item_data: ItemData, mat: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	var size := item_data.size if item_data else Vector3.ONE
	box.size = size
	_ghost.mesh = box
	_ghost.material_override = mat
	_ghost.global_position    = _plot.cell_to_world_center(cell)
	_ghost.global_position.y  = _plot.get_surface_y() + 0.01  # Slightly above surface
	_ghost.rotation_degrees   = Vector3.ZERO
	_ghost.show()

# ── Build mode ────────────────────────────────────────────────────────────────

func _enter_build() -> void:
	if GameState.active_build_mode != "":
		return
	GameState.active_build_mode = "blueprint"
	_active = true
	_build_label.show()
	_plot.show_grid()

func _exit_build() -> void:
	GameState.active_build_mode = ""
	_active = false
	_ghost.hide()
	_build_label.hide()
	_plot.hide_grid()

func _update_build_label() -> void:
	var bp := _plot.blueprint_instance
	if not bp:
		_build_label.text = "Carry a blueprint to the plot, walk up and press [E]    [B] Exit"
		return
	if bp.is_complete():
		_build_label.text = "BUILD COMPLETE!    [B] Exit"
		return
	var idx: int            = bp.current_phase
	var data: BlueprintData = bp.blueprint_data
	var phase_name: String  = data.phase_names[idx] if idx < data.phase_names.size() else "Phase %d" % idx

	# Show which item the currently hovered slot needs
	var item_hint := ""
	if _current_slot_index >= 0:
		var slot: BlueprintSlot = data.slots[_current_slot_index]
		var item_res := load("res://items/resources/" + slot.required_item_id + ".tres") as ItemData
		var item_name: String = item_res.display_name if item_res else slot.required_item_id
		var has: bool = _carrying_item_id(slot.required_item_id)
		item_hint = "  →  %s %s" % [item_name, "" if has else "(not carrying)"]

	_build_label.text = "%s%s    [LMB] Place    [B] Exit" % [phase_name, item_hint]

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

	# Get the actual carried item
	var carried_item: PhysicalItem = _get_carried_item(slot.required_item_id)
	if not carried_item:
		return

	carried_item.play_place_sound()
	_consume_item_by_id(slot.required_item_id)

	# Create placed piece using the actual item
	var piece := _create_placed_piece_from_item(carried_item)
	_plot.get_node("PlacedPieces").add_child(piece)
	piece.global_position   = _plot.cell_to_world_center(_current_cell)
	piece.global_position.y = _plot.get_surface_y() + 0.01

	_plot.place(_current_cell, piece)
	bp.fill_slot(slot_idx)

# ── Piece creation from actual items ──────────────────────────────────────────

func _create_placed_piece_from_item(carried: PhysicalItem) -> PlacedPlank:
	var piece := PlacedPlank.new()
	piece.size  = carried.item_data.size
	piece.color = carried.item_data.color

	# Build collision
	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = carried.item_data.size
	col.shape  = shape
	piece.add_child(col)

	# Build mesh
	var box := BoxMesh.new()
	box.size = carried.item_data.size
	var mi := MeshInstance3D.new()
	mi.mesh              = box
	mi.material_override = _wood_mat(carried.item_data.color)
	piece.add_child(mi)

	return piece

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
	return null

func _get_item_color(item_id: String) -> Color:
	for item in _player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.id == item_id:
			return pi.item_data.color
	return Color(0.65, 0.42, 0.15)


func _consume_item_by_id(item_id: String) -> void:
	for i in range(_player.carried_items.size() - 1, -1, -1):
		var item := _player.carried_items[i] as PhysicalItem
		if item.item_data and item.item_data.id == item_id:
			_player.carried_items.remove_at(i)
			item.queue_free()
			return
