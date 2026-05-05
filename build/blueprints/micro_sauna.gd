extends BlueprintData
class_name MicroSaunaBlueprint

# Tiny satisfying build: 2×2 meter sauna
# Footprint: cells (1,1) to (2,2)
# Just floor, walls, and roof. Uses all the new materials nicely.

func _init() -> void:
	display_name = "Micro Sauna"
	phase_names = [
		"Structure — planks & floor",
		"Roof — panels",
	]
	_add_structure()
	_add_roofing()

func _add_structure() -> void:
	# Interior floor (2×2)
	for x in range(1, 3):
		for z in range(1, 3):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.FLOOR, "wood_board", BlueprintSlot.Phase.STRUCTURE)

	# Perimeter walls
	# North wall
	for x in range(1, 3):
		_slot(Vector2i(x, 0), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall
	for x in range(1, 3):
		_slot(Vector2i(x, 2), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	for z in range(1, 3):
		_slot(Vector2i(0, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	for z in range(1, 3):
		_slot(Vector2i(2, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	# Roof panels (2×2)
	for x in range(1, 3):
		for z in range(1, 3):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.ROOF, "roofing_panel", BlueprintSlot.Phase.ROOFING)

func _slot(cell: Vector2i, type: BlueprintSlot.PlacementType, item_id: String, phase: BlueprintSlot.Phase) -> void:
	var s := BlueprintSlot.new()
	s.cell = cell
	s.placement_type = type
	s.required_item_id = item_id
	s.phase = phase
	slots.append(s)
