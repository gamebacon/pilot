extends Node

const ENEMY_SCRIPT := preload("res://world/enemy.gd")

var core_position := Vector3.ZERO

var _wave_num    := 0
var _spawn_timer := 0.0
var _was_night   := false

func _ready() -> void:
	add_to_group("wave_spawner")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	var dnc := get_tree().get_first_node_in_group("day_night")
	if not dnc:
		return

	var tod: float     = dnc.time_of_day
	var is_night: bool = tod > 0.75 or tod < 0.25

	# Night begins → start a new wave
	if is_night and not _was_night:
		_wave_num   += 1
		_spawn_timer = 1.5   # short pause before first spawn each night
		print("Night %d begins — max alive: %d  interval: %.1fs" % [_wave_num, _max_alive(), _interval()])

	# Dawn → wave survived
	if not is_night and _was_night and _wave_num > 0:
		print("Dawn — wave %d survived" % _wave_num)

	_was_night = is_night

	if not is_night:
		return

	# Maintain pressure: only spawn when under the alive cap
	if _alive_count() >= _max_alive():
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	_spawn_timer = _interval()
	var type  := _pick_type()
	var angle := randf() * TAU
	var r     := randf_range(18.0, 30.0)
	var pos   := core_position + Vector3(cos(angle) * r, 5.0, sin(angle) * r)
	if NetworkManager.is_active():
		_rpc_spawn.rpc(pos, type.id)
	else:
		_rpc_spawn(pos, type.id)

# ── Scaling ───────────────────────────────────────────────────────────────────

## Maximum enemies alive at once — grows each wave so pressure always escalates.
func _max_alive() -> int:
	return 3 + (_wave_num - 1) * 2

## Seconds between spawns — converges toward 1.2 s by wave 5+.
func _interval() -> float:
	return maxf(1.2, 4.5 - _wave_num * 0.5)

func _alive_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _pick_type() -> EnemyType:
	# Wave 1: grunts only.  Wave 2+: add brutes.  Wave 3+: add fast runners.
	var r := randf()
	if _wave_num >= 3 and r < 0.12:
		return EnemyType.by_id("runner")
	if _wave_num >= 2 and r < 0.35:
		return EnemyType.by_id("brute")
	return EnemyType.by_id("grunt")

# ── Spawn ─────────────────────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_local")
func _rpc_spawn(pos: Vector3, type_id: String) -> void:
	var type := EnemyType.by_id(type_id)

	var body := CharacterBody3D.new()
	body.set_script(ENEMY_SCRIPT)
	body.enemy_type = type

	var col   := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = type.capsule_radius
	shape.height = type.capsule_height
	col.shape    = shape
	body.add_child(col)

	var mi   := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = type.capsule_radius
	mesh.height = type.capsule_height
	mi.mesh     = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = type.body_color
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)

	get_tree().current_scene.add_child(body)
	body.global_position = pos
