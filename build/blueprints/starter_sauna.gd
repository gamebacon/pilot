extends BlueprintData
class_name StarterSaunaBlueprint

# 2 m × 3 m interior floor, walls and roof all derived from item dimensions.

func _init() -> void:
	display_name = "Starter Sauna"
	phase_names  = ["Structure — wood planks", "Roofing — panels"]
	_add_structure()
	_add_roofing()

func _add_structure() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	var half_t := plank.size.y * 0.5   # half wall thickness in Z (= 0.025 m)
	var height := plank.size.z         # wall height when standing (= 1.0 m)

	# Interior floor: 2 m × 3 m
	_fill_floor(0.0, 0.0, 2.0, 3.0, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# North wall — full span
	_fill_wall_x(0.0, 2.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall — door gap 0.4 m wide centred at x = 1.0
	_fill_wall_x(0.0, 0.8, 3.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)
	_fill_wall_x(1.2, 2.0, 3.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	_fill_wall_z(0.0, 3.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	_fill_wall_z(0.0, 3.0, 2.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	var height := plank.size.z  # top of walls
	_fill_roof(0.0, 0.0, 2.0, 3.0, height, "roofing_panel", BlueprintSlot.Phase.ROOFING)
