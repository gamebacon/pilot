extends CharacterBody3D

const SPEED = 5.0
const SPRINT_SPEED = 9.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

var carry_capacity: int = 2
var carried_items: Array[Node] = []
var interact_target: Node = null  # updated every frame, read by PlayerHUD

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var carry_point: Node3D = $Head/CarryPoint

func _ready() -> void:
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
		interact_target = t if t.has_method("interact") else null
	else:
		interact_target = null

# --- Carry system ---

func pick_up(item: Node) -> bool:
	if carried_items.size() >= carry_capacity:
		return false
	item.reparent(carry_point, false)
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	# Stack items slightly offset so multiple are visible
	item.position = Vector3(0.25 * carried_items.size(), -0.3, -0.6)
	item.rotation = Vector3(-0.3, 0.0, 0.1)
	carried_items.append(item)
	return true

func drop_last() -> void:
	if carried_items.is_empty():
		return
	var item: Node = carried_items.pop_back()
	item.reparent(get_tree().current_scene, true)
	item.collision_layer = 1
	item.collision_mask = 1
	item.freeze = false
	item.linear_velocity = -transform.basis.z * 3.0 + Vector3(0, 1, 0)

# --- Interaction ---

func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target.has_method("interact"):
			target.interact(self)
