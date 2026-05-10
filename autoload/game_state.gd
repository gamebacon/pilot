extends Node

signal currency_changed(new_amount: int)
signal debug_mode_changed(enabled: bool)
signal shift_ended(pay: int)

var currency: int = 800
var active_build_mode: String = ""  # "blueprint" | "freeplace" | ""
var day: int = 1
var shift_active: bool = false
var shift_done: bool = false

var debug_mode: bool = false:
	set(v):
		debug_mode = v
		debug_mode_changed.emit(v)

# Any UI that fully blocks gameplay input (shop, pause menu, etc.) increments
# this. Player reads it to decide whether to process game input.
var _ui_stack: int = 0
var ui_open: bool:
	get: return _ui_stack > 0

func push_ui() -> void:
	_ui_stack += 1

func pop_ui() -> void:
	_ui_stack = max(0, _ui_stack - 1)

func add_currency(amount: int) -> void:
	currency += amount
	emit_signal("currency_changed", currency)

func spend_currency(amount: int) -> bool:
	if currency < amount:
		return false
	currency -= amount
	emit_signal("currency_changed", currency)
	return true
