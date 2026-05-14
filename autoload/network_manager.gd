extends Node

const DEFAULT_PORT := 7777
const MAX_CLIENTS  := 7

signal player_connected(id: int)
signal player_disconnected(id: int)
signal connected_ok()
signal connect_failed()
signal server_disconnected()

# id -> {name: String}
var players: Dictionary = {}
var local_name  := "Player"
var world_seed  := 0  # server picks, broadcast to all clients before world loads

func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_signals()
	world_seed = randi()  # generate once; all clients will receive this
	players[1] = {name = local_name}
	return OK

func join(ip: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_signals()
	return OK

func close() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	world_seed = 0

func is_active() -> bool:
	return multiplayer.has_multiplayer_peer()

func is_server() -> bool:
	return is_active() and multiplayer.is_server()

# ── Internal ──────────────────────────────────────────────────────────────────

func _bind_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	# Don't emit connected_ok yet — wait for the server's welcome (which carries the seed).
	var my_id := multiplayer.get_unique_id()
	players[my_id] = {name = local_name}
	_hello.rpc_id(1, local_name)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connect_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	world_seed = 0
	server_disconnected.emit()

# ── Handshake ─────────────────────────────────────────────────────────────────

# Client → server: "here is my name"
@rpc("any_peer", "reliable")
func _hello(name_str: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {name = name_str}
	_announce.rpc(id, name_str)      # tell everyone about this player
	_welcome.rpc_id(id, world_seed)  # send the world seed back to the new client

# Server → new client: world seed delivered, safe to load the world now
@rpc("authority", "reliable")
func _welcome(seed: int) -> void:
	world_seed = seed
	connected_ok.emit()

# Server → all: someone's name was registered (call_local so server also updates its dict)
@rpc("authority", "reliable", "call_local")
func _announce(id: int, name_str: String) -> void:
	players[id] = {name = name_str}
