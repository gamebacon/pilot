extends Node

const SNAP_DIST := 0.3
const ROT_STEP  := 90.0
const MAX_REACH := 15.0

var _active      := false
var _snapping    := false
var _place_held  := false  # hysteresis gate: arm ≥ 0.9, disarm ≤ 0.1
var _planks_root: Node3D

var _held_item: PhysicalItem = null
var _held_data: ItemData     = null
var _held_size: Vector3      = Vector3.ONE

var player: Player = null
@onready var _ghost: MeshInstance3D  = $Ghost
@onready var _label: VBoxContainer   = $UI/Label

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_planks_root      = Node3D.new()
	_planks_root.name = "PlacedPlanks"
	get_parent().call_deferred("add_child", _planks_root)

	_mat_snap    = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))
	_mat_blocked = _ghost_mat(Color(0.90, 0.20, 0.20, 0.55))
	_mat_free    = _ghost_mat(Color(1.0, 1.0, 1.0, 0.50))

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _mat_free
	_ghost.hide()
	_label.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("plank_mode"):
		if _active: _exit()
		else:       _enter()
		return

	if not _active:
		return

	if event.is_action_pressed("rotate_y") and not event.is_echo():
		var sign := -1.0 if (event is InputEventKey and event.shift_pressed) else 1.0
		_ghost.global_rotate(Vector3.UP, deg_to_rad(ROT_STEP) * sign)
	elif event.is_action_pressed("rotate_x") and not event.is_echo():
		_ghost.global_rotate(Vector3.RIGHT, deg_to_rad(ROT_STEP))
	elif event.is_action_pressed("rotate_z") and not event.is_echo():
		_ghost.global_rotate(Vector3.FORWARD, deg_to_rad(ROT_STEP))
	elif event.is_action_pressed("reset_rotation") and not event.is_echo():
		_ghost.rotation_degrees = Vector3.ZERO
	elif event.is_action_pressed("remove_piece") and not event.is_echo():
		_remove_piece()

	if event.is_action_pressed("exit_build"):
		_exit()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
		return
	if not _active:
		return
	# Keep held item in sync with whatever the player cycles to.
	var active := player.inventory.active()
	if active != null and active != _held_item:
		_hold(active)
		_refresh_ghost_for_held()
	if Input.is_action_just_pressed("place") and not _place_held:
		_place_held = true
		_place()
	elif _place_held and Input.get_action_raw_strength("place") <= 0.1:
		_place_held = false
	_update_ghost()
	_update_hint()

func _update_ghost() -> void:
	var cam  := player.camera
	var from := cam.global_position
	var dir  := -cam.global_transform.basis.z
	var to   := from + dir * MAX_REACH

	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_ghost.hide()
		return

	_ghost.show()

	var basis := _ghost.global_transform.basis
	var hh    := _held_size * 0.5
	var half_extent: float = (
		abs(basis.x.dot(hit.normal)) * hh.x +
		abs(basis.y.dot(hit.normal)) * hh.y +
		abs(basis.z.dot(hit.normal)) * hh.z
	)
	_ghost.global_position = hit.position + hit.normal * half_extent

	var offset := _find_snap_offset()
	_snapping   = offset != Vector3.ZERO
	if _snapping:
		_ghost.global_position += offset

	if _is_blocked():
		_ghost.material_override = _mat_blocked
	elif _snapping:
		_ghost.material_override = _mat_snap
	else:
		_ghost.material_override = _mat_free

# ── Overlap check ─────────────────────────────────────────────────────────────

func _is_blocked() -> bool:
	var params      := PhysicsShapeQueryParameters3D.new()
	var shape       := BoxShape3D.new()
	shape.size       = _held_size
	params.shape     = shape
	params.transform = _ghost.global_transform
	params.margin    = -0.02
	params.exclude   = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(params, 1).size() > 0

# ── Snap logic ───────────────────────────────────────────────────────────────

func _find_snap_offset() -> Vector3:
	var ghost_sockets := _ghost_world_sockets()
	var best_dist     := SNAP_DIST
	var best_offset   := Vector3.ZERO

	for piece in get_tree().get_nodes_in_group("placed_planks"):
		for placed_pos: Vector3 in piece.get_world_sockets():
			for ghost_pos: Vector3 in ghost_sockets:
				var d := ghost_pos.distance_to(placed_pos)
				if d < best_dist:
					best_dist   = d
					best_offset = placed_pos - ghost_pos

	return best_offset

func _ghost_world_sockets() -> Array:
	var result := []
	for local_pos: Vector3 in PlacedPlank.sockets_for(_held_size):
		result.append(_ghost.global_transform * local_pos)
	return result

# ── Placement ────────────────────────────────────────────────────────────────

func _place() -> void:
	if not _ghost.visible or _is_blocked() or _held_item == null:
		return

	var piece := PlacedPlank.build(_held_size, _held_data.color)
	_planks_root.add_child(piece)
	piece.set_deferred("global_transform", _ghost.global_transform)

	_held_item.play_place_sound()
	_rumble(0.0, 0.7, 0.12)
	_consume_held()

func _consume_held() -> void:
	if GameState.debug_mode:
		return  # keep item, keep placing indefinitely
	player.inventory.remove(_held_item)
	_held_item.queue_free()
	_held_item = null

	if player.inventory.is_empty():
		_exit()
	else:
		_hold(player.inventory.active())
		_refresh_ghost_for_held()

# ── Remove placed piece ───────────────────────────────────────────────────────

func _remove_piece() -> void:
	var cam  := player.camera
	var from := cam.global_position
	var dir  := -cam.global_transform.basis.z
	var to   := from + dir * MAX_REACH

	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		return

	var collider: Object = hit["collider"]
	if collider is PlacedPlank:
		collider.queue_free()
	elif collider != null and collider.get_parent() is PlacedPlank:
		collider.get_parent().queue_free()

# ── Held item management ─────────────────────────────────────────────────────

func _hold(item: PhysicalItem) -> void:
	_held_item = item
	_held_data = item.item_data
	_held_size = _held_data.size if _held_data else Vector3.ONE

func _refresh_ghost_for_held() -> void:
	var box := BoxMesh.new()
	box.size = _held_size
	_ghost.mesh = box

	var c := _held_data.color if _held_data else Color(1, 1, 1)
	_mat_free = _ghost_mat(Color(c.r, c.g, c.b, 0.5))
	_ghost.material_override = _mat_free

	_update_hint()

func _update_hint() -> void:
	var item_name := _held_data.display_name if _held_data else "Item"
	UIStyle.set_hint(_label, [
		["FREEPLACE: %s  " % item_name, "@place", " Place  ", "@exit_build", " Exit"],
		["@rotate_y", " / ", "@rotate_x", " / ", "@rotate_z", " Rotate  ",
		 "@reset_rotation", " Reset  ", "@remove_piece", " Remove"],
	])

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if GameState.active_build_mode != GameConstants.BUILD_NONE:
		return
	if player.inventory.is_empty():
		return
	GameState.active_build_mode = GameConstants.BUILD_FREEPLACE

	_hold(player.inventory.active())
	_refresh_ghost_for_held()

	_active = true
	_ghost.show()
	_label.show()

func _exit() -> void:
	GameState.active_build_mode = GameConstants.BUILD_NONE
	_active    = false
	_held_item = null
	_held_data = null
	_ghost.hide()
	_label.hide()

# ── Ghost material ────────────────────────────────────────────────────────────

func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
