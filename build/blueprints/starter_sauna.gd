extends BlueprintData
class_name StarterSaunaBlueprint

# Outer footprint: 4 wide (x 0–3), 5 deep (z 0–4)
# Interior: x 1–2, z 1–3  (2 × 3 m — realistic small Finnish sauna)
# Door gap: south wall at x = 1
# Full-cell walls (1 × 2.2 × 1 m) so corners join with zero gaps — no rotation needed.

func _init() -> void:
	display_name = "Starter Sauna"
	phase_names = [
		"Structure — wood planks",
		"Roofing — roofing panels",
	]
	_add_structure()
	_add_roofing()

func _add_structure() -> void:
	# Interior floor
	for x in range(1, 3):
		for z in range(1, 4):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.FLOOR, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# North wall (full row)
	for x in range(0, 4):
		_slot(Vector2i(x, 0), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall — door gap at x = 1
	for x in [0, 2, 3]:
		_slot(Vector2i(x, 4), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	for z in range(1, 4):
		_slot(Vector2i(0, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	for z in range(1, 4):
		_slot(Vector2i(3, z), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	for x in range(0, 4):
		for z in range(0, 5):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.ROOF, "roofing_panel", BlueprintSlot.Phase.ROOFING)

func _slot(cell: Vector2i, type: BlueprintSlot.PlacementType, item_id: String, phase: BlueprintSlot.Phase) -> void:
	var s := BlueprintSlot.new()
	s.cell = cell
	s.placement_type = type
	s.required_item_id = item_id
	s.phase = phase
	slots.append(s)
