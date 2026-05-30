class_name BuildSystem
extends Node

const ROT_STEP:              float = 90.0
const MAX_REACH:             float = 15.0
# Foundation placement constants (camera-relative system).
const FOUNDATION_REACH:        float = 4.0   # fixed camera-forward distance for slab placement
const FOUNDATION_MAX_HOVER:    float = 2.0   # max gap between foundation bottom and terrain
const FOUNDATION_SNAP_DIST:    float = 2.0   # XZ snap radius to adjacent placed foundations
const FOUNDATION_MAX_SINK:     float = 0.5   # how deep the foundation bottom can go below terrain
# How close the ghost can be to any foundation before free placement is blocked.
# Must be larger than (foundation size + FOUNDATION_SNAP_DIST) so there is no gap
# between the snap zone and the block zone — prevents unaligned "close but not snapped" slabs.
const FOUNDATION_BLOCK_RADIUS: float = 6.0
# Wall / tower placement constant.
const BUILDING_SNAP_DIST:    float = 2.0   # XZ radius to snap onto a foundation centre

var _active:     bool = false
var _snapping:   bool = false
var _place_held: bool = false

var _building_rot_offset:       float   = 0.0  # player's R-key offset on top of snapped foundation yaw
var _foundation_stretched_h:    float   = 0.0  # actual placed height this frame (may exceed data.size.y)

var _pieces_root: Node3D
var _placed_root: Node3D

var _held_id:     String   = ""
var _held_data:   ItemData = null
var _held_size:   Vector3  = Vector3.ONE
var _held_net_id: int      = 0

var player: Player = null
@onready var _ghost: MeshInstance3D = $Ghost

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

var _ghost_mesh_child: Node3D = null  # instantiated mesh_scene shown instead of BoxMesh


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
	_mat_free    = _ghost_mat(Color(0.20, 0.60, 0.95, 0.50))

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_ghost_material(_mat_free)
	_ghost.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event.is_action_pressed("rotate") and not event.is_echo():
		if _held_data != null and _held_data.can_rotate:
			if _is_building_piece():
				# Accumulate offset; ghost rotation is applied each frame in _update_ghost_building.
				_building_rot_offset += deg_to_rad(ROT_STEP)
			else:
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

	var slot: Inventory.ItemStack = player.inventory.active_slot_data()
	var cur_id: String = slot.item_id if slot else ""
	if cur_id != _held_id:
		var cur_data: ItemData = slot.get_data() if slot else null
		if cur_id.is_empty() or cur_data == null or not cur_data.is_placeable:
			_exit(); return
		_hold_from_slot(slot)
		_refresh_ghost_for_held()

	if Input.is_action_just_pressed("interact") and not _place_held:
		_place_held = true
		_place()
		if not _active: return
	elif _place_held and Input.get_action_raw_strength("interact") <= 0.1:
		_place_held = false

	_update_ghost()

# ── Ghost update ──────────────────────────────────────────────────────────────

func _update_ghost() -> void:
	var cam: Camera3D = player.camera

	# Foundations use a camera-relative path — no terrain raycast needed.
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

	if _is_building_piece():
		_update_ghost_building(hit)
	else:
		_update_ghost_free(hit)

# ── Foundation ghost (your original system) ───────────────────────────────────

func _update_ghost_foundation(cam: Camera3D) -> void:
	# Yaw only — slab stays flat regardless of camera pitch.
	var yaw: float = cam.global_transform.basis.get_euler(EULER_ORDER_YXZ).y
	_ghost.global_rotation = Vector3(0.0, yaw, 0.0)

	# Float at fixed distance along the camera forward direction.
	_ghost.global_position = cam.global_position + (-cam.global_transform.basis.z) * FOUNDATION_REACH

	# Snap to an adjacent placed foundation when one is close enough.
	var snap: Dictionary  = _find_foundation_grid_snap()
	var is_snapping: bool = not snap.is_empty()
	if is_snapping:
		_ghost.global_position = snap["position"]
		_ghost.global_rotation = Vector3(0.0, snap["yaw"] as float, 0.0)
	_snapping = is_snapping

	# Block free placement near existing foundations — the player must either snap
	# onto the grid or move far enough away to start a genuinely separate group.
	# This prevents placing an unaligned slab that looks adjacent but isn't synced.
	if not is_snapping and _is_near_any_foundation():
		_ghost.show()
		_set_ghost_material(_mat_blocked)
		return

	# Stretch the bottom face down to terrain — top face stays at current position.
	# When snapping, top_y is locked to the adjacent piece's top face so the surface
	# is always flush.  Do NOT clamp to min height here — on rising terrain the clamp
	# would push the top face above top_y and cause a height mismatch.
	# In free placement the min-height clamp still applies to keep the slab usable.
	var top_y: float = snap["top_y"] as float if is_snapping else _ghost.global_position.y + _held_size.y * 0.5
	var terrain_y:   float = _sample_terrain_y(_ghost.global_position)
	var raw_h:       float = top_y - terrain_y
	var stretched_h: float = raw_h if is_snapping else max(_held_size.y, raw_h)
	_foundation_stretched_h       = stretched_h
	_ghost.global_position.y      = terrain_y + stretched_h * 0.5
	(_ghost.mesh as BoxMesh).size = Vector3(_held_size.x, stretched_h, _held_size.z)

	# Terrain is flush with or above the snap level — can't place here.
	if is_snapping and raw_h < 0.05:
		_ghost.show()
		_set_ghost_material(_mat_blocked)
		return

	if _foundation_ground_invalid():
		_ghost.show()
		_set_ghost_material(_mat_blocked)
		return
	_ghost.show()
	_set_ghost_material(_mat_snap if is_snapping else _mat_free)

## Returns the lowest terrain Y beneath the foundation footprint by sampling the
## centre and four inset corners.  Taking the minimum ensures the slab always
## reaches down to the deepest dip — a centre-only sample misses terrain that
## dips near the edges and leaves an air gap on the underside.
func _sample_terrain_y(at: Vector3) -> float:
	var hx: float = _held_size.x * 0.45
	var hz: float = _held_size.z * 0.45
	var offsets: Array[Vector2] = [
		Vector2(0.0,  0.0),
		Vector2( hx,  hz), Vector2(-hx,  hz),
		Vector2( hx, -hz), Vector2(-hx, -hz),
	]
	var min_y: float = 1e9
	for off: Vector2 in offsets:
		var hit_y: float = _cast_terrain_ray(Vector3(at.x + off.x, at.y, at.z + off.y))
		if hit_y < min_y:
			min_y = hit_y
	return min_y if min_y < 1e8 else at.y - _held_size.y * 0.5

## Shoots a single ray straight down, skipping any PlacedPiece it encounters,
## so it always returns the terrain surface below any placed structures.
## Returns a large sentinel value (1e9) if no terrain is found.
func _cast_terrain_ray(at: Vector3) -> float:
	var space:   PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var start_y: float = at.y + 10.0
	var end_y:   float = at.y - 30.0
	for _i: int in 4:  # max passes through stacked placed pieces
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(at.x, start_y, at.z),
			Vector3(at.x, end_y,   at.z))
		query.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		if not (hit["collider"] is PlacedPiece):
			return hit["position"].y as float
		# Landed on a placed piece — step below it and cast again.
		start_y = (hit["position"].y as float) - 0.05
		if start_y <= end_y:
			break
	return 1e9

## Returns true if placement should be blocked:
##   - No terrain found below.
##   - Another placed piece is directly below (no stacking foundations).
func _foundation_ground_invalid() -> bool:
	var center: Vector3 = _ghost.global_position
	var space:  PhysicsDirectSpaceState3D   = player.get_world_3d().direct_space_state
	var query:  PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(center.x, center.y + 4.0, center.z),
		Vector3(center.x, center.y - _foundation_stretched_h - 2.0, center.z))
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	if hit["collider"] is PlacedPiece:
		return true
	return false

## Returns true when the ghost is within FOUNDATION_BLOCK_RADIUS of any placed
## foundation, used to block free placement that would produce an unaligned slab.
func _is_near_any_foundation() -> bool:
	var ghost_xz: Vector2 = Vector2(_ghost.global_position.x, _ghost.global_position.z)
	for piece: PlacedPiece in get_tree().get_nodes_in_group("placed_pieces"):
		if not piece.is_foundation: continue
		var piece_xz: Vector2 = Vector2(piece.global_position.x, piece.global_position.z)
		if ghost_xz.distance_to(piece_xz) < FOUNDATION_BLOCK_RADIUS:
			return true
	return false

## Returns {position, yaw} for the nearest open grid slot adjacent to any placed
## foundation, or an empty Dictionary if nothing is within FOUNDATION_SNAP_DIST.
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
			var snap_pos: Vector3 = Vector3(candidate.x, piece.global_position.y, candidate.z)
			var snap_xz:  Vector2 = Vector2(snap_pos.x, snap_pos.z)
			# Skip slots already filled by another foundation so the ghost never
			# snaps to a red blocked position — only open slots are offered.
			var is_occupied: bool = false
			for other: PlacedPiece in get_tree().get_nodes_in_group("placed_pieces"):
				if not other.is_foundation or other == piece: continue
				var other_xz: Vector2 = Vector2(other.global_position.x, other.global_position.z)
				if other_xz.distance_to(snap_xz) < 0.3:
					is_occupied = true
					break
			if is_occupied: continue
			# XZ-only distance so slope height differences don't block snapping.
			var flat_d: float = Vector2(ghost_pos.x - snap_pos.x, ghost_pos.z - snap_pos.z).length()
			if flat_d < best_dist:
				best_dist = flat_d
				best = {
					"position": snap_pos,
					"yaw":      piece.global_rotation.y,
					"top_y":    piece.global_position.y + piece.size.y * 0.5,
				}

	return best

# ── Building ghost (walls, towers) ───────────────────────────────────────────

func _update_ghost_building(hit: Dictionary) -> void:
	# Start at the raycast surface so the ghost is always visible.
	var hh: Vector3 = _held_size * 0.5
	_ghost.global_position = hit.position + hit.normal * hh.y

	# Snap XZ+Y to the nearest foundation centre and inherit its yaw.
	var snap: Dictionary = _find_foundation_center_snap()
	_snapping = not snap.is_empty()

	if _snapping:
		_ghost.global_position = snap["position"]
		_ghost.global_rotation = Vector3(0.0, (snap["yaw"] as float) + _building_rot_offset, 0.0)

	if _is_blocked():
		_set_ghost_material(_mat_blocked)
		return
	_set_ghost_material(_mat_snap if _snapping else _mat_free)

## Returns {position, yaw} for the nearest foundation within BUILDING_SNAP_DIST,
## or an empty Dictionary when nothing is close enough.
func _find_foundation_center_snap() -> Dictionary:
	var ghost_xz:  Vector2   = Vector2(_ghost.global_position.x, _ghost.global_position.z)
	var best_dist: float     = BUILDING_SNAP_DIST
	var best:      Dictionary = {}

	for piece: PlacedPiece in get_tree().get_nodes_in_group("placed_pieces"):
		if not piece.is_foundation: continue
		var piece_xz: Vector2 = Vector2(piece.global_position.x, piece.global_position.z)
		var d: float = ghost_xz.distance_to(piece_xz)
		if d < best_dist:
			best_dist = d
			var top_y: float = piece.global_position.y + piece.size.y * 0.5
			best = {
				"position": Vector3(piece.global_position.x, top_y + _held_size.y * 0.5, piece.global_position.z),
				"yaw":      piece.global_rotation.y,
			}

	return best

# ── Free ghost (chests, interactables) ───────────────────────────────────────

func _update_ghost_free(hit: Dictionary) -> void:
	var basis: Basis   = _ghost.global_transform.basis
	var hh:    Vector3 = _held_size * 0.5
	var half_extent: float = (
		abs(basis.x.dot(hit.normal)) * hh.x +
		abs(basis.y.dot(hit.normal)) * hh.y +
		abs(basis.z.dot(hit.normal)) * hh.z
	)
	_ghost.global_position = hit.position + hit.normal * half_extent
	_snapping = true  # free-placement items are always valid

	if _is_blocked():
		_set_ghost_material(_mat_blocked)
		return
	_set_ghost_material(_mat_free)

# ── Overlap check ─────────────────────────────────────────────────────────────

func _is_blocked() -> bool:
	var shape:  BoxShape3D                    = BoxShape3D.new()
	shape.size  = _held_size
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = _ghost.global_transform
	params.margin    = -0.02
	params.exclude   = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(params, 1).size() > 0


# ── Placement ────────────────────────────────────────────────────────────────

func _place() -> void:
	if not _ghost.visible or _held_id.is_empty(): return

	if _is_foundation_held():
		if _ghost.material_override == _mat_blocked: return
	elif _is_building_piece():
		if not _snapping or _is_blocked(): return
	else:
		if _is_blocked(): return
		if not _is_free_placement() and not _snapping: return

	var net_id:     int         = _assign_net_id()
	var world_t:    Transform3D = _ghost.global_transform
	var place_size: Vector3     = _held_size
	if _is_foundation_held():
		place_size = Vector3(_held_size.x, _foundation_stretched_h, _held_size.z)

	_apply_place_local(_held_id, world_t, net_id, place_size)

	if player._held_visual:
		player._held_visual.play_place_sound()
	_rumble(0.0, 0.7, 0.12)

	if NetworkManager.is_active() and _held_data:
		if NetworkManager.is_server():
			_sync_place.rpc(_held_id, world_t, net_id, place_size)
		else:
			_request_place.rpc_id(1, _held_id, world_t, net_id, place_size)

	_consume_held()

func _consume_held() -> void:
	if GameState.debug_mode: return

	player.inventory.remove_active_one()
	_held_id     = ""
	_held_data   = null
	_held_net_id = 0

	var slot: Inventory.ItemStack = player.inventory.active_slot_data()
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

	var collider: Object      = hit["collider"]
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

# ── Predicates ────────────────────────────────────────────────────────────────

func _is_building_piece() -> bool:
	return _held_data is BuildingItemData and not (_held_data as BuildingItemData).piece_type.is_empty()

func _is_foundation_held() -> bool:
	return _held_data != null and _held_data.is_foundation

func _is_free_placement() -> bool:
	return _held_data != null and _held_data.free_placement

# ── Held item management ─────────────────────────────────────────────────────

func _hold_from_slot(slot: Inventory.ItemStack) -> void:
	_held_id              = slot.item_id
	_held_data            = slot.get_data()
	_held_size            = _held_data.size if _held_data else Vector3.ONE
	_held_net_id          = slot.active_net_id()
	_building_rot_offset  = 0.0

func _refresh_ghost_for_held() -> void:
	if _ghost_mesh_child:
		_ghost_mesh_child.queue_free()
		_ghost_mesh_child = null

	var bdata: BuildingItemData = _held_data as BuildingItemData if _held_data is BuildingItemData else null
	if bdata != null and bdata.mesh_scene != null:
		_ghost.mesh       = null
		_ghost_mesh_child = bdata.mesh_scene.instantiate() as Node3D
		_ghost.add_child(_ghost_mesh_child)

		# Match PlacedPiece.build(): shift down by half-height so a bottom-origin
		# mesh sits correctly inside the ghost box. XZ offset from Blender is kept.
		_ghost_mesh_child.position = Vector3(0.0, -_held_size.y * 0.5, 0.0) + bdata.visual_offset
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size         = _held_size
		_ghost.mesh      = box

	_mat_free = _ghost_mat(Color(0.20, 0.60, 0.95, 0.50))
	_set_ghost_material(_mat_free)

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if not player or GameState.is_building: return
	var slot: Inventory.ItemStack = player.inventory.active_slot_data()
	if slot == null or slot.is_empty(): return
	var data: ItemData = slot.get_data()
	if data == null or not data.is_placeable: return
	GameState.is_building = true
	_hold_from_slot(slot)
	_refresh_ghost_for_held()
	_active = true
	_ghost.show()

func _exit() -> void:
	GameState.is_building    = false
	_active                  = false
	_snapping                = false
	_held_id                 = ""
	_held_data               = null
	_held_net_id             = 0
	_building_rot_offset     = 0.0
	_ghost.hide()

# ── Multiplayer ───────────────────────────────────────────────────────────────

func _assign_net_id() -> int:
	return get_tree().get_first_node_in_group("world").assign_item_id()

@rpc("any_peer", "reliable")
func _request_place(item_id: String, world_transform: Transform3D, net_id: int, actual_size: Vector3) -> void:
	if not NetworkManager.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_apply_place_local(item_id, world_transform, net_id, actual_size)
	for pid: int in NetworkManager.players.keys():
		if pid != 1 and pid != sender_id:
			_sync_place.rpc_id(pid, item_id, world_transform, net_id, actual_size)

@rpc("authority", "reliable")
func _sync_place(item_id: String, world_transform: Transform3D, net_id: int, actual_size: Vector3) -> void:
	_apply_place_local(item_id, world_transform, net_id, actual_size)

## `actual_size` overrides `data.size` — used for foundations whose height
## is stretched to terrain at placement time.
func _apply_place_local(item_id: String, world_transform: Transform3D, net_id: int, actual_size: Vector3 = Vector3.ZERO) -> void:
	var data: ItemData = ItemRegistry.get_item(item_id)
	if not data: return
	var world: Node = get_tree().get_first_node_in_group("world")
	var node: Node3D

	if data is PlaceableItemData:
		var scene: PackedScene = (data as PlaceableItemData).get_placement_scene()
		if not scene: return
		node = scene.instantiate()
		node.set("net_id", net_id)
		node.name = "placed_%d" % net_id   # deterministic — net_id is identical on all peers
		_placed_root.add_child(node)
	else:
		var use_size:   Vector3          = actual_size if actual_size != Vector3.ZERO else data.size
		var bdata:      BuildingItemData = data as BuildingItemData if data is BuildingItemData else null
		var bscene:     PackedScene      = bdata.mesh_scene    if bdata != null else null
		var vis_offset: Vector3          = bdata.visual_offset if bdata != null else Vector3.ZERO
		var piece: PlacedPiece           = PlacedPiece.build(use_size, data.color, bscene, vis_offset)
		piece.net_id        = net_id
		piece.is_foundation = data.is_foundation
	 	# ? piece.blocker_priority = data.blocker_priority
		piece.name          = "piece_%d" % net_id   # deterministic — net_id is identical on all peers
		if bdata != null:
			piece.piece_type = bdata.piece_type
			piece.piece_tier = bdata.piece_tier
			piece.max_hp     = bdata.piece_hp
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
		var sz: Vector3 = entry.get("size", Vector3.ZERO) as Vector3
		_apply_place_local(entry["item_id"], entry["transform"], entry["net_id"], sz)
		# Restore HP state — find the piece we just placed and sync its health.
		var hp_current: float = entry.get("hp_current", -1.0) as float
		var hp_max:     float = entry.get("hp_max",     -1.0) as float
		if hp_current >= 0.0 and hp_max > 0.0 and hp_current < hp_max:
			var world: Node = get_tree().get_first_node_in_group("world")
			if world:
				var piece: Node3D = world.get_placed_piece(entry["net_id"] as int)
				if piece is DamageableBody:
					(piece as DamageableBody).sync_hp(hp_current, hp_max)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty(): return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _set_ghost_material(mat: StandardMaterial3D) -> void:
	_ghost.material_override = mat
	if _ghost_mesh_child:
		_apply_mat_recursive(_ghost_mesh_child, mat)

func _apply_mat_recursive(node: Node3D, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child: Node in node.get_children():
		if child is Node3D:
			_apply_mat_recursive(child as Node3D, mat)

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
