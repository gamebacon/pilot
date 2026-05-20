extends Control

const UIStyle := preload("res://autoload/ui_style.gd")

@onready var panel:        PanelContainer = $Panel
@onready var title_label:  Label          = $Panel/VBox/Title
@onready var name_label:   Label          = $Panel/VBox/NameRow/NameLabel
@onready var name_field:   LineEdit       = $Panel/VBox/NameRow/NameField
@onready var lobby_field:  LineEdit       = $Panel/VBox/JoinRow/IPField
@onready var status_label: Label          = $Panel/VBox/StatusLabel
@onready var host_btn:     Button         = $Panel/VBox/HostButton
@onready var join_btn:     Button         = $Panel/VBox/JoinRow/JoinButton
@onready var solo_btn:     Button         = $Panel/VBox/SoloButton

# If the player hits Host/Join before Steam is ready we queue the action
# and fire it automatically the moment Steam connects.
enum _Pending { NONE, HOST, JOIN }
var _pending: _Pending = _Pending.NONE

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
	join_btn.pressed.connect(_on_join)

	lobby_field.placeholder_text = "Lobby ID"

	if NetworkManager.steam_ready():
		name_field.text = NetworkManager.local_name
	else:
		_set_status("Connecting to Steam...")

	solo_btn.call_deferred("grab_focus")

func _restore_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_steam_became_ready() -> void:
	name_field.text = NetworkManager.local_name
	status_label.text = ""
	# Fire any queued action the player already asked for.
	match _pending:
		_Pending.HOST: _do_host()
		_Pending.JOIN: _do_join()
	_pending = _Pending.NONE

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_solo() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_host() -> void:
	if not NetworkManager.steam_ready():
		_pending = _Pending.HOST
		return
	_do_host()

func _on_join() -> void:
	if not NetworkManager.steam_ready():
		_pending = _Pending.JOIN
		return
	_do_join()

func _do_host() -> void:
	_apply_name()
	_set_status("Creating lobby…")
	_set_buttons(false)
	NetworkManager.host()

func _do_join() -> void:
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

func _on_lobby_ready(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_connected_ok() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")

func _on_connect_failed() -> void:
	_set_status("Connection failed.")
	_set_buttons(true)

func _on_disconnected() -> void:
	_set_status("Disconnected.")
	_set_buttons(true)

# ── Helpers ───────────────────────────────────────────────────────────────────

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

# ── Styling ───────────────────────────────────────────────────────────────────

func _apply_style() -> void:
	var bg := ColorRect.new()
	bg.color = UIStyle.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	panel.add_theme_stylebox_override("panel", UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, 10, 20.0))

	UIStyle.apply_label(title_label,  UIStyle.SIZE_HEADING, UIStyle.ON_SURFACE, true)
	UIStyle.apply_label(name_label,   UIStyle.SIZE_BODY,    UIStyle.ON_SURFACE_DIM)
	UIStyle.apply_label(status_label, UIStyle.SIZE_SM,      UIStyle.ON_SURFACE_DIM)

	_style_field(name_field)
	_style_field(lobby_field)

	_style_button(solo_btn)
	_style_button(host_btn)
	_style_button(join_btn)

static func _style_field(field: LineEdit) -> void:
	field.add_theme_font_override("font", UIStyle.FONT)
	field.add_theme_font_size_override("font_size", UIStyle.SIZE_BODY)
	field.add_theme_color_override("font_color", UIStyle.ON_SURFACE)
	field.add_theme_color_override("font_placeholder_color", UIStyle.ON_SURFACE_DIM)

static func _style_button(btn: Button) -> void:
	btn.add_theme_font_override("font", UIStyle.FONT_BOLD)
	btn.add_theme_font_size_override("font_size", UIStyle.SIZE_BODY)
	btn.add_theme_color_override("font_color", UIStyle.ON_SURFACE)
	btn.add_theme_stylebox_override("focus", UIStyle.make_focus_style(UIStyle.PRIMARY))
