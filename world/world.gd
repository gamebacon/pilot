extends Node3D

const PLAYER_SCENE := preload("res://player/player.tscn")
const ITEM_SCENE   := preload("res://items/physical_item.tscn")

var _item_counter:      int = 0   # runtime items  (peer * 100_000 + n)
var _world_gen_counter: int = 0   # world-gen items (1 – 99_999)

# O(1) lookup for all world items (not in any inventory).
var _world_items: Dictionary = {}   # net_id -> PhysicalItem

# Single source of truth for all placed build pieces.
var _placed_pieces: Dictionary = {}  # net_id -> Node3D

func _ready() -> void:
	add_to_group("world")

	var seed_val: int
	if NetworkManager.is_active():
		seed_val = NetworkManager.world_seed
	else:
		randomize()
		seed_val = randi()
	$WorldGenerator.generate(seed_val)

	if not NetworkManager.is_active():
		var solo := get_node_or_null("Player")
		if solo:
			solo.global_position = _core_spawn_pos()
		return

	var solo := get_node_or_null("Player")
	if solo:
		solo.queue_free()

	if NetworkManager.is_server():
		NetworkManager.player_disconnected.connect(_on_disconnect)
		_do_spawn(multiplayer.get_unique_id())
	else:
		_request_players.rpc_id(1)

# ── Player spawning ───────────────────────────────────────────────────────────

func _on_disconnect(id: int) -> void:
	_do_remove.rpc(id)

@rpc("any_peer", "reliable")
func _request_players() -> void:
	if not NetworkManager.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for pid in _current_ids():
		_do_spawn.rpc_id(id, pid)
	_do_spawn.rpc(id)
	_rpc_receive_piece_snapshot.rpc_id(id, _build_piece_snapshot())

@rpc("authority", "reliable", "call_local")
func _do_spawn(id: int) -> void:
	if $Players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	$Players.add_child(player)
	player.global_position = _core_spawn_pos()

@rpc("authority", "reliable", "call_local")
func _do_remove(id: int) -> void:
	var p := get_node_or_null("Players/" + str(id))
	if p:
		p.queue_free()

func _current_ids() -> Array:
	return $Players.get_children().map(func(c): return int(c.name))

# ── Item ID assignment ────────────────────────────────────────────────────────

func assign_world_gen_id() -> int:
	_world_gen_counter += 1
	assert(_world_gen_counter < 100_000, "World-gen ID overflow")
	return _world_gen_counter

func assign_item_id() -> int:
	_item_counter += 1
	var my_id := 1 if not NetworkManager.is_active() else multiplayer.get_unique_id()
	return my_id * 100_000 + _item_counter

# ── World item registry ───────────────────────────────────────────────────────

func register_item(item: PhysicalItem) -> void:
	if item.net_id != 0:
		_world_items[item.net_id] = item

func _unregister(net_id: int) -> void:
	_world_items.erase(net_id)

func _find_item(net_id: int) -> PhysicalItem:
	var item := _world_items.get(net_id) as PhysicalItem
	if item and not is_instance_valid(item):
		_world_items.erase(net_id)
		return null
	return item

# ── Placed piece registry ─────────────────────────────────────────────────────

func register_piece(net_id: int, piece: Node3D) -> void:
	if net_id != 0:
		_placed_pieces[net_id] = piece

func unregister_piece(net_id: int) -> Node3D:
	var piece: Node3D = _placed_pieces.get(net_id) as Node3D
	_placed_pieces.erase(net_id)
	return piece if piece and is_instance_valid(piece) else null

func _build_piece_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for net_id: int in _placed_pieces:
		var piece: Node3D = _placed_pieces[net_id] as Node3D
		if not piece or not is_instance_valid(piece): continue
		result.append({
			"net_id":    net_id,
			"item_id":   piece.get_meta("item_id", ""),
			"transform": piece.global_transform,
		})
	return result

@rpc("authority", "reliable")
func _rpc_receive_piece_snapshot(snapshot: Array[Dictionary]) -> void:
	($BuildSystem as BuildSystem).apply_piece_snapshot(snapshot)

# ── Item spawn ────────────────────────────────────────────────────────────────

func request_spawn_item(item_id: String, world_pos: Vector3) -> void:
	if not NetworkManager.is_active():
		_spawn_local(item_id, world_pos, assign_item_id())
		return
	if multiplayer.is_server():
		_rpc_do_spawn_item.rpc(item_id, world_pos, assign_item_id())
	else:
		_rpc_request_spawn.rpc_id(1, item_id, world_pos)

@rpc("any_peer", "reliable")
func _rpc_request_spawn(item_id: String, world_pos: Vector3) -> void:
	if not multiplayer.is_server(): return
	_rpc_do_spawn_item.rpc(item_id, world_pos, assign_item_id())

@rpc("authority", "reliable", "call_local")
func _rpc_do_spawn_item(item_id: String, world_pos: Vector3, net_id: int,
		durability: int = -1, velocity: Vector3 = Vector3.ZERO) -> void:
	var item := _spawn_local(item_id, world_pos, net_id, durability)
	if item and velocity != Vector3.ZERO:
		item.linear_velocity = velocity

func _spawn_local(item_id: String, world_pos: Vector3, net_id: int,
		durability: int = -1) -> PhysicalItem:
	var data := ItemRegistry.get_item(item_id)
	if not data: return null
	var item       := ITEM_SCENE.instantiate() as PhysicalItem
	item.item_data  = data
	item.net_id     = net_id
	if durability >= 0:
		item.current_durability = durability
	get_tree().current_scene.add_child(item)
	item.global_position = world_pos
	register_item(item)
	return item

# ── Item pickup (server-authoritative) ───────────────────────────────────────

func request_pickup(net_id: int) -> void:
	if not NetworkManager.is_active(): return
	if multiplayer.is_server():
		_server_do_pickup(net_id, multiplayer.get_unique_id())
	else:
		_rpc_request_pickup.rpc_id(1, net_id)

@rpc("any_peer", "reliable")
func _rpc_request_pickup(net_id: int) -> void:
	if not multiplayer.is_server(): return
	_server_do_pickup(net_id, multiplayer.get_remote_sender_id())

func _server_do_pickup(net_id: int, sender_id: int) -> void:
	var item := _find_item(net_id)
	if not item: return                   # already claimed

	_unregister(net_id)                   # atomic lock — concurrent requests bounce above
	var item_id := item.item_data.id if item.item_data else ""
	var dur     := item.current_durability
	item.queue_free()
	_rpc_remove_world_item.rpc(net_id)    # remove on all clients

	# Confirm to the winner.
	if sender_id == multiplayer.get_unique_id():
		_confirm_pickup_local(net_id, item_id, dur)
	else:
		_rpc_confirm_pickup.rpc_id(sender_id, net_id, item_id, dur)

	# Notify all other peers so they update the winner's held visual.
	for pid: int in NetworkManager.players.keys():
		if pid == sender_id: continue
		if pid == multiplayer.get_unique_id():
			_notify_held(sender_id, item_id)
		else:
			_rpc_notify_held.rpc_id(pid, sender_id, item_id)

@rpc("authority", "reliable", "call_remote")
func _rpc_remove_world_item(net_id: int) -> void:
	var item := _find_item(net_id)
	if item:
		_unregister(net_id)
		item.queue_free()

@rpc("authority", "reliable")
func _rpc_confirm_pickup(net_id: int, item_id: String, durability: int) -> void:
	_confirm_pickup_local(net_id, item_id, durability)

func _confirm_pickup_local(net_id: int, item_id: String, durability: int) -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if not player: return
	var data := ItemRegistry.get_item(item_id)
	if not data: return
	var dur := durability if data is ToolItemData else -1
	player.inventory.add(item_id, net_id, dur)
	player._update_held_visual()
	AudioManager.play_sfx(data.sound_pickup if data.sound_pickup else
		preload("res://audio/sfx/item_pickup.mp3"))

func _notify_held(player_id: int, item_id: String) -> void:
	var p := get_node_or_null("Players/" + str(player_id)) as Player
	if p: p.set_held_visual(item_id)

@rpc("authority", "reliable")
func _rpc_notify_held(player_id: int, item_id: String) -> void:
	_notify_held(player_id, item_id)

# ── Item drop (server-authoritative) ─────────────────────────────────────────

func request_drop(item_id: String, existing_net_id: int, durability: int,
		world_pos: Vector3, velocity: Vector3) -> void:
	if not NetworkManager.is_active(): return
	if multiplayer.is_server():
		_server_do_drop(item_id, existing_net_id, durability, world_pos, velocity)
	else:
		_rpc_request_drop.rpc_id(1, item_id, existing_net_id, durability, world_pos, velocity)

@rpc("any_peer", "reliable")
func _rpc_request_drop(item_id: String, existing_net_id: int, durability: int,
		world_pos: Vector3, velocity: Vector3) -> void:
	if not multiplayer.is_server(): return
	_server_do_drop(item_id, existing_net_id, durability, world_pos, velocity)

func _server_do_drop(item_id: String, existing_net_id: int, durability: int,
		world_pos: Vector3, velocity: Vector3) -> void:
	var net_id := existing_net_id if existing_net_id != 0 else assign_item_id()
	_rpc_do_spawn_item.rpc(item_id, world_pos, net_id, durability, velocity)

# ── Container inventory sync ──────────────────────────────────────────────────

func sync_inventory_state(container_net_id: int, slots: Array) -> void:
	if NetworkManager.is_active():
		_rpc_sync_inventory.rpc(container_net_id, slots)

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_inventory(container_net_id: int, slots: Array) -> void:
	var inv := _find_synced_inventory(container_net_id)
	if inv:
		inv.apply_remote_state(slots)

# ── Chest slot ops (server-authoritative) ────────────────────────────────────

signal chest_take_denied

func request_chest_take(chest_net_id: int, slot_idx: int, qty: int) -> void:
	if not NetworkManager.is_active(): return
	if multiplayer.is_server():
		_server_do_chest_take(chest_net_id, slot_idx, qty, multiplayer.get_unique_id())
	else:
		_rpc_request_chest_take.rpc_id(1, chest_net_id, slot_idx, qty)

@rpc("any_peer", "reliable")
func _rpc_request_chest_take(chest_net_id: int, slot_idx: int, qty: int) -> void:
	if not multiplayer.is_server(): return
	_server_do_chest_take(chest_net_id, slot_idx, qty, multiplayer.get_remote_sender_id())

func _server_do_chest_take(chest_net_id: int, slot_idx: int, qty: int, sender_id: int) -> void:
	var inv := _find_synced_inventory(chest_net_id)
	if not inv: return
	if inv.get_slot(slot_idx).is_empty():
		if sender_id == multiplayer.get_unique_id():
			chest_take_denied.emit()
		else:
			_rpc_chest_take_denied.rpc_id(sender_id)
		return
	inv.take_items(slot_idx, qty)   # changed → _on_net_changed → sync broadcast

@rpc("authority", "reliable")
func _rpc_chest_take_denied() -> void:
	chest_take_denied.emit()

func request_chest_place(chest_net_id: int, slot_idx: int, item_id: String,
		qty: int, net_ids: Array, durability: int) -> void:
	if not NetworkManager.is_active(): return
	if multiplayer.is_server():
		_server_do_chest_place(chest_net_id, slot_idx, item_id, qty, net_ids, durability)
	else:
		_rpc_request_chest_place.rpc_id(1, chest_net_id, slot_idx, item_id, qty, net_ids, durability)

@rpc("any_peer", "reliable")
func _rpc_request_chest_place(chest_net_id: int, slot_idx: int, item_id: String,
		qty: int, net_ids: Array, durability: int) -> void:
	if not multiplayer.is_server(): return
	_server_do_chest_place(chest_net_id, slot_idx, item_id, qty, net_ids, durability)

func _server_do_chest_place(chest_net_id: int, slot_idx: int, item_id: String,
		qty: int, net_ids: Array, durability: int) -> void:
	var inv := _find_synced_inventory(chest_net_id)
	if not inv: return
	var d := Inventory.ItemStack.new()
	d.item_id = item_id; d.quantity = qty; d.net_ids = net_ids.duplicate()
	if durability >= 0: d.set_durability(durability)
	inv.place_items(slot_idx, d)    # changed → _on_net_changed → sync broadcast

# ── Helpers ───────────────────────────────────────────────────────────────────

func _core_spawn_pos() -> Vector3:
	var wgen := $WorldGenerator
	var base: Vector3 = wgen.core_position if wgen else Vector3.ZERO
	return base + Vector3(4.0, 1.5, 0.0)

func _find_synced_inventory(cnet_id: int) -> Inventory:
	for node in get_tree().get_nodes_in_group("synced_inventory"):
		if (node as Inventory).container_net_id == cnet_id:
			return node
	return null
