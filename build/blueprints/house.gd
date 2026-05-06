extends BlueprintData
class_name HouseBlueprint

# Nordic cabin — 4 m wide (X) × 6 m long (Z), 2.4 m ceiling.
# Phase 0 — concrete-slab foundation + stud-wall framing.
# Phase 1 — flat roof deck and tiles.
# Phase 2 — mineral-wool insulation + plasterboard lining + wood floor.

const W := 4.0
const L := 6.0

func _init() -> void:
	display_name = "Simple House"
	phase_names = [
		"Foundation & Framing",
		"Roof Deck & Tiles",
		"Insulation & Interior Lining",
	]
	_add_structure()
	_add_roofing()
	_add_interior()

func _add_structure() -> void:
	var slab := _load_item("concrete_slab")
	var stud := _load_item("framing_section")
	if not (slab and stud): return

	var half_t := stud.size.y * 0.5

	# Foundation — 4 × 6 m footprint
	_fill_floor(0.0, 0.0, W, L, "concrete_slab", BlueprintSlot.Phase.STRUCTURE)

	# North wall — full span
	_fill_wall_x(0.0, W, -half_t, "framing_section", BlueprintSlot.Phase.STRUCTURE)

	# South wall — 0.8 m door gap centred at x = 2.0
	_fill_wall_x(0.0, 1.6, L + half_t, "framing_section", BlueprintSlot.Phase.STRUCTURE)
	_fill_wall_x(2.4, W,   L + half_t, "framing_section", BlueprintSlot.Phase.STRUCTURE)

	# West wall
	_fill_wall_z(0.0, L, -half_t, "framing_section", BlueprintSlot.Phase.STRUCTURE)

	# East wall
	_fill_wall_z(0.0, L, W + half_t, "framing_section", BlueprintSlot.Phase.STRUCTURE)

func _add_roofing() -> void:
	var stud := _load_item("framing_section")
	if not stud: return
	_fill_roof(0.0, 0.0, W, L, stud.size.z, "roofing_panel", BlueprintSlot.Phase.ROOFING)

func _add_interior() -> void:
	var stud := _load_item("framing_section")
	var ins  := _load_item("insulation_batt")
	var dry  := _load_item("drywall")
	var slab := _load_item("concrete_slab")
	if not (stud and ins and dry and slab): return

	# Wood floor boards over the concrete slab
	_fill_floor(0.0, 0.0, W, L, "wood_board", BlueprintSlot.Phase.INTERIOR, slab.size.y)

	# Offset from the room-edge (inner face of framing)
	var ins_offset := stud.size.y * 0.5 + ins.size.y * 0.5
	var dry_offset := stud.size.y * 0.5 + ins.size.y + dry.size.y * 0.5

	# Insulation batts — inside all four walls
	_fill_wall_x(0.0, W,   ins_offset,       "insulation_batt", BlueprintSlot.Phase.INTERIOR)  # north
	_fill_wall_x(0.0, 1.6, L - ins_offset,   "insulation_batt", BlueprintSlot.Phase.INTERIOR)  # south left
	_fill_wall_x(2.4, W,   L - ins_offset,   "insulation_batt", BlueprintSlot.Phase.INTERIOR)  # south right
	_fill_wall_z(0.0, L,   ins_offset,       "insulation_batt", BlueprintSlot.Phase.INTERIOR)  # west
	_fill_wall_z(0.0, L,   W - ins_offset,   "insulation_batt", BlueprintSlot.Phase.INTERIOR)  # east

	# Plasterboard — innermost layer on all walls
	_fill_wall_x(0.0, W,   dry_offset,       "drywall", BlueprintSlot.Phase.INTERIOR)  # north
	_fill_wall_x(0.0, 1.6, L - dry_offset,   "drywall", BlueprintSlot.Phase.INTERIOR)  # south left
	_fill_wall_x(2.4, W,   L - dry_offset,   "drywall", BlueprintSlot.Phase.INTERIOR)  # south right
	_fill_wall_z(0.0, L,   dry_offset,       "drywall", BlueprintSlot.Phase.INTERIOR)  # west
	_fill_wall_z(0.0, L,   W - dry_offset,   "drywall", BlueprintSlot.Phase.INTERIOR)  # east
