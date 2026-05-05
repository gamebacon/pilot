extends BlueprintData
class_name TraditionalSaunaBlueprint

# Three phases: shell structure, roof, interior finish.
# 2 m × 3 m interior. All positions derived from item sizes.

func _init() -> void:
	display_name = "Traditional Sauna"
	phase_names  = [
		"Structure — floor & walls",
		"Roofing — tarred panels",
		"Interior — cladding & kiuas",
	]
	_add_structure()
	_add_roofing()
	_add_interior()

func _add_structure() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	var half_t := plank.size.y * 0.5
	var height := plank.size.z

	# Interior floor
	_fill_floor(0.0, 0.0, 2.0, 3.0, "wood_board", BlueprintSlot.Phase.STRUCTURE)

	# North wall — full span
	_fill_wall_x(0.0, 2.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# South wall — 0.4 m door gap centred at x = 1.0
	_fill_wall_x(0.0, 0.8, 3.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)
	_fill_wall_x(1.2, 2.0, 3.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	_fill_wall_z(0.0, 3.0, -half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	_fill_wall_z(0.0, 3.0, 2.0 + half_t, "wood_plank", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	var plank := _load_item("wood_plank")
	if not plank: return
	_fill_roof(0.0, 0.0, 2.0, 3.0, plank.size.z, "roofing_panel", BlueprintSlot.Phase.ROOFING)

func _add_interior() -> void:
	var plank := _load_item("wood_plank")
	var panel := _load_item("sauna_panel")
	var stone := _load_item("sauna_stone")
	var board := _load_item("wood_board")
	if not (plank and panel and stone and board): return

	# Inner face of structure walls: just inside the plank thickness
	var inner_offset := plank.size.y * 0.5 + panel.size.y * 0.5

	# North inner cladding
	_fill_wall_x(0.0, 2.0, inner_offset, "sauna_panel", BlueprintSlot.Phase.INTERIOR)
	# West inner cladding
	_fill_wall_z(0.0, 3.0, inner_offset, "sauna_panel", BlueprintSlot.Phase.INTERIOR)
	# East inner cladding
	_fill_wall_z(0.0, 3.0, 2.0 - inner_offset, "sauna_panel", BlueprintSlot.Phase.INTERIOR)

	# Kiuas (sauna stove stone platform) — back-left corner
	_slot(Vector3(0.3, stone.size.y * 0.5, 0.3),
		BlueprintSlot.PlacementType.FLOOR, "sauna_stone", BlueprintSlot.Phase.INTERIOR)

	# Lower bench — along back wall, 0.45 m high
	_fill_floor(0.0, 2.5, 2.0, 3.0, "wood_board", BlueprintSlot.Phase.INTERIOR, 0.45)

	# Upper bench — one step forward, 0.9 m high
	_fill_floor(0.0, 2.0, 2.0, 2.5, "wood_board", BlueprintSlot.Phase.INTERIOR, 0.90)
