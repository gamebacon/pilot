extends StaticBody3D

# Add item IDs here — each must match a .tres file in res://items/resources/
@export var stock_ids: Array[String] = []

var _stock: Array[ItemData] = []

@onready var spawn_point: Marker3D = $SpawnPoint

func _ready() -> void:
	for id in stock_ids:
		var path := "res://items/resources/" + id + ".tres"
		if ResourceLoader.exists(path):
			_stock.append(load(path) as ItemData)
		else:
			push_warning("Shop: missing item resource: " + id)

func interact(_player: Node) -> void:
	var ui := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if ui:
		ui.open(_stock, self)

func get_interact_hint(_player: Node) -> String:
	return "[E]  Browse Shop"

func spawn_item(item_data: ItemData) -> void:
	var item_scene: PackedScene = preload("res://items/physical_item.tscn")
	var item := item_scene.instantiate() as PhysicalItem
	item.item_data = item_data
	get_tree().current_scene.add_child(item)
	item.global_position = spawn_point.global_position + Vector3(randf_range(-0.3, 0.3), 0.5, 0)
