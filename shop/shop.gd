extends StaticBody3D

@export var stock: Array[ItemData] = []

# Where purchased items physically appear for pickup
@onready var spawn_point: Marker3D = $SpawnPoint

func interact(_player: Node) -> void:
	var ui := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if ui:
		ui.open(stock, self)

func get_interact_hint(_player: Node) -> String:
	return "[E]  Browse Shop"

func spawn_item(item_data: ItemData) -> void:
	var item_scene: PackedScene = preload("res://items/physical_item.tscn")
	var item := item_scene.instantiate() as PhysicalItem
	item.item_data = item_data
	# Show the item name on its label
	item.get_node("Label3D").text = item_data.display_name
	get_tree().current_scene.add_child(item)
	item.global_position = spawn_point.global_position + Vector3(randf_range(-0.3, 0.3), 0.5, 0)
