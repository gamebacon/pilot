extends CharacterBody3D
class_name Player

const ITEM_SCENE := preload("res://items/physical_item.tscn")

const SPEED          = 5.0
const SPRINT_SPEED   = 9.0
const JUMP_VELOCITY  = 4.5
const MOUSE_SENS     = 0.002
const MAX_CARRY_MASS = 30.0

const WALK_STEP_INTERVAL   = 0.45
const SPRINT_STEP_INTERVAL = 0.28
const GAMEPAD_LOOK_SENS       = 2.5
const GAMEPAD_PRECISION_SCALE = 0.35

var _step_timer         := 0.0
var _sprinting          := false
var _just_recaptured    := false

@onready var head:         Node3D   = $Head
@onready var camera:       Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var carry_point:  Node3D    = $Head/CarryPoint

var inventory: Inventory

var interact_target: Node   = null
var _attack_cooldown := 0.0

var _held_visual: PhysicalItem = null   # single visual node for the equipped item
var _last_held_id: String      = ""     # item_id of the current visual

var walk_audio: AudioStreamPlayer

func _ready() -> void:
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.changed.connect(_update_held_visual)

	if NetworkManager.is_active() and not is_multiplayer_authority():
		_setup_as_remote()
		return

	# ── Debug starting items — remove when done testing ───────────────────────
	for _i in 5:
		inventory.add("wall_wood_proto")

	walk_audio = AudioStreamPlayer.new()
	walk_audio.bus = "Ambient"
	add_child(walk_audio)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	camera.make_current()

func _setup_as_remote() -> void:
	camera.current   = false
	interact_ray.enabled = false

	var mi  := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2; cap.height = 1.5
	mi.mesh     = cap
	mi.position = Vector3(0, 0.9, 0)
	add_child(mi)

	var lbl := Label3D.new()
	lbl.text      = NetworkManager.players.get(int(name), {}).get("name", "?")
	lbl.position  = Vector3(0, 2.0, 0)
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
			return

	if event.is_action_pressed("sprint"):
		_sprinting = not _sprinting

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("drop") and not GameState.is_building:
		drop_active()

	if event.is_action_pressed("inventory_next"):
		inventory.cycle_next()

	for slot in Inventory.HOTBAR_COLS:
		if event.is_action_pressed("hotbar_slot_%d" % (slot + 1)):
			inventory.set_active_hotbar_slot(slot)

	if event.is_action_pressed("hotbar_cycle_prev"):
		inventory.cycle_prev()
	elif event.is_action_pressed("hotbar_cycle_next"):
		inventory.cycle_next()
	elif event.is_action_pressed("hotbar_row_prev"):
		inventory.prev_hotbar_row()
	elif event.is_action_pressed("hotbar_row_next"):
		inventory.next_hotbar_row()

func _physics_process(delta: float) -> void:
	if NetworkManager.is_active() and not is_multiplayer_authority():
		return

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
	var speed     := (SPRINT_SPEED if _sprinting else SPEED) * _carry_weight_multiplier()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if not recaptured and Input.is_action_just_pressed("attack") and not GameState.is_building:
		_try_attack()

	_apply_gamepad_look(delta)
	move_and_slide()
	_tick_footsteps(delta)
	_update_interact_target()

	if NetworkManager.is_active():
		_sync_transform.rpc(global_position, rotation.y, head.rotation.x)

# ── Multiplayer sync ──────────────────────────────────────────────────────────

@rpc("any_peer", "unreliable_ordered")
func _sync_transform(pos: Vector3, rot_y: float, head_x: float) -> void:
	global_position = pos
	rotation.y      = rot_y
	head.rotation.x = head_x

@rpc("any_peer", "unreliable_ordered")
func _sync_held_item(item_id: String) -> void:
	set_held_visual(item_id)

# ── Held visual ───────────────────────────────────────────────────────────────

## Rebuild the single visual node at carry_point to match the active inventory slot.
## Connected to inventory.changed — called automatically on every slot change.
func _update_held_visual() -> void:
	var new_id: String = inventory.active_item_id()
	if new_id == _last_held_id:
		# Durability may have changed without swapping item type.
		if _held_visual and new_id != "":
			var d: int = inventory.active_durability()
			if _held_visual.current_durability != d:
				_held_visual.current_durability = d
		return
	_last_held_id = new_id
	if _held_visual:
		_held_visual.queue_free()
		_held_visual = null
	if not new_id.is_empty():
		var data := ItemRegistry.get_item(new_id)
		if data:
			_held_visual = ITEM_SCENE.instantiate() as PhysicalItem
			_held_visual.item_data          = data
			_held_visual.current_durability = inventory.active_durability()
			_held_visual.freeze             = true
			_held_visual.collision_layer    = 0
			_held_visual.collision_mask     = 0
			carry_point.add_child(_held_visual)
			_held_visual.position = Vector3(0.0, -0.3, -0.6)
			_held_visual.rotation = Vector3(-0.3, 0.0, 0.1)
			_held_visual.scale    = Vector3.ONE * _held_scale(data)

	# Sync to remote peers.
	if NetworkManager.is_active() and is_multiplayer_authority():
		_sync_held_item.rpc(new_id)

## Called by world.gd on remote player nodes to update their held visual.
func set_held_visual(item_id: String) -> void:
	if _held_visual:
		_held_visual.queue_free()
		_held_visual = null
	_last_held_id = item_id
	if item_id.is_empty(): return
	var data := ItemRegistry.get_item(item_id)
	if not data: return
	_held_visual = ITEM_SCENE.instantiate() as PhysicalItem
	_held_visual.item_data       = data
	_held_visual.freeze          = true
	_held_visual.collision_layer = 0
	_held_visual.collision_mask  = 0
	carry_point.add_child(_held_visual)
	_held_visual.position = Vector3(0.0, -0.3, -0.6)
	_held_visual.rotation = Vector3(-0.3, 0.0, 0.1)
	_held_visual.scale    = Vector3.ONE * _held_scale(data)

## Returns the held scale for a given ItemData.
func _held_scale(data: ItemData) -> float:
	if not data: return 1.0
	if data.held_scale > 0.0: return data.held_scale
	var s       := data.size
	var max_dim := maxf(s.x, maxf(s.y, s.z))
	return minf(1.0, 0.40 / max_dim)

# ── Pickup ────────────────────────────────────────────────────────────────────

func pick_up(item: PhysicalItem) -> bool:
	if inventory.is_full(): return false
	if NetworkManager.is_active() and item.net_id != 0:
		var world := get_tree().get_first_node_in_group("world")
		if world:
			world.request_pickup(item.net_id)
		return true
	# Solo / untracked crafted item — add data directly, free world node.
	var dur := item.current_durability
	inventory.add(item.item_data.id if item.item_data else "", item.net_id, dur)
	item.queue_free()
	return true

# ── Drop ──────────────────────────────────────────────────────────────────────

func drop_active() -> void:
	var drag: Inventory.ItemStack = inventory.remove_active_one()
	if drag.is_empty(): return
	_eject_data(drag.item_id, drag.net_ids[0] if not drag.net_ids.is_empty() else 0,
		drag.get_durability(), -transform.basis.z * 3.0 + Vector3(0, 1, 0))

## Called from UI drag-drop to drop a single item by data.
func drop_item_data(item_id: String, net_id: int, durability: int) -> void:
	_eject_data(item_id, net_id, durability, -transform.basis.z * 3.0 + Vector3(0, 2, 0))

func _eject_data(item_id: String, net_id: int, durability: int, throw_vel: Vector3) -> void:
	var drop_pos := global_position + throw_vel.normalized() * 0.8 + Vector3(0, 0.2, 0)
	if not NetworkManager.is_active():
		var data := ItemRegistry.get_item(item_id)
		if not data: return
		var item       := ITEM_SCENE.instantiate() as PhysicalItem
		item.item_data  = data
		item.net_id     = net_id
		item.current_durability = durability
		get_tree().current_scene.add_child(item)
		item.global_position = drop_pos
		item.freeze          = false
		item.collision_layer = 1
		item.collision_mask  = 1
		item.linear_velocity = throw_vel
		var world := get_tree().get_first_node_in_group("world")
		if world: world.register_item(item)
		return
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.request_drop(item_id, net_id, durability, drop_pos, throw_vel)

# ── Gamepad look ──────────────────────────────────────────────────────────────

func _apply_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() < 0.01: return
	var scale := GAMEPAD_PRECISION_SCALE if Input.is_action_pressed("precision_look") else 1.0
	rotate_y(-look.x * GAMEPAD_LOOK_SENS * scale * delta)
	head.rotate_x(-look.y * GAMEPAD_LOOK_SENS * scale * delta)
	head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

func _update_interact_target() -> void:
	if not is_instance_valid(interact_target):
		interact_target = null
	if interact_ray.is_colliding():
		var t := interact_ray.get_collider()
		if is_instance_valid(t) and (t.has_method("interact") or t.is_in_group("enemies")):
			interact_target = t
		else:
			interact_target = null
	else:
		interact_target = null

func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target and target.has_method("interact"):
			target.interact(self)

func _try_attack() -> void:
	if _attack_cooldown > 0.0: return
	_attack_cooldown = 0.55
	var target := interact_target
	if not is_instance_valid(target): return

	if target.is_in_group("enemies"):
		var dmg  := 25.0
		var slot: Inventory.ItemStack = inventory.active_slot_data()
		if not slot.is_empty():
			var data := slot.get_data()
			if data is ToolItemData:
				dmg = (data as ToolItemData).attack_damage
				if inventory.use_active_durability(1):
					inventory.remove_active_one()
		target.take_damage(dmg)
	elif target.is_in_group("harvestable"):
		target.interact(self)

func _carry_weight_multiplier() -> float:
	if GameState.debug_mode: return 1.0
	return clamp(1.0 - inventory.total_mass() / MAX_CARRY_MASS, 0.45, 1.0)

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
	var held_id := inventory.active_item_id()
	var stream: AudioStream
	if not held_id.is_empty():
		var data := ItemRegistry.get_item(held_id)
		if data and data.sound_walk:
			stream = data.sound_walk
	if not stream:
		stream = preload("res://audio/sfx/footstep_default.mp3")
	walk_audio.stream      = stream
	walk_audio.pitch_scale = randf_range(1, 1.4)
	walk_audio.play()
