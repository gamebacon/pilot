extends Control

@onready var name_field:   LineEdit = $Panel/VBox/NameRow/NameField
@onready var ip_field:     LineEdit = $Panel/VBox/JoinRow/IPField
@onready var status_label: Label    = $Panel/VBox/StatusLabel
@onready var host_btn:     Button   = $Panel/VBox/HostButton
@onready var join_btn:     Button   = $Panel/VBox/JoinRow/JoinButton
@onready var solo_btn:     Button   = $Panel/VBox/SoloButton

func _ready() -> void:
	NetworkManager.connected_ok.connect(_on_connected_ok)
	NetworkManager.connect_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_disconnected)
	solo_btn.pressed.connect(_on_solo)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	# Start unfocused so keyboard navigation works after Enter
	solo_btn.call_deferred("grab_focus")

func _on_solo() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_host() -> void:
	_apply_name()
	var err := NetworkManager.host()
	if err != OK:
		_set_status("Failed to start server (error %d)" % err)
		return
	var ip := _local_ip()
	_set_status("Hosting — LAN IP: %s   Port: %d\nShare this with friends on your network." % [ip, NetworkManager.DEFAULT_PORT])
	_set_buttons(false)
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_join() -> void:
	_apply_name()
	var ip := ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var err := NetworkManager.join(ip)
	if err != OK:
		_set_status("Join error %d" % err)
		return
	_set_status("Connecting to %s…" % ip)
	_set_buttons(false)

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
	NetworkManager.local_name = n if not n.is_empty() else "Player"

func _set_status(msg: String) -> void:
	status_label.text = msg

func _set_buttons(enabled: bool) -> void:
	solo_btn.disabled  = not enabled
	host_btn.disabled  = not enabled
	join_btn.disabled  = not enabled

func _local_ip() -> String:
	for addr in IP.get_local_addresses():
		if not addr.begins_with("127.") and "." in addr and not addr.begins_with("169.254."):
			return addr
	return "127.0.0.1"
