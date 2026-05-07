extends StaticBody3D
class_name Plot

var blueprint_instance: BlueprintInstance = null

func _ready() -> void:
	add_to_group("plot")

func get_surface_y() -> float:
	return global_position.y

func get_interact_hint(player: Node) -> String:
	if blueprint_instance:
		return ""
	for item in player.inventory.items:
		if item.item_data and item.item_data.is_blueprint:
			return "%s  Unroll Blueprint" % InputHelper.action_label("interact")
	return ""

func interact(player: Node) -> void:
	if blueprint_instance:
		return
	var items: Array[PhysicalItem] = player.inventory.items
	for i in range(items.size() - 1, -1, -1):
		var item: PhysicalItem = items[i]
		if item.item_data and item.item_data.is_blueprint and item.item_data.blueprint_data:
			_activate_blueprint(item.item_data.blueprint_data)
			player.inventory.remove(item)
			item.queue_free()
			return

func _activate_blueprint(data: BlueprintData) -> void:
	var scene: PackedScene = preload("res://build/blueprint_instance.tscn")
	blueprint_instance = scene.instantiate() as BlueprintInstance
	add_child(blueprint_instance)
	blueprint_instance.position = Vector3.ZERO
	blueprint_instance.activate(data)
