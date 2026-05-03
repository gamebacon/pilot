extends Node

@export var player_path: NodePath

# How close (metres) a ghost socket must be to a placed socket to snap
const SNAP_DIST := 0.3
# Degrees rotated per key press
const ROT_STEP  := 90.0
# Max ray distance when aiming
const MAX_REACH := 15.0

var _player: CharacterBody3D
var _active    := false
var _snapping  := false
var _planks_root: Node3D

# Item currently being placed (taken from the player's carry)
var _held_item: PhysicalItem = null
var _held_data: ItemData     = null
var _held_size: Vector3      = Vector3.ONE

@onready var _ghost: MeshInstance3D = $Ghost
@onready var _label: Label          = $UI/Label

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_player = get_node(player_path)

	_planks_root      = Node3D.new()
	_planks_root.name = "PlacedPlanks"
	get_parent().call_deferred("add_child", _planks_root)

	_mat_snap    = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))
	_mat_blocked = _ghost_mat(Color(0.90, 0.20, 0.20, 0.55))
	_mat_free    = _ghost_mat(Color(1.0, 1.0, 1.0, 0.50))   # replaced per-item on _enter

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _mat_free
	_ghost.hide()

	_label.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if _active: _exit()
		else:       _enter()
		return

	if not _active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var sign := -1.0 if event.shift_pressed else 1.0
		var step  := deg_to_rad(ROT_STEP) * sign
		match event.keycode:
			KEY_R: _ghost.global_rotate(Vector3.UP,      step)
			KEY_X: _ghost.global_rotate(Vector3.RIGHT,   step)
			KEY_Z: _ghost.global_rotate(Vector3.FORWARD, step)
			KEY_Q: _ghost.rotation_degrees = Vector3.ZERO
			KEY_F: _remove_piece()

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:  _place()
			MOUSE_BUTTON_RIGHT: _exit()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _active:
		_update_ghost()

func _update_ghost() -> void:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var from  := camera.global_position
	var dir   := -camera.global_transform.basis.z
	var to    := from + dir * MAX_REACH

	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit   := space.intersect_ray(query)

	if hit.is_empty():
		_ghost.hide()
		return

	_ghost.show()

	# Sit the piece flush against whatever surface was hit.
	# Project the held size onto the surface normal so the offset is correct
	# regardless of current rotation.
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
	params.exclude   = [_player.get_rid()]

	var space   := _player.get_world_3d().direct_space_state
	var results := space.intersect_shape(params, 1)
	return results.size() > 0

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

	var piece := PlacedPlank.new()
	piece.size  = _held_size
	piece.color = _held_data.color
	_planks_root.add_child(piece)

	var t := _ghost.global_transform
	piece.set_deferred("global_transform", t)

	var shape := BoxShape3D.new()
	shape.size = _held_size
	var col := CollisionShape3D.new()
	col.shape = shape
	piece.add_child(col)

	var box := BoxMesh.new()
	box.size = _held_size
	var mi := MeshInstance3D.new()
	mi.mesh              = box
	mi.material_override = _piece_mat(_held_data.color)
	piece.add_child(mi)

	_held_item.play_place_sound()

	_consume_held()

func _consume_held() -> void:
	_player.carried_items.erase(_held_item)
	_held_item.queue_free()
	_held_item = null

	# If more items remain, switch to the next one; otherwise exit build mode
	if _player.carried_items.is_empty():
		_exit()
	else:
		_hold(_player.carried_items.back())
		_refresh_ghost_for_held()

# ── Remove placed piece ───────────────────────────────────────────────────────

func _remove_piece() -> void:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var from  := camera.global_position
	var dir   := -camera.global_transform.basis.z
	var to    := from + dir * MAX_REACH

	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit   := space.intersect_ray(query)

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

	# Keep rotation for next peice? ( commented out )
	# _ghost.rotation = Vector3.ZERO

	_label.text = _hint_text()

func _hint_text() -> String:
	var item_name: String = _held_data.display_name if _held_data else "Item"
	return (
		"BUILD MODE: %s    [LMB] Place    [RMB] Exit\n" % item_name
		+ "[R / Shift+R] Yaw    [X / Shift+X] Pitch    [Z / Shift+Z] Roll    [Q] Reset    [F] Remove"
	)

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if _player.carried_items.is_empty():
		return  # Need an item in hand to enter build mode

	_hold(_player.carried_items.back())
	_refresh_ghost_for_held()

	_active = true
	_ghost.show()
	_label.show()

func _exit() -> void:
	_active     = false
	_held_item  = null
	_held_data  = null
	_ghost.hide()
	_label.hide()

# ── Material helpers ──────────────────────────────────────────────────────────

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# Solid material with slight per-piece tonal variation for a natural look
func _piece_mat(base: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var v   := randf_range(-0.05, 0.05)
	mat.albedo_color = Color(
		clampf(base.r + v, 0.0, 1.0),
		clampf(base.g + v, 0.0, 1.0),
		clampf(base.b + v, 0.0, 1.0),
		base.a
	)
	return mat
