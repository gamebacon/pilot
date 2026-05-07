extends Node

signal currency_changed(new_amount: int)

var currency: int = 5_000
var active_build_mode: String = ""  # "blueprint" | "freeplace" | ""

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
