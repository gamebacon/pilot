extends Node3D
class_name Damageable

## Composite damage node — bundles HealthComponent + HitReaction into one child.
## Programmatic: add_child(Damageable.new(max_hp = 80.0, bar_height = 1.3))
## Scene: add Damageable node in the editor, configure max_hp/bar_height in Inspector.

@export var max_hp:     float = 100.0
@export var bar_height: float = 1.5

func _init(p_max_hp: float = 100.0, p_bar_height: float = 1.5) -> void:
	max_hp     = p_max_hp
	bar_height = p_bar_height

## Override to animate a different node's scale on hit (e.g. visual root vs physics body).
## Safe to set before or after add_child().
var scale_target: Node3D = null:
	set(v):
		scale_target = v
		if _hit_reaction:
			_hit_reaction.scale_target = v

signal died
signal hp_changed(current: float, maximum: float)

var _health:       HealthComponent = null
var _hit_reaction: HitReaction     = null

func _ready() -> void:
	_health       = HealthComponent.new()
	_hit_reaction = HitReaction.new()
	add_child(_health)
	add_child(_hit_reaction)

	_health.setup(max_hp)
	_hit_reaction.setup(bar_height)
	if scale_target:
		_hit_reaction.scale_target = scale_target

	_health.hp_changed.connect(_hit_reaction.on_hit)
	_health.hp_changed.connect(func(c: float, m: float) -> void: hp_changed.emit(c, m))
	_health.died.connect(func() -> void: died.emit())

func take_damage(amount: float) -> void:
	if _health:
		_health.take_damage(amount)

func is_dead() -> bool:
	return _health.is_dead() if _health else false

func get_ratio() -> float:
	return _health.get_ratio() if _health else 1.0

func get_current_hp() -> float:
	return _health.current_hp if _health else max_hp

func get_max_hp() -> float:
	return max_hp

## Update the visual bar without touching HP — used for remote multiplayer sync.
func show_hit(current: float, maximum: float) -> void:
	if _hit_reaction:
		_hit_reaction.on_hit(current, maximum)

## Restore both HP state and bar silently — used for late-join sync.
## Does NOT emit hp_changed or died; just sets the numbers and refreshes the bar.
func sync_hp(current: float, maximum: float) -> void:
	if _health:
		_health.set_hp_direct(current, maximum)
	if _hit_reaction:
		_hit_reaction.refresh_bar(current, maximum)
