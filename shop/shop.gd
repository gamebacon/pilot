extends StaticBody3D

# Optional whitelist — if empty, the shop stocks every item in ItemRegistry.
# Add specific item IDs here to restrict what this shop sells.
@export var stock_ids: Array[String] = []

var _stock: Array[ItemData] = []

@onready var spawn_point: Marker3D = $SpawnPoint

func _ready() -> void:
	if stock_ids.is_empty():
		_stock = ItemRegistry.get_all()
	else:
		for id in stock_ids:
			var item := ItemRegistry.get_item(id)
			if item:
				_stock.append(item)
			else:
				push_warning("Shop: unknown item id '%s'" % id)

func interact(_player: Node) -> void:
	var ui := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if ui:
		ui.open(_stock, self)

func get_interact_hint(_player: Node) -> String:
	return "%s  Browse hardware store" % InputHelper.action_label("interact")

func spawn_item(item_data: ItemData) -> void:
	var item_scene: PackedScene = preload("res://items/physical_item.tscn")
	var item := item_scene.instantiate() as PhysicalItem
	item.item_data = item_data
	get_tree().current_scene.add_child(item)
	# Spawn in front of the counter face so items can't clip inside the mesh.
	var forward := -global_transform.basis.z
	var pos := spawn_point.global_position \
		+ forward * 0.7 \
		+ Vector3(randf_range(-0.2, 0.2), 0.1, 0.0)
	item.global_position = pos

	if NetworkManager.is_active():
		var world := get_tree().get_first_node_in_group("world")
		if world:
			item.net_id = world.assign_item_id()
			world.sync_item_spawn(item_data.id, pos, item.net_id)
