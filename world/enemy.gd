extends CharacterBody3D

const GRAVITY := 9.8

## Set by wave_spawner before add_child so _ready() can read it.
var enemy_type: EnemyType = null

var hp: float            = 60.0
var _core: Node3D        = null
var _attack_timer: float = 0.0
var _footstep_timer: float = 0.0
var _ambient_timer: float  = 0.0
var _dead: bool           = false

var _hp_bar: MeshInstance3D          = null
var _snd_footstep: AudioStreamPlayer3D = null
var _snd_attack:   AudioStreamPlayer3D = null
var _snd_hurt:     AudioStreamPlayer3D = null
var _snd_death:    AudioStreamPlayer3D = null
var _snd_ambient:  AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("enemies")

	if not enemy_type:
		enemy_type = EnemyType._grunt()

	hp = enemy_type.max_hp

	# Place healthbar above capsule top: top = height/2 + radius
	var bar_y := enemy_type.capsule_height * 0.5 + enemy_type.capsule_radius + 0.35
	_build_health_bar(bar_y)
	_build_sounds()

# ── Health bar ────────────────────────────────────────────────────────────────

func _build_health_bar(y: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, y, 0.0)
	add_child(root)

	var bg      := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.1, 0.16)
	bg.mesh      = bg_mesh
	var bg_mat  := StandardMaterial3D.new()
	bg_mat.albedo_color   = Color(0.08, 0.08, 0.08, 0.85)
	bg_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	bg_mat.no_depth_test  = true
	bg.set_surface_override_material(0, bg_mat)
	root.add_child(bg)

	_hp_bar      = MeshInstance3D.new()
	var hp_mesh := QuadMesh.new()
	hp_mesh.size = Vector2(1.04, 0.11)
	_hp_bar.mesh = hp_mesh
	var hp_mat  := StandardMaterial3D.new()
	hp_mat.albedo_color   = Color(0.15, 0.9, 0.1)
	hp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	hp_mat.no_depth_test  = true
	_hp_bar.set_surface_override_material(0, hp_mat)
	root.add_child(_hp_bar)

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
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	_update_bar()
	if hp <= 0.0:
		_die()
	elif _snd_hurt.stream:
		_snd_hurt.pitch_scale = randf_range(1.3, 1.6)
		_snd_hurt.play()

func _update_bar() -> void:
	if not _hp_bar:
		return
	var ratio := hp / enemy_type.max_hp
	_hp_bar.scale.x = ratio
	var mat := _hp_bar.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0 - ratio, ratio * 0.88, 0.06)

func _die() -> void:
	if _dead:
		return
	_dead = true
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
	if not _snd_attack.stream:
		return
	_snd_attack.pitch_scale = randf_range(0.85, 1.15)
	_snd_attack.play()
