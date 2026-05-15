extends Node

const APP_ID     := 480  # Replace with your real Steam App ID before shipping
const MAX_CLIENTS := 7

signal player_connected(id: int)
signal player_disconnected(id: int)
signal connected_ok()
signal connect_failed()
signal server_disconnected()
signal lobby_ready(lobby_id: int)

# id -> {name: String}
var players:    Dictionary = {}
var local_name: String     = "Player"
var world_seed: int        = 0

var _lobby_id: int  = 0
var _steam_ok: bool = false

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))

	var init := Steam.steamInit()
	if not init:
		push_warning("Steam unavailable — is Steam running? Multiplayer disabled.")
		return

	_steam_ok  = true
	local_name = Steam.getFriendPersonaName(Steam.getSteamID())

	# SteamMultiplayerPeer requires the relay network to be available.
	# Calling this at startup gives it time to warm up before the user hosts.
	Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)

func _process(_delta: float) -> void:
	if _steam_ok:
		Steam.run_callbacks()

# ── Public API ────────────────────────────────────────────────────────────────

func host() -> void:
	assert(_steam_ok, "Steam is not running")
	world_seed = randi()
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_CLIENTS)

func join_lobby(lobby_id: int) -> void:
	assert(_steam_ok, "Steam is not running")
	Steam.joinLobby(lobby_id)

func close() -> void:
	if _lobby_id != 0:
		Steam.leaveLobby(_lobby_id)
		_lobby_id = 0
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	world_seed = 0

func is_active() -> bool:
	return multiplayer.has_multiplayer_peer()

func is_server() -> bool:
	return is_active() and multiplayer.is_server()

func steam_ready() -> bool:
	return _steam_ok

func current_lobby() -> int:
	return _lobby_id

# ── Steam lobby callbacks ─────────────────────────────────────────────────────

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		push_error("Lobby creation failed: %d" % result)
		connect_failed.emit()
		return
	_lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "world_seed", str(world_seed))
	Steam.setLobbyJoinable(lobby_id, true)

	var peer := SteamMultiplayerPeer.new()
	var err  := peer.create_host(MAX_CLIENTS)
	if err != OK:
		push_error("SteamMultiplayerPeer.create_host failed: %d" % err)
		connect_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	_bind_signals()
	players[1] = {name = local_name}
	lobby_ready.emit(lobby_id)

func _on_lobby_joined(lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	print("[NET] lobby_joined fired — lobby: %d  response: %d" % [lobby_id, response])
	if response != 1:
		push_error("Join lobby failed: response %d" % response)
		connect_failed.emit()
		return
	# Steam fires lobby_joined for the host too — ignore it, we're already set up.
	if Steam.getSteamID() == Steam.getLobbyOwner(lobby_id):
		print("[NET] We are the host, ignoring lobby_joined.")
		return
	_lobby_id = lobby_id
	var seed_s := Steam.getLobbyData(lobby_id, "world_seed")
	if not seed_s.is_empty():
		world_seed = int(seed_s)

	var host_id := Steam.getLobbyOwner(lobby_id)
	print("[NET] Connecting to host Steam ID: %d" % host_id)
	var peer    := SteamMultiplayerPeer.new()
	var err     := peer.create_client(host_id)
	print("[NET] create_client returned: %d" % err)
	if err != OK:
		push_error("SteamMultiplayerPeer.create_client failed: %d" % err)
		connect_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	_bind_signals()
	print("[NET] Peer assigned, waiting for connected_to_server...")
	_watch_connection(peer)

# Polls the peer connection status every second for up to 10s, then times out.
func _watch_connection(peer: SteamMultiplayerPeer) -> void:
	for i in range(10):
		await get_tree().create_timer(1.0).timeout
		if not multiplayer.has_multiplayer_peer():
			return  # already disconnected
		var status := peer.get_connection_status()
		print("[NET] connection status after %ds: %d" % [i + 1, status])
		# STATUS_CONNECTED = 2
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return
	# Still not connected after 10s — give up
	print("[NET] connection timed out")
	multiplayer.multiplayer_peer = null
	connect_failed.emit()

# Fired when the user accepts a Steam invite or clicks "Join Game" on a friend.
func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_lobby(lobby_id)

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
	print("[NET] peer_connected: %d" % id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer_disconnected: %d" % id)
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("[NET] connected_to_server fired — we are peer %d" % multiplayer.get_unique_id())
	var my_id := multiplayer.get_unique_id()
	players[my_id] = {name = local_name}
	_hello.rpc_id(1, local_name)

func _on_connection_failed() -> void:
	print("[NET] connection_failed fired")
	multiplayer.multiplayer_peer = null
	connect_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	world_seed = 0
	server_disconnected.emit()

# ── Handshake ─────────────────────────────────────────────────────────────────
# world_seed comes from Steam lobby metadata — _welcome just signals "you're in".

# Client → server: register name
@rpc("any_peer", "reliable")
func _hello(name_str: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {name = name_str}
	_announce.rpc(id, name_str)
	_welcome.rpc_id(id)

# Server → new client: you are registered, load the world
@rpc("authority", "reliable")
func _welcome() -> void:
	connected_ok.emit()

# Server → all: someone joined (call_local so host updates its dict too)
@rpc("authority", "reliable", "call_local")
func _announce(id: int, name_str: String) -> void:
	players[id] = {name = name_str}
