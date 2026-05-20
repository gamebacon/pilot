extends CharacterBody3D
class_name Player

const SPEED          = 5.0
const SPRINT_SPEED   = 9.0
const JUMP_VELOCITY  = 4.5
const MOUSE_SENS     = 0.002
const MAX_CARRY_MASS = 30.0  # kg at which slowdown is maximal

const WALK_STEP_INTERVAL   = 0.45
const SPRINT_STEP_INTERVAL = 0.28
const GAMEPAD_LOOK_SENS       = 2.5
const GAMEPAD_PRECISION_SCALE = 0.35

var _step_timer         := 0.0
var _sprinting          := false
var _just_recaptured    := false   # suppress attack on the same click that recaptures the mouse

@onready var head:       Node3D   = $Head
@onready var camera:     Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var carry_point:  Node3D    = $Head/CarryPoint

var inventory: Inventory
var interact_target: Node = null
var _attack_cooldown := 0.0


var walk_audio: AudioStreamPlayer

func _ready() -> void:
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.changed.connect(func() -> void: _reposition_carried())

	if NetworkManager.is_active() and not is_multiplayer_authority():
		_setup_as_remote()
		return

	walk_audio = AudioStreamPlayer.new()
	walk_audio.bus = "Ambient"
	add_child(walk_audio)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	camera.make_current()

func _setup_as_remote() -> void:
	camera.current = false
	interact_ray.enabled = false

	# Simple body mesh so remote players are visible.
	var mi   := MeshInstance3D.new()
	var cap  := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.5
	mi.mesh     = cap
	mi.position = Vector3(0, 0.9, 0)
	add_child(mi)

	# Name label above head.
	var lbl := Label3D.new()
	lbl.text     = NetworkManager.players.get(int(name), {}).get("name", "?")
	lbl.position = Vector3(0, 2.0, 0)
	lbl.font_size = 28
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
	if NetworkManager.is_active() and not is_multiplayer_authority():
		return

	if event.is_action_pressed("debug_toggle"):
		GameState.debug_mode = !GameState.debug_mode
		get_viewport().set_input_as_handled()
		return

	# Toggle inventory before the ui_open guard so it works both ways.
	if event.is_action_pressed("open_inventory"):
		var inv_hud := get_tree().get_first_node_in_group("inventory_hud")
		if inv_hud:
			inv_hud.toggle()
		get_viewport().set_input_as_handled()
		return

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
			_just_recaptured = true
			return   # don't also attack on the recapture click

	if event.is_action_pressed("sprint"):
		_sprinting = not _sprinting

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("drop") and not GameState.is_building:
		drop_active()

	if event.is_action_pressed("inventory_next") and not interact_target:
		inventory.cycle_next()
		_reposition_carried()

	for slot in Inventory.HOTBAR_COLS:
		if event.is_action_pressed("hotbar_slot_%d" % (slot + 1)):
			inventory.set_active_hotbar_slot(slot)
			_reposition_carried()

	if not GameState.is_building and not interact_target:
		if event.is_action_pressed("hotbar_cycle_prev"):
			inventory.cycle_prev(); _reposition_carried()
		elif event.is_action_pressed("hotbar_cycle_next"):
			inventory.cycle_next(); _reposition_carried()
		elif event.is_action_pressed("hotbar_row_prev"):
			inventory.prev_hotbar_row(); _reposition_carried()
		elif event.is_action_pressed("hotbar_row_next"):
			inventory.next_hotbar_row(); _reposition_carried()

func _physics_process(delta: float) -> void:
	if NetworkManager.is_active() and not is_multiplayer_authority():
		return  # remote player: position is written by _sync_transform RPC

	# Consume the recapture flag — must be first so it covers the whole frame.
	var recaptured := _just_recaptured
	_just_recaptured = false

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
	var base_speed := SPRINT_SPEED if _sprinting else SPEED
	var speed := base_speed * _carry_weight_multiplier()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Attack — suppressed while in build/place mode.
	if not recaptured and Input.is_action_just_pressed("attack") and not GameState.is_building:
		_try_attack()

	_apply_gamepad_look(delta)
	move_and_slide()
	_tick_footsteps(delta)
	_update_interact_target()

	if NetworkManager.is_active():
		_sync_transform.rpc(global_position, rotation.y, head.rotation.x)

# ── Multiplayer position sync ─────────────────────────────────────────────────

@rpc("any_peer", "unreliable_ordered")
func _sync_transform(pos: Vector3, rot_y: float, head_x: float) -> void:
	global_position  = pos
	rotation.y       = rot_y
	head.rotation.x  = head_x

# ── Gamepad look ─────────────────────────────────────────────────────────────

func _apply_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() < 0.01:
		return
	var scale := GAMEPAD_PRECISION_SCALE if Input.is_action_pressed("precision_look") else 1.0
	rotate_y(-look.x * GAMEPAD_LOOK_SENS * scale * delta)
	head.rotate_x(-look.y * GAMEPAD_LOOK_SENS * scale * delta)
	head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

func _update_interact_target() -> void:
	# Proactively clear any stale reference from a node freed last frame.
	if not is_instance_valid(interact_target):
		interact_target = null
	if interact_ray.is_colliding():
		var t := interact_ray.get_collider()
		# Accept anything interactable OR any enemy (enemies don't need interact()).
		if is_instance_valid(t) and (t.has_method("interact") or t.is_in_group("enemies")):
			interact_target = t
		else:
			interact_target = null
	else:
		interact_target = null

func pick_up(item: PhysicalItem) -> bool:
	if inventory.is_full():
		return false
	item.play_pickup_sound()

	if NetworkManager.is_active() and item.net_id != 0 and item.item_data:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			world.sync_item_pickup(item.net_id, item.item_data.id, multiplayer.get_unique_id())

	item.reparent(carry_point, false)
	item.freeze          = true
	item.collision_layer = 0
	item.collision_mask  = 0
	item.rotation = Vector3(-0.3, 0.0, 0.1)
	item.scale    = Vector3.ONE * _held_scale(item)
	inventory.add(item)
	_reposition_carried()
	return true

func drop_active() -> void:
	var item := inventory.remove_active_one()
	if not item:
		return
	item.visible         = true
	item.reparent(get_tree().current_scene, true)
	item.scale           = Vector3.ONE
	item.collision_layer = 1
	item.collision_mask  = 1
	item.freeze          = false
	item.linear_velocity = -transform.basis.z * 3.0 + Vector3(0, 1, 0)

	if NetworkManager.is_active() and item.item_data:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			if item.net_id == 0:
				item.net_id = world.assign_item_id()
			world.sync_item_drop(item.item_data.id, item.global_position, item.net_id)

## Drop a specific [item] into the world in front of the player with multiplayer sync.
## Safe to call from inventory UI — does not touch inventory slot data.
func drop_item(item: PhysicalItem) -> void:
	if not is_instance_valid(item):
		return
	item.visible         = true
	item.reparent(get_tree().current_scene, true)
	item.scale           = Vector3.ONE
	item.collision_layer = 1
	item.collision_mask  = 1
	item.freeze          = false
	item.linear_velocity = -transform.basis.z * 3.0 + Vector3(0, 2, 0)

	if NetworkManager.is_active() and item.item_data:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			if item.net_id == 0:
				item.net_id = world.assign_item_id()
			world.sync_item_drop(item.item_data.id, item.global_position, item.net_id)

# Show only the active slot's first item; hide everything else.
func _reposition_carried() -> void:
	var active_idx := Inventory.MAIN_SLOTS \
		+ inventory.active_hotbar_row * Inventory.HOTBAR_COLS + inventory.active_slot
	for i in Inventory.TOTAL_SLOTS:
		var slot: Inventory.Slot = inventory.get_slot(i)
		for j in slot.physical.size():
			var item: PhysicalItem = slot.physical[j]
			if i == active_idx and j == 0:
				item.visible  = true
				item.position = Vector3(0.0, -0.3, -0.6)
				item.rotation = Vector3(-0.3, 0.0, 0.1)
				item.scale    = Vector3.ONE * _held_scale(item)
			else:
				item.visible   = false
				item.position  = Vector3(0.0, -0.3, -0.6)  # keep stacked items at carry_point so drop position is correct

## Returns the uniform scale to use while an item is carried.
## Normalises the largest dimension to 0.40 m so nothing blocks the view,
## but never scales items UP (cap at 1.0).
func _held_scale(item: PhysicalItem) -> float:
	if not item.item_data:
		return 1.0
	if item.item_data.held_scale > 0.0:
		return item.item_data.held_scale
	var s    := item.item_data.size
	var max_dim := maxf(s.x, maxf(s.y, s.z))
	return minf(1.0, 0.40 / max_dim)

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
	var interval := SPRINT_STEP_INTERVAL if _sprinting else WALK_STEP_INTERVAL
	_step_timer += delta
	if _step_timer >= interval:
		_step_timer = 0.0
		_play_footstep()

func _play_footstep() -> void:
	var held := inventory.active()
	var stream: AudioStream = held.get_walk_sound() if held else preload("res://audio/sfx/footstep_default.mp3")
	walk_audio.stream      = stream
	walk_audio.pitch_scale = randf_range(1, 1.4)
	walk_audio.play()

func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target.has_method("interact"):
			target.interact(self)

func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.55
	var target := interact_target
	if not is_instance_valid(target):
		return
	if target.is_in_group("enemies"):
		var dmg := 25.0
		var active := inventory.active()
		if active and active.item_data is ToolItemData:
			dmg = (active.item_data as ToolItemData).attack_damage
			if active.use_durability(1):
				inventory.remove(active)
				active.queue_free()
				_reposition_carried()
		target.take_damage(dmg)
	elif target.is_in_group("harvestable"):
		target.interact(self)
