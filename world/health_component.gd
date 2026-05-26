extends Node
class_name HealthComponent

## Reusable HP node. Add as a child of any entity that can take damage.
## Call setup() in the parent's _ready(), then connect hp_changed / died as needed.

signal hp_changed(current_hp: float, max_hp: float)
signal died

var max_hp:     float = 100.0
var current_hp: float = 100.0
var _is_dead:   bool  = false

func setup(p_max_hp: float) -> void:
	max_hp     = p_max_hp
	current_hp = p_max_hp
	_is_dead   = false

func take_damage(amount: float) -> void:
	if _is_dead: return
	current_hp = maxf(0.0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0.0:
		_is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if _is_dead: return
	current_hp = minf(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)

func get_ratio() -> float:
	if max_hp <= 0.0: return 1.0
	return current_hp / max_hp

func is_dead() -> bool:
	return _is_dead

## Set HP directly without emitting any signals — used for network late-join sync.
func set_hp_direct(p_current: float, p_max: float) -> void:
	max_hp     = p_max
	current_hp = clampf(p_current, 0.0, p_max)
	_is_dead   = current_hp <= 0.0
