extends Node3D

const PLAYER_SCENE := preload("res://player/player.tscn")
const ITEM_SCENE   := preload("res://items/physical_item.tscn")

var _item_counter: int = 0

func _ready() -> void:
	add_to_group("world")

	# ── World generation (always seeded so multiplayer worlds match) ──────────
	var seed_val: int
	if NetworkManager.is_active():
		seed_val = NetworkManager.world_seed
	else:
		randomize()
		seed_val = randi()
	$WorldGenerator.generate(seed_val)

	# ── Multiplayer player spawning ───────────────────────────────────────────
	if not NetworkManager.is_active():
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

@rpc("authority", "reliable", "call_local")
func _do_spawn(id: int) -> void:
	if $Players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	$Players.add_child(player)
	player.global_position = Vector3(0, 1, 2)

@rpc("authority", "reliable", "call_local")
func _do_remove(id: int) -> void:
	var p := get_node_or_null("Players/" + str(id))
	if p:
		p.queue_free()

func _current_ids() -> Array:
	return $Players.get_children().map(func(c): return int(c.name))

# ── Item ID assignment ────────────────────────────────────────────────────────

func assign_item_id() -> int:
	_item_counter += 1
	var my_id := 1 if not NetworkManager.is_active() else multiplayer.get_unique_id()
	return my_id * 100000 + _item_counter

# ── Item sync RPCs ────────────────────────────────────────────────────────────

# Broadcast a shop-spawned item so all peers see it in the world.
func sync_item_spawn(item_id: String, world_pos: Vector3, net_id: int) -> void:
	if NetworkManager.is_active():
		_rpc_spawn_item.rpc(item_id, world_pos, net_id)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_item(item_id: String, world_pos: Vector3, net_id: int) -> void:
	var data := ItemRegistry.get_item(item_id)
	if not data:
		return
	var item := ITEM_SCENE.instantiate() as PhysicalItem
	item.item_data = data
	item.net_id    = net_id
	get_tree().current_scene.add_child(item)
	item.global_position = world_pos

# Broadcast that someone picked up an item — remove it from all other peers'
# worlds and spawn a visible copy on the carrying player's hands.
func sync_item_pickup(net_id: int, item_id: String, player_id: int) -> void:
	if NetworkManager.is_active():
		_rpc_pickup_item.rpc(net_id, item_id, player_id)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_pickup_item(net_id: int, item_id: String, player_id: int) -> void:
	# Remove the world copy.
	var world_item := _find_item(net_id)
	if world_item:
		world_item.queue_free()

	# Spawn a carried copy on the remote player's carry point.
	var player_node := get_node_or_null("Players/" + str(player_id))
	if not player_node:
		return
	var carry := player_node.get_node_or_null("Head/CarryPoint")
	if not carry:
		return
	var data := ItemRegistry.get_item(item_id)
	if not data:
		return
	var carried := ITEM_SCENE.instantiate() as PhysicalItem
	carried.item_data   = data
	carried.net_id      = net_id
	carry.add_child(carried)
	carried.freeze          = true
	carried.collision_layer = 0
	carried.collision_mask  = 0
	carried.position = Vector3(0, -0.3, -0.6)
	carried.rotation = Vector3(-0.3, 0.0, 0.1)

# Broadcast a drop — move the item back into the world on all other peers.
func sync_item_drop(item_id: String, world_pos: Vector3, net_id: int) -> void:
	if NetworkManager.is_active():
		_rpc_drop_item.rpc(item_id, world_pos, net_id)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_drop_item(item_id: String, world_pos: Vector3, net_id: int) -> void:
	# Try to find the carried copy and move it back to the world.
	var item := _find_item(net_id)
	if item:
		item.reparent(get_tree().current_scene, true)
		item.global_position = world_pos
		item.freeze          = false
		item.collision_layer = 1
		item.collision_mask  = 1
	else:
		# Fallback: carried copy not found, spawn fresh.
		var data := ItemRegistry.get_item(item_id)
		if not data:
			return
		var new_item := ITEM_SCENE.instantiate() as PhysicalItem
		new_item.item_data = data
		new_item.net_id    = net_id
		get_tree().current_scene.add_child(new_item)
		new_item.global_position = world_pos

# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_item(net_id: int) -> PhysicalItem:
	for node in get_tree().get_nodes_in_group("physical_items"):
		if (node as PhysicalItem).net_id == net_id:
			return node
	return null
