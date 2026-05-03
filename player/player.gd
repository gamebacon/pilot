extends CharacterBody3D

const SPEED = 5.0
const SPRINT_SPEED = 9.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

var carry_capacity: int = 10
var carried_items: Array[Node] = []
var interact_target: Node = null  # updated every frame, read by PlayerHUD

const WALK_STEP_INTERVAL  = 0.45  # seconds between footsteps
const SPRINT_STEP_INTERVAL = 0.28
var _step_timer := 0.0


@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var carry_point: Node3D = $Head/CarryPoint
@onready var walk_audio: AudioStreamPlayer = $WalkAudioPlayer  # add this node


func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("drop"):
		drop_last()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	_update_interact_target()

func _update_interact_target() -> void:
	if interact_ray.is_colliding():
		var t := interact_ray.get_collider()
		if t == null:
			interact_target = null
			return
		interact_target = t if t.has_method("interact") else null
	else:
		interact_target = null

# Replace pick_up() ---
func pick_up(item: PhysicalItem) -> bool:
	if carried_items.size() >= carry_capacity:
		return false
	item.play_pickup_sound()          # <-- pickup sound on the item itself
	item.reparent(carry_point, false)
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	item.position = Vector3(0.25 * carried_items.size(), -0.3, -0.6)
	item.rotation = Vector3(-0.3, 0.0, 0.1)
	carried_items.append(item)
	return true

# Replace drop_last() ---
func drop_last() -> void:
	if carried_items.is_empty():
		return
	var item: PhysicalItem = carried_items.pop_back()
	item.reparent(get_tree().current_scene, true)
	item.collision_layer = 1
	item.collision_mask = 1
	item.freeze = false
	item.linear_velocity = -transform.basis.z * 3.0 + Vector3(0, 1, 0)

# Add to _physics_process(), after move_and_slide() ---
func _tick_footsteps(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if not is_on_floor() or not moving:
		_step_timer = 0.0
		return
	var interval := SPRINT_STEP_INTERVAL if Input.is_action_pressed("sprint") else WALK_STEP_INTERVAL
	_step_timer += delta
	if _step_timer >= interval:
		_step_timer = 0.0
		_play_footstep()

func _play_footstep() -> void:
	# Use the sound of the last carried item, or a generic footstep
	var stream: AudioStream
	if not carried_items.is_empty():
		stream = (carried_items.back() as PhysicalItem).get_walk_sound()
	else:
		stream = preload("res://audio/sfx/footstep_default.mp3")
	walk_audio.stream = stream
	walk_audio.pitch_scale = randf_range(0.9, 1.1)
	walk_audio.play()

# --- Interaction ---

func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target.has_method("interact"):
			target.interact(self)
