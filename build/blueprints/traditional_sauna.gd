extends BlueprintData
class_name TraditionalSaunaBlueprint

# Outer footprint: x 0-3, z 0-4 (4m wide, 5m deep)
# Interior: x 1-2, z 1-3 (2m × 3m)
# Door gap: south wall at x=1
# Three phases: frame the shell, lay the roof, finish the inside

func _init() -> void:
	display_name = "Traditional Sauna"
	phase_names = [
		"Structure — floor & walls",
		"Roofing — tarred panels",
		"Interior — cladding & kiuas",
	]
	_add_structure()
	_add_roofing()
	_add_interior()

func _add_structure() -> void:
	# Interior floor (2×3m)
	for x in range(1, 3):
		for z in range(1, 4):
			_slot(Vector2i(x, z), BlueprintSlot.PlacementType.FLOOR, "wood_board", BlueprintSlot.Phase.STRUCTURE)

	# North wall (full span)
	for x in range(0, 4):
		_slot(Vector2i(x, 0), BlueprintSlot.PlacementType.WALL, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall — door gap at x=1
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

func _add_interior() -> void:
	# North wall cladding (aspen panels behind the hot wall)
	for x in range(1, 3):
		_slot(Vector2i(x, 0), BlueprintSlot.PlacementType.WALL, "sauna_panel", BlueprintSlot.Phase.INTERIOR)

	# West wall cladding
	for z in range(1, 4):
		_slot(Vector2i(0, z), BlueprintSlot.PlacementType.WALL, "sauna_panel", BlueprintSlot.Phase.INTERIOR)

	# East wall cladding
	for z in range(1, 4):
		_slot(Vector2i(3, z), BlueprintSlot.PlacementType.WALL, "sauna_panel", BlueprintSlot.Phase.INTERIOR)

	# Kiuas platform — front corner, near door wall
	_slot(Vector2i(2, 1), BlueprintSlot.PlacementType.FLOOR, "sauna_stone", BlueprintSlot.Phase.INTERIOR)

	# Lower bench — along back wall
	for x in range(1, 3):
		_slot(Vector2i(x, 3), BlueprintSlot.PlacementType.FLOOR, "wood_board", BlueprintSlot.Phase.INTERIOR)

	# Upper bench — one step up from lower
	_slot(Vector2i(1, 2), BlueprintSlot.PlacementType.FLOOR, "wood_board", BlueprintSlot.Phase.INTERIOR)
	_slot(Vector2i(2, 2), BlueprintSlot.PlacementType.FLOOR, "wood_board", BlueprintSlot.Phase.INTERIOR)

func _slot(cell: Vector2i, type: BlueprintSlot.PlacementType, item_id: String, phase: BlueprintSlot.Phase) -> void:
	var s := BlueprintSlot.new()
	s.cell = cell
	s.placement_type = type
	s.required_item_id = item_id
	s.phase = phase
	slots.append(s)
