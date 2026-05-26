extends CharacterBody3D

const GRAVITY := 9.8

## Set by wave_spawner before add_child so _ready() can read it.
var enemy_type: EnemyType = null

var damageable: Damageable = null
var _core:      Node3D     = null
var _attack_timer:   float        = 0.0
var _footstep_timer: float        = 0.0
var _ambient_timer:  float        = 0.0

var _snd_footstep: AudioStreamPlayer3D = null
var _snd_attack:   AudioStreamPlayer3D = null
var _snd_hurt:     AudioStreamPlayer3D = null
var _snd_death:    AudioStreamPlayer3D = null
var _snd_ambient:  AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("enemies")

	if not enemy_type:
		enemy_type = EnemyType._grunt()

	var bar_y: float = enemy_type.capsule_height * 0.5 + enemy_type.capsule_radius + 0.35
	damageable = Damageable.new(enemy_type.max_hp, bar_y)
	add_child(damageable)
	damageable.died.connect(_die)

	_build_sounds()

# ── Sounds ────────────────────────────────────────────────────────────────────

func _build_sounds() -> void:
	_snd_footstep = _make_sfx_player(8.0)
	_snd_attack   = _make_sfx_player(20.0)
	_snd_hurt     = _make_sfx_player(18.0)
	_snd_death    = _make_sfx_player(25.0)
	_snd_ambient  = _make_sfx_player(20.0)
	_load_sound(_snd_footstep, enemy_type.snd_footstep)
	_load_sound(_snd_attack,   enemy_type.snd_attack)
	_load_sound(_snd_hurt,     enemy_type.snd_hurt)
	_load_sound(_snd_death,    enemy_type.snd_death)
	_load_sound(_snd_ambient,  enemy_type.snd_ambient)

func _make_sfx_player(max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance       = max_dist
	p.attenuation_model  = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size          = 5.0
	p.bus                = "SFX"
	add_child(p)
	return p

func _load_sound(player: AudioStreamPlayer3D, path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	player.stream = load(path)

# ── Combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if damageable.is_dead(): return
	damageable.take_damage(amount)
	if not damageable.is_dead() and _snd_hurt.stream:
		_snd_hurt.pitch_scale = randf_range(1.3, 1.6)
		_snd_hurt.play()

func _die() -> void:
	set_physics_process(false)
	_snd_footstep.stop()
	_snd_ambient.stop()
	_snd_attack.stop()
	_snd_hurt.stop()
	if _snd_death.stream:
		_snd_death.pitch_scale = randf_range(0.85, 1.15)
		_snd_death.play()
		await _snd_death.finished
	queue_free()

# ── Movement & AI ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _core:
		_core = get_tree().get_first_node_in_group("core")
		if not _core:
			return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var to_core := _core.global_position - global_position
	to_core.y   = 0.0
	var dist    := to_core.length()
	var moving  := false

	if dist > enemy_type.capsule_radius + 1.5:
		var dir := to_core.normalized()
		velocity.x = dir.x * enemy_type.speed
		velocity.z = dir.z * enemy_type.speed
		moving = true
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = enemy_type.attack_cooldown
			if multiplayer.is_server():
				_core.take_damage(enemy_type.damage)
			_play_attack()

	move_and_slide()
	_tick_footstep(delta, moving)
	_tick_ambient(delta)

# ── Audio ticks ───────────────────────────────────────────────────────────────

func _tick_footstep(delta: float, moving: bool) -> void:
	return # annoyting
	if not moving or not _snd_footstep.stream:
		return
	var interval := 0.45 / (enemy_type.speed / 3.5)  # faster enemy = faster steps
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer           = interval
		_snd_footstep.pitch_scale = randf_range(0.8, 1.2)
		_snd_footstep.play()

func _tick_ambient(delta: float) -> void:
	if not _snd_ambient.stream or _snd_ambient.playing:
		return
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		_ambient_timer            = randf_range(4.0, 9.0)
		_snd_ambient.pitch_scale  = randf_range(0.9, 1.1)
		_snd_ambient.play()

func _play_attack() -> void:
	return # annoyting

	if not _snd_attack.stream:
		return
	_snd_attack.pitch_scale = randf_range(0.85, 1.15)
	_snd_attack.play()
