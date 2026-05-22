extends Control

const UIStyle := preload("res://autoload/ui_style.gd")

const _FRIENDS_POLL_INTERVAL: float = 6.0
const _LOBBY_ID_MIN_LENGTH:   int   = 17

@onready var panel:               PanelContainer = $CenterContainer/Panel
@onready var title_label:         Label          = $CenterContainer/Panel/VBox/Title
@onready var status_label:        Label          = $CenterContainer/Panel/VBox/StatusLabel
@onready var host_btn:            Button         = $CenterContainer/Panel/VBox/HostButton
@onready var solo_btn:            Button         = $CenterContainer/Panel/VBox/SoloButton
@onready var lobby_field:         LineEdit       = $CenterContainer/Panel/VBox/LobbyField
@onready var _friends_sep:        HSeparator     = $CenterContainer/Panel/VBox/HSep3
@onready var _friends_header_lbl: Label          = $CenterContainer/Panel/VBox/FriendsHeaderLabel
@onready var _friends_list:       VBoxContainer  = $CenterContainer/Panel/VBox/FriendsList

var _pending_host: bool = false

# steam_id -> TextureRect for in-flight avatar requests.
var _pending_avatars: Dictionary = {}
var _friends_poll_timer: float = 0.0

func _ready() -> void:
	_apply_style()
	call_deferred(&"_restore_cursor")

	NetworkManager.connected_ok.connect(_on_connected_ok)
	NetworkManager.connect_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_disconnected)
	NetworkManager.lobby_ready.connect(_on_lobby_ready)
	NetworkManager.steam_became_ready.connect(_on_steam_became_ready)
	solo_btn.pressed.connect(_on_solo)
	host_btn.pressed.connect(_on_host)
	lobby_field.text_changed.connect(_on_lobby_field_changed)

	if NetworkManager.steam_ready():
		_on_steam_became_ready()
	else:
		_set_status("Connecting to Steam…")
		_refresh_friends()

	solo_btn.call_deferred("grab_focus")

func _restore_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not NetworkManager.steam_ready():
		return
	_friends_poll_timer += delta
	if _friends_poll_timer >= _FRIENDS_POLL_INTERVAL:
		_friends_poll_timer = 0.0
		_refresh_friends()

func _on_steam_became_ready() -> void:
	status_label.text = ""
	_connect_avatar_signal()
	_refresh_friends()
	if _pending_host:
		_pending_host = false
		_do_host()

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_solo() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_host() -> void:
	if not NetworkManager.steam_ready():
		_pending_host = true
		return
	_do_host()

func _on_lobby_field_changed(text: String) -> void:
	var id_str := text.strip_edges()
	if id_str.length() < _LOBBY_ID_MIN_LENGTH:
		return
	if not NetworkManager.steam_ready():
		_set_status("Steam not ready.")
		return
	var lobby_id := int(id_str)
	if lobby_id == 0:
		return
	_set_status("Joining…")
	_set_buttons(false)
	NetworkManager.join_lobby(lobby_id)

func _do_host() -> void:
	_set_status("Creating lobby…")
	_set_buttons(false)
	NetworkManager.host()

func _on_lobby_ready(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_connected_ok() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_connect_failed() -> void:
	_set_status("Connection failed.")
	_set_buttons(true)
	lobby_field.clear()

func _on_disconnected() -> void:
	_set_status("Disconnected.")
	_set_buttons(true)

# ── Friends panel ─────────────────────────────────────────────────────────────

func _refresh_friends() -> void:
	_pending_avatars.clear()
	for child: Node in _friends_list.get_children():
		child.queue_free()

	var has_friends: bool = false
	if NetworkManager.steam_ready():
		var count: int = Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE)
		for i: int in range(count):
			var friend_id: int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
			var game_info: Dictionary = Steam.getFriendGamePlayed(friend_id)
			if game_info.is_empty():
				continue
			var lobby_id: int = int(game_info.get("lobby", 0))
			if lobby_id == 0:
				continue
			var app_id: int = int(game_info.get("id", game_info.get("app_id", 0)))
			if app_id != NetworkManager.APP_ID:
				continue
			_add_friend_row(Steam.getFriendPersonaName(friend_id), friend_id, lobby_id)
			has_friends = true

	_friends_sep.visible        = has_friends
	_friends_header_lbl.visible = has_friends
	_friends_list.visible       = has_friends

func _add_friend_row(friend_name: String, friend_id: int, lobby_id: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(28, 28)
	avatar.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(avatar)
	_pending_avatars[friend_id] = avatar
	Steam.getPlayerAvatar(Steam.AVATAR_SMALL, friend_id)

	var lbl: Label = UIStyle.make_label(friend_name, UIStyle.SIZE_BODY, UIStyle.ON_SURFACE, false)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)

	var btn: Button = UIStyle.make_button("Join")
	btn.pressed.connect(func() -> void: _join_friend(lobby_id))
	row.add_child(btn)

	_friends_list.add_child(row)

func _join_friend(lobby_id: int) -> void:
	_set_status("Joining…")
	_set_buttons(false)
	NetworkManager.join_lobby(lobby_id)

func _connect_avatar_signal() -> void:
	if not Steam.avatar_loaded.is_connected(_on_avatar_loaded):
		Steam.avatar_loaded.connect(_on_avatar_loaded)

func _on_avatar_loaded(steam_id: int, width: int, data: PackedByteArray) -> void:
	if not _pending_avatars.has(steam_id):
		return
	var img: Image = Image.create_from_data(width, width, false, Image.FORMAT_RGBA8, data)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var rect: TextureRect = _pending_avatars[steam_id]
	if is_instance_valid(rect):
		rect.texture = tex
	_pending_avatars.erase(steam_id)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_status(msg: String) -> void:
	status_label.text = msg

func _set_buttons(enabled: bool) -> void:
	solo_btn.disabled  = not enabled
	host_btn.disabled  = not enabled
	lobby_field.editable = enabled

# ── Styling ───────────────────────────────────────────────────────────────────

func _apply_style() -> void:
	var bg := ColorRect.new()
	bg.color = UIStyle.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	panel.add_theme_stylebox_override("panel", UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 10, 20.0))

	UIStyle.apply_label(title_label,         UIStyle.SIZE_HEADING, UIStyle.ON_SURFACE,     true)
	UIStyle.apply_label(status_label,        UIStyle.SIZE_SM,      UIStyle.ON_SURFACE_DIM)
	UIStyle.apply_label(_friends_header_lbl, UIStyle.SIZE_SM,      UIStyle.ON_SURFACE_DIM, true)

	UIStyle.apply_line_edit(lobby_field)

	for btn: Button in [solo_btn, host_btn]:
		btn.add_theme_font_override("font", UIStyle.FONT_BOLD)
		btn.add_theme_font_size_override("font_size", UIStyle.SIZE_BODY)
		btn.add_theme_color_override("font_color", UIStyle.ON_SURFACE)
		btn.add_theme_stylebox_override("focus", UIStyle.make_focus_style(UIStyle.PRIMARY))
