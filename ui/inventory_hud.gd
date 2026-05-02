extends CanvasLayer

@onready var carry_label: Label = $Panel/VBox/CarryLabel
@onready var currency_label: Label = $Panel/VBox/CurrencyLabel

var _player: Node = null

func _ready() -> void:
	GameState.currency_changed.connect(func(v): currency_label.text = "$%d" % v)
	currency_label.text = "$%d" % GameState.currency

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	var items: Array = _player.carried_items
	if items.is_empty():
		carry_label.text = "Hands empty"
		return

	var lines := PackedStringArray()
	for item in items:
		var name: String = item.item_data.display_name if item.item_data else "?"
		lines.append(name)

	carry_label.text = "Carrying (%d/%d):\n%s" % [
		items.size(),
		_player.carry_capacity,
		"\n".join(lines)
	]
