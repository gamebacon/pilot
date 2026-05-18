extends Node

const SNAP_DIST := 0.3
const ROT_STEP  := 90.0
const MAX_REACH := 15.0

var _active      := false
var _snapping    := false
var _place_held  := false  # hysteresis gate: arm ≥ 0.9, disarm ≤ 0.1
var _planks_root: Node3D
var _net_counter := 0

var _held_item: PhysicalItem = null
var _held_data: ItemData     = null
var _held_size: Vector3      = Vector3.ONE

var player: Player = null
@onready var _ghost: MeshInstance3D = $Ghost

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_planks_root      = Node3D.new()
	_planks_root.name = "PlacedPlanks"
	add_child(_planks_root)  # child of self — survives reparenting, never inside Factory

	_mat_snap    = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))
	_mat_blocked = _ghost_mat(Color(0.90, 0.20, 0.20, 0.55))
	_mat_free    = _ghost_mat(Color(1.0, 1.0, 1.0, 0.50))

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _mat_free
	_ghost.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("rotate_y") and not event.is_echo():
		_ghost.global_rotate(Vector3.UP, deg_to_rad(ROT_STEP))

	if event.is_action_pressed("exit_build"):
		_exit()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not player:
		for p in get_tree().get_nodes_in_group("player"):
			if not NetworkManager.is_active() or p.is_multiplayer_authority():
				player = p
				break
		return

	if Input.is_action_just_pressed("build_mode"):
		if _active: _exit()
		else:       _enter()

	if not _active:
		return
	# Keep held item in sync with whatever the player cycles to.
	var active := player.inventory.active()
	if active != null and active != _held_item:
		_hold(active)
		_refresh_ghost_for_held()
	if Input.is_action_just_pressed("attack") and not _place_held:
		_place_held = true
		_place()
		if not _active:
			return
	elif _place_held and Input.get_action_raw_strength("attack") <= 0.1:
		_place_held = false
	_update_ghost()

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

	var net_id := _assign_net_id()
	var world_t := _ghost.global_transform

	var piece := PlacedPlank.build(_held_size, _held_data.color)
	piece.net_id = net_id
	_planks_root.add_child(piece)
	piece.set_deferred("global_transform", world_t)

	_held_item.play_place_sound()
	_rumble(0.0, 0.7, 0.12)

	if NetworkManager.is_active() and _held_data:
		if NetworkManager.is_server():
			_sync_place.rpc(_held_data.id, world_t, net_id)
		else:
			_request_place.rpc_id(1, _held_data.id, world_t, net_id)

	_consume_held()

func _consume_held() -> void:
	if GameState.debug_mode:
		return  # keep item, keep placing indefinitely
	player.inventory.remove(_held_item)
	if NetworkManager.is_active() and _held_item.net_id != 0:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			world.sync_item_consume(_held_item.net_id)
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
	var plank: PlacedPlank = null
	if collider is PlacedPlank:
		plank = collider
	elif collider != null and collider.get_parent() is PlacedPlank:
		plank = collider.get_parent()

	if not plank:
		return

	var net_id := plank.net_id
	plank.queue_free()

	if NetworkManager.is_active() and net_id != 0:
		if NetworkManager.is_server():
			_sync_remove.rpc(net_id)
		else:
			_request_remove.rpc_id(1, net_id)

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

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if not player or GameState.is_building:
		return
	var active_item := player.inventory.active()
	if not active_item:
		return
	GameState.is_building = true

	_hold(active_item)
	_refresh_ghost_for_held()

	_active = true
	_ghost.show()

func _exit() -> void:
	GameState.is_building = false
	_active    = false
	_held_item = null
	_held_data = null
	_ghost.hide()

# ── Multiplayer ───────────────────────────────────────────────────────────────

func _assign_net_id() -> int:
	_net_counter += 1
	var my_id := 1 if not NetworkManager.is_active() else multiplayer.get_unique_id()
	return my_id * 100000 + _net_counter

@rpc("any_peer", "reliable")
func _request_place(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_place_local(item_id, world_transform, net_id)
	for pid in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_place.rpc_id(pid, item_id, world_transform, net_id)

@rpc("authority", "reliable")
func _sync_place(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	_apply_place_local(item_id, world_transform, net_id)

func _apply_place_local(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	var data := ItemRegistry.get_item(item_id)
	if not data:
		return
	var piece := PlacedPlank.build(data.size, data.color)
	piece.net_id = net_id
	_planks_root.add_child(piece)
	piece.set_deferred("global_transform", world_transform)

@rpc("any_peer", "reliable")
func _request_remove(net_id: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_remove_local(net_id)
	for pid in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_remove.rpc_id(pid, net_id)

@rpc("authority", "reliable")
func _sync_remove(net_id: int) -> void:
	_apply_remove_local(net_id)

func _apply_remove_local(net_id: int) -> void:
	for piece in get_tree().get_nodes_in_group("placed_planks"):
		if (piece as PlacedPlank).net_id == net_id:
			piece.queue_free()
			return

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
