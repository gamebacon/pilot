extends StaticBody3D
class_name Plot

const CELL_SIZE := 1.0
const GRID_WIDTH := 6
const GRID_DEPTH := 8

# Vector2i -> placed StaticBody3D
var occupied: Dictionary = {}

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
