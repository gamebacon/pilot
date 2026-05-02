extends BlueprintData
class_name StarterSaunaBlueprint

# Layout: 4 wide (x 0-3), 5 deep (z 0-4)
# Interior floor: x 1-2, z 1-3
# Door gap: south wall at x=1

func _init() -> void:
	display_name = "Starter Sauna"
	phase_names = [
		"Structure — wood planks",
		"Roofing — roofing panels",
	]
	_add_structure()
	_add_roofing()

func _add_structure() -> void:
	# Interior floor tiles (no rotation)
	for x in range(1, 3):
		for z in range(1, 4):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.FLOOR, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# North wall — faces Z axis, no rotation
	for x in range(0, 4):
		_slot(Vector2i(x, 0), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE, 0.0)

	# South wall — door gap at x=1, no rotation
	for x in [0, 2, 3]:
		_slot(Vector2i(x, 4), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE, 0.0)

	# West wall — faces X axis, 90° rotation
	for z in range(1, 4):
		_slot(Vector2i(0, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE, 90.0)

	# East wall — faces X axis, 90° rotation
	for z in range(1, 4):
		_slot(Vector2i(3, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE, 90.0)

func _add_roofing() -> void:
	for x in range(0, 4):
		for z in range(0, 5):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.ROOF, "roofing_panel", BlueprintSlot.Phase.ROOFING)

func _slot(cell: Vector2i, type: BlueprintSlot.PlacementType, item_id: String, phase: BlueprintSlot.Phase, rot_y: float = 0.0) -> void:
	var s := BlueprintSlot.new()
	s.cell = cell
	s.placement_type = type
	s.required_item_id = item_id
	s.phase = phase
	s.rotation_y_deg = rot_y
	slots.append(s)
