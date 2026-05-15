extends Control

@onready var name_field:   LineEdit = $Panel/VBox/NameRow/NameField
@onready var lobby_field:  LineEdit = $Panel/VBox/JoinRow/IPField    # repurposed
@onready var status_label: Label    = $Panel/VBox/StatusLabel
@onready var host_btn:     Button   = $Panel/VBox/HostButton
@onready var join_btn:     Button   = $Panel/VBox/JoinRow/JoinButton
@onready var solo_btn:     Button   = $Panel/VBox/SoloButton

func _ready() -> void:
	NetworkManager.connected_ok.connect(_on_connected_ok)
	NetworkManager.connect_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_disconnected)
	NetworkManager.lobby_ready.connect(_on_lobby_ready)
	solo_btn.pressed.connect(_on_solo)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)

	lobby_field.placeholder_text = "Lobby ID"

	if not NetworkManager.steam_ready():
		host_btn.disabled = true
		join_btn.disabled = true
		_set_status("Steam is not running — solo only.")
	else:
		name_field.text = NetworkManager.local_name
		_set_status("")

	solo_btn.call_deferred("grab_focus")

func _on_solo() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_host() -> void:
	_apply_name()
	_set_status("Creating lobby…")
	_set_buttons(false)
	NetworkManager.host()

# Lobby is live — jump into the world immediately.
# The Lobby ID shown in the HUD lets friends copy-paste it to join,
# and the Steam overlay (Shift+Tab → Friends) lets you send direct invites.
func _on_lobby_ready(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_join() -> void:
	_apply_name()
	var id_str := lobby_field.text.strip_edges()
	if id_str.is_empty():
		_set_status("Paste a Lobby ID to join.")
		return
	var lobby_id := int(id_str)
	if lobby_id == 0:
		_set_status("Invalid Lobby ID.")
		return
	_set_status("Joining…")
	_set_buttons(false)
	NetworkManager.join_lobby(lobby_id)

func _on_connected_ok() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_connect_failed() -> void:
	_set_status("Connection failed.")
	_set_buttons(true)

func _on_disconnected() -> void:
	_set_status("Disconnected.")
	_set_buttons(true)

func _apply_name() -> void:
	var n := name_field.text.strip_edges()
	if not n.is_empty():
		NetworkManager.local_name = n

func _set_status(msg: String) -> void:
	status_label.text = msg

func _set_buttons(enabled: bool) -> void:
	solo_btn.disabled = not enabled
	host_btn.disabled = not enabled
	join_btn.disabled = not enabled
