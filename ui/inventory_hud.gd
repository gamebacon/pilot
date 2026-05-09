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
	_on_inventory_changed(player.inventory.items, player.inventory.capacity, player.inventory.active_index)
	set_process(false)

func _on_inventory_changed(items: Array[PhysicalItem], capacity: int, active_index: int) -> void:
	if items.is_empty():
		carry_label.text = "Hands empty"
		return

	# Group items by ID, preserving first-appearance order.
	var order: Array[String] = []
	var counts: Dictionary  = {}
	var names:  Dictionary  = {}
	var active_id := items[active_index].item_data.id if items[active_index].item_data else ""

	for item in items:
		var id := item.item_data.id if item.item_data else "_"
		if id not in counts:
			order.append(id)
			counts[id] = 0
			names[id]  = item.item_data.display_name if item.item_data else "?"
		counts[id] += 1

	var player := get_tree().get_first_node_in_group("player")
	var slots_used: int = player.inventory.used_slots() if player else items.size()

	var lines := PackedStringArray()
	for id in order:
		var prefix := "► " if id == active_id else "   "
		var count: int = counts[id]
		var count_str := "%d× " % count if count > 1 else "    "
		lines.append("%s%s%s" % [prefix, count_str, names[id]])

	carry_label.text = "Carrying (%d/%d slots):\n%s" % [slots_used, capacity, "\n".join(lines)]
