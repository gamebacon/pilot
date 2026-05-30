extends CharacterBody3D

# ── Constants ─────────────────────────────────────────────────────────────────

const GRAVITY: float = 9.8

const TARGET_REFRESH_INTERVAL: float = 0.5

const ATTACK_RANGE_PADDING: float = 1.7
const ATTACK_EXIT_MULT: float = 1.3

const BLOCKER_DETECT_RANGE: float = 12.0
const STALL_BLOCKER_THRESHOLD: float = 1.5

const NAV_REPATH_INTERVAL: float = 0.5
const STATE_LOCK_TIME: float = 0.35

const PHYSICAL_STALL_SPEED_RATIO: float = 0.15

# ── State ─────────────────────────────────────────────────────────────────────

enum State {
	IDLE,
	MOVING,
	ATTACKING,
	DEAD
}

# ── Config ────────────────────────────────────────────────────────────────────

var enemy_type: EnemyType = null

# ── Nodes ─────────────────────────────────────────────────────────────────────

var damageable: Damageable
var _nav_agent: NavigationAgent3D

var _snd_footstep: AudioStreamPlayer3D
var _snd_attack: AudioStreamPlayer3D
var _snd_hurt: AudioStreamPlayer3D
var _snd_death: AudioStreamPlayer3D
var _snd_ambient: AudioStreamPlayer3D

# ── Runtime ───────────────────────────────────────────────────────────────────

var _state: State = State.IDLE

# actual attack target
var _current_target: Node3D = null

# preferred target (player/core)
var _desired_target: Node3D = null

var _last_target_distance := INF
var _no_progress_timer := 0.0

var _target_refresh_timer := 0.0
var _state_lock_timer := 0.0
var _attack_timer := 0.0
var _footstep_timer := 0.0
var _ambient_timer := 0.0
var _repath_timer := 0.0

var _stall_duration := 0.0
var _intended_to_move := false

var _debug_label: Label3D

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("enemies")

	if enemy_type == null:
		enemy_type = EnemyType._grunt()

	var bar_y := (
		enemy_type.capsule_height * 0.5
		+ enemy_type.capsule_radius
		+ 0.35
	)

	damageable = Damageable.new(enemy_type.max_hp, bar_y)
	add_child(damageable)

	damageable.died.connect(_die)

	_nav_agent = NavigationAgent3D.new()
	add_child(_nav_agent)

	await get_tree().physics_frame

	_nav_agent.path_desired_distance = 1.0
	# Drive the agent to well inside attack range so floating-point and
	# navmesh approximation errors don't leave the enemy one step short.
	_nav_agent.target_desired_distance = enemy_type.capsule_radius + 0.5

	_nav_agent.avoidance_enabled = false

	_state = State.MOVING

	_build_sounds()
	_build_debug_label()

# ── Physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if NetworkManager.is_active() and not multiplayer.is_server():
		return

	_state_lock_timer = maxf(_state_lock_timer - delta, 0.0)
	_repath_timer = maxf(_repath_timer - delta, 0.0)

	_intended_to_move = false

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	match _state:
		State.MOVING:
			_process_movement(delta)

		State.ATTACKING:
			_process_attack(delta)

	move_and_slide()

	# ── Physical stall detection ────────────────────────────────────────────

	if _intended_to_move:
		var horiz_speed := Vector2(
			velocity.x,
			velocity.z
		).length()

		if horiz_speed < enemy_type.speed * PHYSICAL_STALL_SPEED_RATIO:
			_stall_duration += delta
		else:
			_stall_duration = max(_stall_duration - delta, 0.0)

	_tick_ambient(delta)

# ── Movement ──────────────────────────────────────────────────────────────────

func _process_movement(delta: float) -> void:
	_target_refresh_timer -= delta

	if _target_refresh_timer <= 0.0:
		_target_refresh_timer = TARGET_REFRESH_INTERVAL
		_update_target()

	if _current_target == null or not is_instance_valid(_current_target):
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dist := global_position.distance_to(
		_current_target.global_position
	)

	# ── Progress tracking (always measured against the desired goal) ────────
	# Using _desired_target keeps _stall_duration elevated while the real
	# goal (player/core) is unreachable, even when _current_target has been
	# redirected to a blocker.  Without this, successfully approaching a
	# blocker resets the stall counter and the enemy flip-flops every cycle.

	var desired_dist := global_position.distance_to(
		_desired_target.global_position
	)

	if desired_dist < _last_target_distance - 0.05:
		_no_progress_timer = 0.0
		_stall_duration = 0.0
	else:
		_no_progress_timer += delta

	_last_target_distance = desired_dist

	if _no_progress_timer > 1.0:
		_stall_duration += delta

	# ── Attack check ────────────────────────────────────────────────────────

	var attack_range := (
		enemy_type.capsule_radius
		+ ATTACK_RANGE_PADDING
	)

	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0

		_attack_timer = 0.0

		_set_state(State.ATTACKING)
		return

	# ── Repath when stalled ────────────────────────────────────────────────

	if _nav_is_stalled():
		if _repath_timer <= 0.0:
			_repath_timer = NAV_REPATH_INTERVAL

			if _desired_target:
				_nav_agent.target_position = (
					_desired_target.global_position
				)

	# ── Navigation movement ────────────────────────────────────────────────

	var next_pos := _nav_agent.get_next_path_position()

	if global_position.distance_to(next_pos) < 0.7:
		return

	var dir := (
		next_pos - global_position
	).normalized()

	var steer := dir * enemy_type.speed

	velocity.x = steer.x
	velocity.z = steer.z

	_intended_to_move = true

	_tick_footstep(delta)

# ── Targeting ────────────────────────────────────────────────────────────────

func _update_target() -> void:
	var desired: Node3D = null

	# ── Priority 1: nearby player ───────────────────────────────────────────

	desired = _find_nearest_player(12.0)

	# ── Priority 2: core ───────────────────────────────────────────────────

	if desired == null:
		desired = get_tree().get_first_node_in_group("core") as Node3D

	if desired == null:
		_current_target = null
		_desired_target = null
		return

	_desired_target = desired

	_nav_agent.target_position = desired.global_position

	# Blocker detection is purely stall-based: async nav path queries are not
	# reliable within the same physics frame as setting target_position.
	var blocked: bool = _stall_duration >= STALL_BLOCKER_THRESHOLD

	# ── Attack blockers if route blocked ───────────────────────────────────

	if blocked:
		var blocker := _find_nearest_blocker(
			BLOCKER_DETECT_RANGE
		)

		if blocker != null:
			_current_target = blocker

			_nav_agent.target_position = (
				blocker.global_position
			)

			return

	# ── Normal pursuit ─────────────────────────────────────────────────────

	_current_target = desired

	_nav_agent.target_position = (
		desired.global_position
	)

# ── Blocker Selection ─────────────────────────────────────────────────────────

func _find_nearest_blocker(radius: float) -> Node3D:
	var best: Node3D = null
	var best_score := -INF

	for node in get_tree().get_nodes_in_group("enemy_blockers"):
		if not is_instance_valid(node):
			continue

		var body := node as Node3D

		if body == null:
			continue

		# ignore structures far above/below us

		var height_diff :float= abs(
			body.global_position.y
			- global_position.y
		)

		if height_diff > 3.5:
			continue

		var dist := global_position.distance_to(
			body.global_position
		)

		if dist > radius:
			continue

		var priority := 0

		if body.has_meta("blocker_priority"):
			priority = int(
				body.get_meta("blocker_priority")
			)

		# higher priority strongly preferred
		# slightly prefers nearby structures

		var score := float(priority) * 100.0 - dist

		if score > best_score:
			best_score = score
			best = body

	return best

# ── Player Search ─────────────────────────────────────────────────────────────

func _find_nearest_player(radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist := radius

	for node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(node):
			continue

		var body := node as Node3D

		if body == null:
			continue

		var dist := global_position.distance_to(
			body.global_position
		)

		if dist < best_dist:
			best_dist = dist
			best = body

	return best

# ── State ─────────────────────────────────────────────────────────────────────

func _set_state(s: State) -> void:
	if _state == s:
		return

	if _state_lock_timer > 0.0 and s != State.DEAD:
		return

	_state = s
	_state_lock_timer = STATE_LOCK_TIME

# ── Navigation ────────────────────────────────────────────────────────────────

func _nav_is_stalled() -> bool:
	if _desired_target == null:
		return true

	if _nav_agent.target_position == Vector3.ZERO:
		return true

	if _nav_agent.is_target_reached():
		return false

	var next_pos := _nav_agent.get_next_path_position()

	# nav path collapsed / invalid

	if next_pos.distance_to(global_position) < 0.05:
		var dist_to_target := global_position.distance_to(
			_desired_target.global_position
		)

		if dist_to_target > 2.0:
			return true

	return false

# ── Attack ────────────────────────────────────────────────────────────────────

func _process_attack(delta: float) -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		_set_state(State.MOVING)
		return

	velocity.x = 0.0
	velocity.z = 0.0

	var dist := global_position.distance_to(
		_current_target.global_position
	)

	var attack_range := (
		enemy_type.capsule_radius
		+ ATTACK_RANGE_PADDING
	)

	if dist > attack_range * ATTACK_EXIT_MULT:
		_set_state(State.MOVING)
		return

	_attack_timer -= delta

	if _attack_timer <= 0.0:
		_attack_timer = enemy_type.attack_cooldown
		_try_attack()

func _try_attack() -> void:
	if _current_target and _current_target.has_method("take_damage"):
		_current_target.take_damage(
			enemy_type.damage
		)

		_play_attack()

# ── Damage / Death ────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if damageable.is_dead():
		return

	damageable.take_damage(amount)

	if _snd_hurt and _snd_hurt.stream:
		_snd_hurt.play()

func _die() -> void:
	_set_state(State.DEAD)

	set_physics_process(false)

	queue_free()

# ── Audio / Debug ─────────────────────────────────────────────────────────────

func _build_sounds() -> void:
	pass

func _build_debug_label() -> void:
	pass

func _tick_footstep(_delta: float) -> void:
	pass

func _tick_ambient(_delta: float) -> void:
	pass

func _play_attack() -> void:
	pass

func _process(_delta: float) -> void:
	pass
