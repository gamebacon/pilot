extends Node

signal currency_changed(new_amount: int)

var currency: int = 5_000

func add_currency(amount: int) -> void:
	currency += amount
	emit_signal("currency_changed", currency)

func spend_currency(amount: int) -> bool:
	if currency < amount:
		return false
	currency -= amount
	emit_signal("currency_changed", currency)
	return true
