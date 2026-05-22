extends Node

const SNAP_DIST := 0.3
const ROT_STEP  := 90.0
const MAX_REACH := 15.0

var _active      := false
var _snapping    := false
var _place_held  := false

var _planks_root: Node3D
var _placed_root: Node3D

# Data-only: what the active slot currently holds (no node reference).
var _held_id:     String = ""
var _held_data:   ItemData = null
var _held_size:   Vector3 = Vector3.ONE
var _held_net_id: int     = 0

var player: Player = null
@onready var _ghost: MeshInstance3D = $Ghost

var _mat_free:    StandardMaterial3D
var _mat_snap:    StandardMaterial3D
var _mat_blocked: StandardMaterial3D

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_planks_root      = Node3D.new()
	_planks_root.name = "PlacedPlanks"
	add_child(_planks_root)

	_placed_root      = Node3D.new()
	_placed_root.name = "PlacedItems"
	add_child(_placed_root)

	_mat_snap    = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))
	_mat_blocked = _ghost_mat(Color(0.90, 0.20, 0.20, 0.55))
	_mat_free    = _ghost_mat(Color(1.0, 1.0, 1.0, 0.50))

	_ghost.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _mat_free
	_ghost.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event.is_action_pressed("rotate") and not event.is_echo():
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

	if not _active: return

	# Sync held data with the player's active slot.
	var slot := player.inventory.active_slot_data()
	var cur_id := slot.item_id if slot else ""
	if cur_id != _held_id:
		if cur_id.is_empty():
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
	var cam  := player.camera
	var from := cam.global_position
	var dir  := -cam.global_transform.basis.z
	var to   := from + dir * MAX_REACH

	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_ghost.hide(); return
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
	if _held_data is PlaceableItemData: return []
	var result := []
	for local_pos: Vector3 in PlacedPlank.sockets_for(_held_size):
		result.append(_ghost.global_transform * local_pos)
	return result

# ── Placement ────────────────────────────────────────────────────────────────

func _place() -> void:
	if not _ghost.visible or _is_blocked() or _held_id.is_empty(): return

	var net_id  := _assign_net_id()
	var world_t := _ghost.global_transform

	_apply_place_local(_held_id, world_t, net_id)

	if player.inventory.active_slot_data():
		# play sound via the held visual if it exists, else silent
		if player._held_visual:
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

	var drag: Inventory.DragStack = player.inventory.remove_active_one()
	if not drag.is_empty() and NetworkManager.is_active() and _held_net_id != 0:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			# Notify other peers that this net_id left all inventories.
			# (No world copy existed; just ensure remote HUDs refresh cleanly.)
			pass

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
	var cam  := player.camera
	var from := cam.global_position
	var dir  := -cam.global_transform.basis.z
	var to   := from + dir * MAX_REACH

	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty(): return

	var collider: Object = hit["collider"]
	var plank: PlacedPlank = null
	if collider is PlacedPlank:
		plank = collider
	elif collider != null and collider.get_parent() is PlacedPlank:
		plank = collider.get_parent()
	if not plank: return

	var net_id := plank.net_id
	plank.queue_free()

	if NetworkManager.is_active() and net_id != 0:
		if NetworkManager.is_server():
			_sync_remove.rpc(net_id)
		else:
			_request_remove.rpc_id(1, net_id)

# ── Held item management ─────────────────────────────────────────────────────

func _hold_from_slot(slot: Inventory.Slot) -> void:
	_held_id     = slot.item_id
	_held_data   = slot.get_data()
	_held_size   = _held_data.size if _held_data else Vector3.ONE
	_held_net_id = slot.active_net_id()

func _refresh_ghost_for_held() -> void:
	var box := BoxMesh.new()
	box.size = _held_size
	_ghost.mesh = box
	var c := _held_data.color if _held_data else Color(1, 1, 1)
	_mat_free = _ghost_mat(Color(c.r, c.g, c.b, 0.5))
	_ghost.material_override = _mat_free

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	if not player or GameState.is_building: return
	var slot := player.inventory.active_slot_data()
	if slot == null or slot.is_empty(): return
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
	if not data: return
	if data is PlaceableItemData:
		var scene := (data as PlaceableItemData).get_placement_scene()
		if scene:
			var node := scene.instantiate()
			node.set("net_id", net_id)
			_placed_root.add_child(node)
			node.set_deferred("global_transform", world_transform)
	else:
		var piece := PlacedPlank.build(data.size, data.color)
		piece.net_id = net_id
		_planks_root.add_child(piece)
		piece.set_deferred("global_transform", world_transform)

@rpc("any_peer", "reliable")
func _request_remove(net_id: int) -> void:
	if not NetworkManager.is_server(): return
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

# ── Helpers ───────────────────────────────────────────────────────────────────

func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty(): return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
