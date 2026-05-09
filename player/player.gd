extends CharacterBody3D
class_name Player

const SPEED          = 5.0
const SPRINT_SPEED   = 9.0
const JUMP_VELOCITY  = 4.5
const MOUSE_SENS     = 0.002
const MAX_CARRY_MASS = 30.0  # kg at which slowdown is maximal

const WALK_STEP_INTERVAL   = 0.45
const SPRINT_STEP_INTERVAL = 0.28
const GAMEPAD_LOOK_SENS    = 2.5
var _step_timer := 0.0

@onready var head:       Node3D   = $Head
@onready var camera:     Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var carry_point:  Node3D    = $Head/CarryPoint

var inventory: Inventory
var interact_target: Node = null

var walk_audio: AudioStreamPlayer

func _ready() -> void:
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)

	walk_audio = AudioStreamPlayer.new()
	walk_audio.bus = "Ambient"
	add_child(walk_audio)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")

func _unhandled_input(event: InputEvent) -> void:
	if GameState.ui_open:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

	if event.is_action_pressed("ui_cancel") and event is InputEventKey:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("drop"):
		drop_active()

	if event.is_action_pressed("inventory_next") and not interact_target:
		inventory.cycle_next()
		_reposition_carried()

	if event.is_action_pressed("debug_toggle"):
		GameState.debug_mode = !GameState.debug_mode

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if GameState.ui_open:
		velocity.x = move_toward(velocity.x, 0, SPRINT_SPEED)
		velocity.z = move_toward(velocity.z, 0, SPRINT_SPEED)
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var base_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED
	var speed := base_speed * _carry_weight_multiplier()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	_apply_gamepad_look(delta)
	move_and_slide()
	_tick_footsteps(delta)
	_update_interact_target()

func _apply_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() < 0.01:
		return
	rotate_y(-look.x * GAMEPAD_LOOK_SENS * delta)
	head.rotate_x(-look.y * GAMEPAD_LOOK_SENS * delta)
	head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

func _update_interact_target() -> void:
	if interact_ray.is_colliding():
		var t := interact_ray.get_collider()
		interact_target = t if t != null and t.has_method("interact") else null
	else:
		interact_target = null

func pick_up(item: PhysicalItem) -> bool:
	if inventory.is_full():
		return false
	item.play_pickup_sound()
	item.reparent(carry_point, false)
	item.freeze          = true
	item.collision_layer = 0
	item.collision_mask  = 0
	item.rotation = Vector3(-0.3, 0.0, 0.1)
	inventory.add(item)
	_reposition_carried()
	return true

func drop_active() -> void:
	var item := inventory.active()
	if not item:
		return
	inventory.remove(item)
	_reposition_carried()
	item.reparent(get_tree().current_scene, true)
	item.collision_layer = 1
	item.collision_mask  = 1
	item.freeze          = false
	item.linear_velocity = -transform.basis.z * 3.0 + Vector3(0, 1, 0)

# Positions all carried items so same-type items stack visually.
func _reposition_carried() -> void:
	for item in inventory.items:
		item.position = Vector3(0.25 * inventory.slot_for(item), -0.3, -0.6)
		item.rotation = Vector3(-0.3, 0.0, 0.1)

# Returns 1.0 when hands are empty, down to 0.45 at MAX_CARRY_MASS. Bypassed in debug mode.
func _carry_weight_multiplier() -> float:
	if GameState.debug_mode:
		return 1.0
	var total_mass := 0.0
	for item in inventory.items:
		if item.item_data:
			total_mass += item.item_data.mass
	return clamp(1.0 - total_mass / MAX_CARRY_MASS, 0.45, 1.0)

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
	var held := inventory.active()
	var stream: AudioStream = held.get_walk_sound() if held else preload("res://audio/sfx/footstep_default.mp3")
	walk_audio.stream      = stream
	walk_audio.pitch_scale = randf_range(0.9, 1.1)
	walk_audio.play()

func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target.has_method("interact"):
			target.interact(self)
