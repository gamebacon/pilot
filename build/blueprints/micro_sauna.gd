extends BlueprintData
class_name MicroSaunaBlueprint

# Tiny build: 2 m × 2 m floor, wood_board floor, wood_plank walls.

func _init() -> void:
	display_name = "Micro Sauna"
	phase_names  = ["Structure — planks & boards", "Roof — panels"]
	_add_structure()
	_add_roofing()

func _add_structure() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	var half_t := plank.size.y * 0.5
	var height := plank.size.z

	# Interior floor: 2 m × 2 m with wood_board
	_fill_floor(0.0, 0.0, 2.0, 2.0, "wood_board", BlueprintSlot.Phase.STRUCTURE)

	# North wall
	_fill_wall_x(0.0, 2.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall — full (no door gap on micro sauna; hatch-style entry)
	_fill_wall_x(0.0, 2.0, 2.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	_fill_wall_z(0.0, 2.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	_fill_wall_z(0.0, 2.0, 2.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	_fill_roof(0.0, 0.0, 2.0, 2.0, plank.size.z, "roofing_panel", BlueprintSlot.Phase.ROOFING)
