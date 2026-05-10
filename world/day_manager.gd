extends Node
class_name DayManager

const SHIFT_DURATION := 480.0  # 8 minutes real time
const PAY_PER_SLOT   := 40     # SEK per blueprint slot filled

# Blueprint assigned to each day — loops when days exceed list length
const DAILY_BLUEPRINTS := [
	"blueprint_woodshed",
	"blueprint_sauna",
	"blueprint_house",
]

signal timer_updated(seconds_remaining: float)

var _time_remaining := 0.0
var _ended          := false
var _plot: Plot     = null

func _ready() -> void:
	add_to_group("day_manager")
	call_deferred("_connect_plot")

func _process(delta: float) -> void:
	if not GameState.shift_active:
		return
	_time_remaining = max(0.0, _time_remaining - delta)
	timer_updated.emit(_time_remaining)
	if _time_remaining <= 0.0 and not _ended:
		_ended = true
		_end_shift()

# ── Daily blueprint ───────────────────────────────────────────────────────────

func get_target_blueprint_id() -> String:
	var idx := (GameState.day - 1) % DAILY_BLUEPRINTS.size()
	return DAILY_BLUEPRINTS[idx]

func get_target_blueprint_name() -> String:
	var item := ItemRegistry.get_item(get_target_blueprint_id())
	return item.display_name if item else "Blueprint"

# ── Shift control ─────────────────────────────────────────────────────────────

func start_shift() -> void:
	if GameState.shift_active:
		return
	_time_remaining    = SHIFT_DURATION
	_ended             = false
	GameState.shift_active = true

func end_day() -> void:
	if GameState.shift_active:
		_end_shift()
	GameState.day          += 1
	GameState.shift_active  = false
	GameState.shift_done    = false
	_ended                  = false
	_time_remaining         = 0.0

func _end_shift() -> void:
	GameState.shift_active = false
	GameState.shift_done   = true
	var pay := _calculate_pay()
	GameState.add_currency(pay)
	GameState.shift_ended.emit(pay)

func _calculate_pay() -> int:
	if not _plot:
		return 0
	var filled := 0
	for instance in _plot.blueprint_instances:
		filled += instance.filled.size()
	return filled * PAY_PER_SLOT

# ── Build completion ──────────────────────────────────────────────────────────

func _connect_plot() -> void:
	_plot = get_tree().get_first_node_in_group("plot") as Plot
	if _plot:
		_plot.blueprint_added.connect(_on_blueprint_added)

func _on_blueprint_added(instance: BlueprintInstance) -> void:
	instance.build_completed.connect(_on_build_completed)

func _on_build_completed() -> void:
	if GameState.shift_active and not _ended:
		_ended = true
		_end_shift()
