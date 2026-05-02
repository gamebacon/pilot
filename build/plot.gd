extends StaticBody3D
class_name Plot

const CELL_SIZE := 1.0
const GRID_WIDTH := 6
const GRID_DEPTH := 8

var occupied: Dictionary = {}          # Vector2i -> placed StaticBody3D
var blueprint_instance: BlueprintInstance = null

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_DEPTH

func is_occupied(cell: Vector2i) -> bool:
	return occupied.has(cell)

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := to_local(world_pos)
	return Vector2i(floori(local.x / CELL_SIZE), floori(local.z / CELL_SIZE))

func cell_to_world_center(cell: Vector2i) -> Vector3:
	var local := Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)
	return to_global(local)

func get_surface_y() -> float:
	return global_position.y

func place(cell: Vector2i, piece: Node) -> void:
	occupied[cell] = piece

func vacate(cell: Vector2i) -> void:
	occupied.erase(cell)

func get_interact_hint(player: Node) -> String:
	if blueprint_instance:
		return ""
	for item in player.carried_items:
		var pi := item as PhysicalItem
		if pi.item_data and pi.item_data.is_blueprint:
			return "[E]  Unroll Blueprint"
	return ""

# Called by the player's interact ray when pressing E while looking at the plot floor
func interact(player: Node) -> void:
	if blueprint_instance:
		return  # Blueprint already placed

	# Search carry for a blueprint item
	var items: Array = player.carried_items
	for i in range(items.size() - 1, -1, -1):
		var item: PhysicalItem = items[i]
		if item.item_data and item.item_data.is_blueprint and item.item_data.blueprint_data:
			_activate_blueprint(item.item_data.blueprint_data)
			items.remove_at(i)
			item.queue_free()
			return

func _activate_blueprint(data: BlueprintData) -> void:
	var scene: PackedScene = preload("res://build/blueprint_instance.tscn")
	blueprint_instance = scene.instantiate() as BlueprintInstance
	add_child(blueprint_instance)
	# Blueprint instance sits at the plot's origin so its local coords match the grid
	blueprint_instance.position = Vector3.ZERO
	blueprint_instance.activate(data)
