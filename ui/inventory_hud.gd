extends CanvasLayer

@onready var carry_label:    Label = $Panel/VBox/CarryLabel
@onready var currency_label: Label = $Panel/VBox/CurrencyLabel

func _ready() -> void:
	GameState.currency_changed.connect(func(v): currency_label.text = "$%d" % v)
	currency_label.text = "$%d" % GameState.currency

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	player.inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed(player.inventory.items, player.inventory.capacity)
	set_process(false)

func _on_inventory_changed(items: Array[PhysicalItem], capacity: int) -> void:
	if items.is_empty():
		carry_label.text = "Hands empty"
		return
	var lines := PackedStringArray()
	for item in items:
		lines.append(item.item_data.display_name if item.item_data else "?")
	carry_label.text = "Carrying (%d/%d):\n%s" % [items.size(), capacity, "\n".join(lines)]
