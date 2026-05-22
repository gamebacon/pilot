extends RigidBody3D
class_name PhysicalItem

@export var item_data: ItemData
var net_id: int = 0   # assigned when spawned in multiplayer

## Current durability for tool/weapon items. -1 means no durability (not a tool).
var current_durability: int = -1

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var label: Label3D = $Label3D
var audio: AudioStreamPlayer3D

# --- Default fallback sounds (set these in AudioManager or as preloads) ---
const DEFAULT_COLLIDE  = preload("res://audio/sfx/item_collide.mp3")
const DEFAULT_PICKUP   = preload("res://audio/sfx/item_pickup.mp3")
const DEFAULT_PLACE    = preload("res://audio/sfx/item_place.mp3")
const DEFAULT_WALK     = preload("res://audio/sfx/item_walk.mp3")

# Minimum velocity to trigger a collide sound (avoids spam on resting)
const COLLIDE_THRESHOLD := 1.5
var _collide_cooldown := 0.0

func _ready() -> void:
	add_to_group("physical_items")
	if item_data:
		_apply_item_data()
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

	audio = AudioStreamPlayer3D.new()
	audio.bus = "SFX"
	add_child(audio)

func _process(delta: float) -> void:
	if _collide_cooldown > 0.0:
		_collide_cooldown -= delta

func _apply_item_data() -> void:
	# Collision box — same for everything (bounding box is fine for dropped physics)
	var shape := BoxShape3D.new()
	shape.size = item_data.size
	collision_shape.shape = shape
	mass = item_data.mass

	if item_data is ToolItemData:
		# Custom multi-surface mesh: surface 0 = handle, surface 1 = head/blade
		var tool_mesh := MeshBuilder.tool(item_data as ToolItemData)
		if tool_mesh:
			mesh_instance.mesh            = tool_mesh
			mesh_instance.material_override = null   # let per-surface mats through
		else:
			_apply_box_mesh()
		current_durability = (item_data as ToolItemData).durability_max
	else:
		_apply_box_mesh()

func _apply_box_mesh() -> void:
	var box      := BoxMesh.new()
	box.size      = item_data.size
	mesh_instance.mesh = box

	var m                := StandardMaterial3D.new()
	m.albedo_color        = item_data.color
	if item_data.color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = m

# --- Sound helpers ---
func _resolve(item_sound: AudioStream, default: AudioStream) -> AudioStream:
	return item_sound if item_sound else default

func play_pickup_sound() -> void:
	_play(_resolve(item_data.sound_pickup if item_data else null, DEFAULT_PICKUP))

func play_place_sound() -> void:
	var pitch = randf_range(0.95, 1)
	AudioManager.play_sfx(_resolve(item_data.sound_place if item_data else null, DEFAULT_PLACE), pitch)

func get_walk_sound() -> AudioStream:
	return _resolve(item_data.sound_walk if item_data else null, DEFAULT_WALK)

func _play(stream: AudioStream) -> void:
	audio.stream = stream
	audio.pitch_scale = randf_range(0.92, 1.08)  # subtle variation
	audio.play()

# --- Collision sound (automatic) ---
func _on_body_entered(body: Node) -> void:
	if freeze or _collide_cooldown > 0.0:
		return
	# Only play if impact is strong enough
	var impact := linear_velocity.length()
	if impact < COLLIDE_THRESHOLD:
		return
	var stream := _resolve(item_data.sound_collide if item_data else null, DEFAULT_COLLIDE)
	audio.volume_db = linear_to_db(clamp(impact / 10.0, 0.1, 1.0))  # louder = harder hit
	_play(stream)
	_collide_cooldown = 0.3  # prevent rapid re-triggering

# --- Interaction ---
func interact(player: Node) -> void:
	player.pick_up(self)

func get_interact_hint(_player: Node) -> String:
	var n: String = item_data.display_name if item_data else "item"
	return "%s  Pick up  %s" % [InputHelper.action_label("interact"), n]

# ── Durability ─────────────────────────────────────────────────────────────────

## Consume one use of durability. Returns true when the tool is broken (0 or below).
func use_durability(amount: int = 1) -> bool:
	if current_durability < 0:
		return false
	current_durability -= amount
	return current_durability <= 0

## 0.0–1.0 fullness, or -1.0 if this item has no durability.
func durability_fraction() -> float:
	if current_durability < 0 or not (item_data is ToolItemData):
		return -1.0
	return float(current_durability) / float((item_data as ToolItemData).durability_max)
