extends StaticBody3D
class_name Plot

const CELL_SIZE := 1.0
const GRID_WIDTH := 6
const GRID_DEPTH := 8

var occupied: Dictionary = {}          # Vector2i -> placed StaticBody3D
var blueprint_instance: BlueprintInstance = null
var _grid_node: Node3D = null

func _ready() -> void:
	pass  # grid shown only when build mode is entered

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

func show_grid() -> void:
	if not _grid_node:
		_grid_node = Node3D.new()
		add_child(_grid_node)
		_build_grid()
	_grid_node.show()

func hide_grid() -> void:
	if _grid_node:
		_grid_node.hide()

func _build_grid() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED

	var line_h  := 0.005  # mesh height above surface
	var line_t  := 0.025  # line visual thickness

	# Lines running along Z (one per x column boundary, GRID_WIDTH + 1 total)
	for xi in range(GRID_WIDTH + 1):
		var mi  := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(line_t, line_h, GRID_DEPTH * CELL_SIZE + line_t)
		mi.mesh              = box
		mi.material_override = mat
		mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position          = Vector3(xi * CELL_SIZE, line_h * 0.5, GRID_DEPTH * CELL_SIZE * 0.5)
		_grid_node.add_child(mi)

	# Lines running along X (one per z row boundary, GRID_DEPTH + 1 total)
	for zi in range(GRID_DEPTH + 1):
		var mi  := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(GRID_WIDTH * CELL_SIZE + line_t, line_h, line_t)
		mi.mesh              = box
		mi.material_override = mat
		mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position          = Vector3(GRID_WIDTH * CELL_SIZE * 0.5, line_h * 0.5, zi * CELL_SIZE)
		_grid_node.add_child(mi)
