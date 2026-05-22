class_name BuildSystem
extends Node

const SNAP_DIST            := 0.3
const ROT_STEP             := 90.0
const MAX_REACH            : float = 15.0
const FOUNDATION_REACH    : float = 4.0
const FOUNDATION_MAX_HOVER: float = 2.0   # max gap between foundation bottom and terrain
const FOUNDATION_SNAP_DIST: float = 1.2

var _active     := false
var _snapping   := false
var _place_held := false

var _pieces_root: Node3D
var _placed_root: Node3D

# Data-only snapshot of the active inventory slot — no node reference.
var _held_id:     String   = ""
var _held_data:   ItemData = null
var _held_size:   Vector3  = Vector3.ONE
var _held_net_id: int      = 0

var player: Player = null
@onready var _ghost: MeshInstance3D = $Ghost

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_pieces_root      = Node3D.new()
	_pieces_root.name = "PlacedPieces"
	add_child(_pieces_root)

	_placed_root      = Node3D.new()
	_placed_root.name = "PlacedItems"
	add_child(_placed_root)

	_mat_snap    = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))
	_mat_blocked = _ghost_mat(Color(0.90, 0.20, 0.20, 0.55))
	_mat_free    = _ghost_mat(Color(1.0,  1.0,  1.0,  0.50))

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _mat_free
	_ghost.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event.is_action_pressed("rotate") and not event.is_echo():
		if _held_data != null and _held_data.can_rotate:
			_ghost.global_rotate(Vector3.UP, deg_to_rad(ROT_STEP))
	if event.is_action_pressed("exit_build"):
		_exit()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not player:
		for p: Node in get_tree().get_nodes_in_group("player"):
			if not NetworkManager.is_active() or p.is_multiplayer_authority():
				player = p as Player
				break
		return

	if Input.is_action_just_pressed("build_mode"):
		if _active: _exit()
		else:       _enter()

	if not _active: return

	# Exit if the active slot switched to a non-placeable item.
	var slot: Inventory.Slot = player.inventory.active_slot_data()
	var cur_id: String = slot.item_id if slot else ""
	if cur_id != _held_id:
		var cur_data: ItemData = slot.get_data() if slot else null
		if cur_id.is_empty() or cur_data == null or not cur_data.is_placeable:
			_exit(); return
		_hold_from_slot(slot)
		_refresh_ghost_for_held()

	if Input.is_action_just_pressed("attack") and not _place_held:
		_place_held = true
		_place()
		if not _active: return
	elif _place_held and Input.get_action_raw_strength("attack") <= 0.1:
		_place_held = false

	_update_ghost()

func _update_ghost() -> void:
	var cam: Camera3D = player.camera

	if _is_foundation_held():
		_update_ghost_foundation(cam)
		return

	var from: Vector3 = cam.global_position
	var to:   Vector3 = from + (-cam.global_transform.basis.z) * MAX_REACH

	var space: PhysicsDirectSpaceState3D   = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)

	if hit.is_empty():
		_ghost.hide(); return
	_ghost.show()

	var basis: Basis   = _ghost.global_transform.basis
	var hh:    Vector3 = _held_size * 0.5
	var half_extent: float = (
		abs(basis.x.dot(hit.normal)) * hh.x +
		abs(basis.y.dot(hit.normal)) * hh.y +
		abs(basis.z.dot(hit.normal)) * hh.z
	)
	_ghost.global_position = hit.position + hit.normal * half_extent

	var offset: Vector3 = _find_snap_offset()
	_snapping = offset != Vector3.ZERO
	if _snapping:
		_ghost.global_position += offset

	_update_ghost_material()

# ── Foundation ghost ──────────────────────────────────────────────────────────

func _update_ghost_foundation(cam: Camera3D) -> void:
	# Yaw only — slab stays flat and faces where the player is looking.
	var yaw: float = cam.global_transform.basis.get_euler(EULER_ORDER_YXZ).y
	_ghost.global_rotation = Vector3(0.0, yaw, 0.0)

	# Fixed distance along the full camera direction; pitch naturally moves it
	# up or down to compensate for rugged terrain.
	_ghost.global_position = cam.global_position + (-cam.global_transform.basis.z) * FOUNDATION_REACH

	# Snap to an adjacent placed foundation when one is close enough.
	var snap: Dictionary  = _find_foundation_grid_snap()
	var is_snapping: bool = not snap.is_empty()
	if is_snapping:
		_ghost.global_position = snap["position"]
		_ghost.global_rotation = Vector3(0.0, snap["yaw"] as float, 0.0)
	_snapping = is_snapping
	_ghost.show()

	var blocked: bool = _is_blocked() or _foundation_ground_invalid()
	if blocked:
		_ghost.material_override = _mat_blocked
	elif is_snapping:
		_ghost.material_override = _mat_snap
	else:
		_ghost.material_override = _mat_free

# Single downward raycast that enforces three ground rules:
#   1. Underground  — terrain surface is above the foundation's bottom face.
#   2. Too high     — foundation bottom is more than FOUNDATION_MAX_HOVER above terrain.
#   3. Stacking     — the first thing below is another placed piece (foundation on foundation).
# Returns true when placement should be blocked.
func _foundation_ground_invalid() -> bool:
	var center:            Vector3 = _ghost.global_position
	var foundation_bottom: float   = center.y - _held_size.y * 0.5
	var space: PhysicsDirectSpaceState3D   = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(center.x, center.y + 4.0, center.z),
		Vector3(center.x, center.y - 8.0, center.z))
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)

	if hit.is_empty():
		return true  # nothing below at all — floating in void

	# Stacking: another placed piece is directly below.
	if hit["collider"] is PlacedPiece:
		return true

	var terrain_y: float = hit["position"].y as float

	# Underground: terrain surface pokes above foundation bottom.
	if terrain_y > foundation_bottom + 0.05:
		return true

	# Too high: foundation is hovering more than FOUNDATION_MAX_HOVER above terrain.
	if foundation_bottom - terrain_y > FOUNDATION_MAX_HOVER:
		return true

	return false

# Returns the snapped {position, yaw} for the nearest open grid slot adjacent to
# any placed foundation, or an empty dict if nothing is within FOUNDATION_SNAP_DIST.
func _find_foundation_grid_snap() -> Dictionary:
	var ghost_pos: Vector3    = _ghost.global_position
	var best_dist: float      = FOUNDATION_SNAP_DIST
	var best:      Dictionary = {}
	for piece: PlacedPiece in get_tree().get_nodes_in_group("placed_pieces"):
		if not piece.is_foundation: continue
		var pb: Basis = piece.global_transform.basis
		var candidates: Array[Vector3] = [
			piece.global_position + pb.x * piece.size.x,
			piece.global_position - pb.x * piece.size.x,
			piece.global_position + pb.z * piece.size.z,
			piece.global_position - pb.z * piece.size.z,
		]
		for candidate: Vector3 in candidates:
			# Lock Y to the existing foundation so the grid stays level.
			var snap_pos: Vector3 = Vector3(candidate.x, piece.global_position.y, candidate.z)
			# XZ-only distance so slope height differences don't block snapping.
			var flat_d: float = Vector2(ghost_pos.x - snap_pos.x, ghost_pos.z - snap_pos.z).length()
			if flat_d < best_dist:
				best_dist = flat_d
				best = {"position": snap_pos, "yaw": piece.global_rotation.y}
	return best

# ── Wall / piece snap ─────────────────────────────────────────────────────────

# Finds the closest socket pair between the ghost and any placed foundation,
# returns a world-space offset to apply to the ghost position.
func _find_snap_offset() -> Vector3:
	var ghost_sockets: Array[Vector3] = _ghost_world_sockets()
	var best_dist:     float          = SNAP_DIST
	var best_offset:   Vector3        = Vector3.ZERO
	var ghost_center:  Vector3        = _ghost.global_position
	for piece: PlacedPiece in get_tree().get_nodes_in_group("placed_pieces"):
		if not piece.is_foundation: continue
		if piece.global_position.distance_to(ghost_center) > MAX_REACH + piece.size.length() * 0.5:
			continue
		for placed_pos: Vector3 in piece.get_world_sockets():
			for ghost_pos: Vector3 in ghost_sockets:
				var d: float = ghost_pos.distance_to(placed_pos)
				if d < best_dist:
					best_dist   = d
					best_offset = placed_pos - ghost_pos
	return best_offset

func _ghost_world_sockets() -> Array[Vector3]:
	if _held_data is PlaceableItemData: return []
	var result: Array[Vector3] = []
	for local_pos: Vector3 in PlacedPiece.sockets_for(_held_size):
		result.append(_ghost.global_transform * local_pos)
	return result

# ── Placement predicates ──────────────────────────────────────────────────────

func _is_foundation_held() -> bool:
	return _held_data != null and _held_data.is_foundation

func _is_free_placement() -> bool:
	return _held_data != null and _held_data.free_placement

func _is_blocked() -> bool:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = _held_size
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = _ghost.global_transform
	params.margin    = -0.02
	params.exclude   = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(params, 1).size() > 0

func _update_ghost_material() -> void:
	if _is_blocked() or (not _is_free_placement() and not _snapping):
		_ghost.material_override = _mat_blocked
	elif _snapping:
		_ghost.material_override = _mat_snap
	else:
		_ghost.material_override = _mat_free

# ── Placement ────────────────────────────────────────────────────────────────

func _place() -> void:
	if not _ghost.visible or _held_id.is_empty(): return
	if _is_foundation_held():
		if _ghost.material_override == _mat_blocked: return
	else:
		if _is_blocked(): return
		if not _is_free_placement() and not _snapping: return

	var net_id:  int         = _assign_net_id()
	var world_t: Transform3D = _ghost.global_transform

	_apply_place_local(_held_id, world_t, net_id)

	if player.inventory.active_slot_data() and player._held_visual:
		player._held_visual.play_place_sound()
	_rumble(0.0, 0.7, 0.12)

	if NetworkManager.is_active() and _held_data:
		if NetworkManager.is_server():
			_sync_place.rpc(_held_id, world_t, net_id)
		else:
			_request_place.rpc_id(1, _held_id, world_t, net_id)

	_consume_held()

func _consume_held() -> void:
	if GameState.debug_mode: return

	player.inventory.remove_active_one()
	_held_id     = ""
	_held_data   = null
	_held_net_id = 0

	var slot: Inventory.Slot = player.inventory.active_slot_data()
	if slot == null or slot.is_empty():
		_exit()
	else:
		_hold_from_slot(slot)
		_refresh_ghost_for_held()

# ── Remove placed piece ───────────────────────────────────────────────────────

func _remove_piece() -> void:
	var cam:  Camera3D = player.camera
	var from: Vector3  = cam.global_position
	var to:   Vector3  = from + (-cam.global_transform.basis.z) * MAX_REACH

	var space: PhysicsDirectSpaceState3D   = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty(): return

	var collider: Object    = hit["collider"]
	var piece:    PlacedPiece = null
	if collider is PlacedPiece:
		piece = collider as PlacedPiece
	elif collider != null and collider.get_parent() is PlacedPiece:
		piece = collider.get_parent() as PlacedPiece
	if not piece: return

	var net_id: int = piece.net_id
	_apply_remove_local(net_id)

	if NetworkManager.is_active() and net_id != 0:
		if NetworkManager.is_server():
			_sync_remove.rpc(net_id)
		else:
			_request_remove.rpc_id(1, net_id)

# ── Held item management ──────────────────────────────────────────────────────

func _hold_from_slot(slot: Inventory.Slot) -> void:
	_held_id     = slot.item_id
	_held_data   = slot.get_data()
	_held_size   = _held_data.size if _held_data else Vector3.ONE
	_held_net_id = slot.active_net_id()

func _refresh_ghost_for_held() -> void:
	var box: BoxMesh     = BoxMesh.new()
	box.size             = _held_size
	_ghost.mesh          = box
	var c: Color         = _held_data.color if _held_data else Color(1.0, 1.0, 1.0)
	_mat_free            = _ghost_mat(Color(c.r, c.g, c.b, 0.5))
	_ghost.material_override = _mat_free

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if not player or GameState.is_building: return
	var slot: Inventory.Slot = player.inventory.active_slot_data()
	if slot == null or slot.is_empty(): return
	var data: ItemData = slot.get_data()
	if data == null or not data.is_placeable: return
	GameState.is_building = true
	_hold_from_slot(slot)
	_refresh_ghost_for_held()
	_active = true
	_ghost.show()

func _exit() -> void:
	GameState.is_building = false
	_active      = false
	_held_id     = ""
	_held_data   = null
	_held_net_id = 0
	_ghost.hide()

# ── Multiplayer ───────────────────────────────────────────────────────────────

func _assign_net_id() -> int:
	return get_tree().get_first_node_in_group("world").assign_item_id()

@rpc("any_peer", "reliable")
func _request_place(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	if not NetworkManager.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_apply_place_local(item_id, world_transform, net_id)
	for pid: int in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_place.rpc_id(pid, item_id, world_transform, net_id)

@rpc("authority", "reliable")
func _sync_place(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	_apply_place_local(item_id, world_transform, net_id)

func _apply_place_local(item_id: String, world_transform: Transform3D, net_id: int) -> void:
	var data: ItemData = ItemRegistry.get_item(item_id)
	if not data: return
	var world: Node  = get_tree().get_first_node_in_group("world")
	var node: Node3D
	if data is PlaceableItemData:
		var scene: PackedScene = (data as PlaceableItemData).get_placement_scene()
		if not scene: return
		node = scene.instantiate()
		node.set("net_id", net_id)
		_placed_root.add_child(node)
	else:
		var piece: PlacedPiece = PlacedPiece.build(data.size, data.color)
		piece.net_id        = net_id
		piece.is_foundation = data.is_foundation
		_pieces_root.add_child(piece)
		node = piece
	node.set_meta("item_id", item_id)
	node.set_deferred("global_transform", world_transform)
	if world:
		world.register_piece(net_id, node)

@rpc("any_peer", "reliable")
func _request_remove(net_id: int) -> void:
	if not NetworkManager.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_apply_remove_local(net_id)
	for pid: int in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_remove.rpc_id(pid, net_id)

@rpc("authority", "reliable")
func _sync_remove(net_id: int) -> void:
	_apply_remove_local(net_id)

func _apply_remove_local(net_id: int) -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if not world: return
	var piece: Node3D = world.unregister_piece(net_id)
	if piece:
		piece.queue_free()

func apply_piece_snapshot(snapshot: Array[Dictionary]) -> void:
	for entry: Dictionary in snapshot:
		_apply_place_local(entry["item_id"], entry["transform"], entry["net_id"])

# ── Helpers ───────────────────────────────────────────────────────────────────

func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
