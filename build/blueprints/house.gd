extends BlueprintData
class_name HouseBlueprint

# 4 m wide (X) × 6 m long (Z) house.
# Builds like a real frame, phase by phase:
#   0 — concrete slab foundation
#   1 — floor frame  (2x10 joists, 600 mm OC)
#   2 — wall skeleton (bottom plate → 2x4 studs at 600 mm OC → top plate)
#   3 — sheathing & roofing panels
#
# Door: 0.8 m rough opening centred at X = 2.0 on the south wall.

const W := 4.0
const L := 6.0

# Item IDs
const SLAB  := "concrete_slab"
const JOIST := "floor_joist"    # 2x10, 4 m span
const STUD  := "wall_stud"      # 2x4, 2.4 m — vertical framing
const PLATE := "wall_plate"     # 2x4, 1 m  — horizontal plates
const ROOF  := "roofing_panel"

# Door rough opening
const DOOR_X0 := 1.6
const DOOR_X1 := 2.4

func _init() -> void:
	display_name = "House"
	phase_names = [
		"Pour Foundation",
		"Floor Frame",
		"Wall Skeleton",
		"Sheathing & Roofing",
	]
	_add_foundation()
	_add_floor_frame()
	_add_wall_skeleton()
	_add_roofing()

# ── Phase 0 — Foundation ──────────────────────────────────────────────────────

func _add_foundation() -> void:
	_fill_floor(0.0, 0.0, W, L, SLAB, 0)

# ── Phase 1 — Floor frame ─────────────────────────────────────────────────────

func _add_floor_frame() -> void:
	var slab  := _load_item(SLAB)
	var joist := _load_item(JOIST)
	if not (slab and joist): return

	# Full-width joists resting on the slab, spaced 600 mm OC.
	# z = 0 and z = L serve as rim joists at each gable end.
	var y_base := slab.size.y   # top of slab
	var z := 0.0
	while z <= L + 0.001:
		_fill_horiz_x(0.0, W, z, y_base, JOIST, 1)
		z = snappedf(z + 0.6, 0.001)

# ── Phase 2 — Wall skeleton ───────────────────────────────────────────────────

func _add_wall_skeleton() -> void:
	var slab  := _load_item(SLAB)
	var joist := _load_item(JOIST)
	var stud  := _load_item(STUD)
	var plate := _load_item(PLATE)
	if not (slab and joist and stud and plate): return

	# Plates sit on top of the floor frame; studs sit on top of the bottom plate.
	var y_plate := slab.size.y + joist.size.y   # bottom of wall plate = top of joists
	var y_studs := y_plate + plate.size.y        # bottom of studs

	# Top of studs (= stud height stored as size.z, becomes Y after rotation)
	var y_top := y_studs + stud.size.z

	# Wall centre positions — inside face flush with plot boundary
	var half_d := stud.size.y * 0.5
	var z_n := -half_d
	var z_s :=  L + half_d
	var x_w := -half_d
	var x_e :=  W + half_d

	# ── Bottom plates ────────────────────────────────────────────────────────
	_fill_horiz_x(0.0, W, z_n, y_plate, PLATE, 2)
	_fill_horiz_x(0.0, W, z_s, y_plate, PLATE, 2)
	_fill_horiz_z(0.0, L, x_w, y_plate, PLATE, 2)
	_fill_horiz_z(0.0, L, x_e, y_plate, PLATE, 2)

	# ── Studs ─────────────────────────────────────────────────────────────────
	# North wall — full span, 600 mm OC, corner posts at ends
	_fill_vertical_x(0.0, W, z_n, y_studs, STUD, 2)

	# South wall — king studs at door edges (1.6 and 2.4), rest at 600 mm OC
	_fill_vertical_x(0.0,    DOOR_X0, z_s, y_studs, STUD, 2)
	_fill_vertical_x(DOOR_X1, W,      z_s, y_studs, STUD, 2)

	# West and east walls — full span, 600 mm OC, corners included
	_fill_vertical_z(0.0, L, x_w, y_studs, STUD, 2)
	_fill_vertical_z(0.0, L, x_e, y_studs, STUD, 2)

	# ── Top plates ───────────────────────────────────────────────────────────
	_fill_horiz_x(0.0, W, z_n, y_top, PLATE, 2)
	_fill_horiz_x(0.0, W, z_s, y_top, PLATE, 2)
	_fill_horiz_z(0.0, L, x_w, y_top, PLATE, 2)
	_fill_horiz_z(0.0, L, x_e, y_top, PLATE, 2)

# ── Phase 3 — Sheathing & roofing ────────────────────────────────────────────

func _add_roofing() -> void:
	var slab  := _load_item(SLAB)
	var joist := _load_item(JOIST)
	var stud  := _load_item(STUD)
	var plate := _load_item(PLATE)
	if not (slab and joist and stud and plate): return

	var roof_y := slab.size.y + joist.size.y + plate.size.y + stud.size.z + plate.size.y
	_fill_roof(0.0, 0.0, W, L, roof_y, ROOF, 3)
