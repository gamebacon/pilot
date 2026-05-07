extends BlueprintData
class_name SaunaBlueprint

# Finnish sauna — 3.0 m × 3.0 m interior.
# Phases:
#   0 — Pour Foundation  (9 concrete slabs)
#   1 — Frame Walls      (bottom plates → 600 mm OC studs → top plates)
#   2 — Lay Roof         (tarred roof panels)
#   3 — Clad Interior    (aspen T&G on north, west, east walls)
#   4 — Place Kiuas      (one sauna stone at the back-left corner)
#
# South wall has a 0.6 m door gap centred at X = 1.5.

const W := 3.0
const L := 3.0

const SLAB     := "concrete_slab"
const STUD     := "wall_stud"
const PLATE    := "wall_plate"
const ROOF     := "roofing_panel"
const CLADDING := "aspen_cladding"
const STONE    := "sauna_stone"

const DOOR_X0 := 1.2
const DOOR_X1 := 1.8

func _init() -> void:
	display_name = "Finnish Sauna"
	phase_names = [
		"Pour Foundation",
		"Frame Walls",
		"Lay Roof",
		"Clad Interior",
		"Place Kiuas",
	]
	_add_foundation()
	_add_framing()
	_add_roof()
	_add_interior()
	_add_kiuas()

# ── Phase 0 ───────────────────────────────────────────────────────────────────

func _add_foundation() -> void:
	_fill_floor(0.0, 0.0, W, L, SLAB, 0)

# ── Phase 1 ───────────────────────────────────────────────────────────────────

func _add_framing() -> void:
	var slab  := _load_item(SLAB)
	var stud  := _load_item(STUD)
	var plate := _load_item(PLATE)
	if not (slab and stud and plate): return

	var y_plate := slab.size.y
	var y_studs := y_plate + plate.size.y
	var y_top   := y_studs + stud.size.z

	var half_d := stud.size.y * 0.5
	var z_n := -half_d
	var z_s :=  L + half_d
	var x_w := -half_d
	var x_e :=  W + half_d

	# Bottom plates
	_fill_horiz_x(0.0, W, z_n, y_plate, PLATE, 1)
	_fill_horiz_x(0.0, W, z_s, y_plate, PLATE, 1)
	_fill_horiz_z(0.0, L, x_w, y_plate, PLATE, 1)
	_fill_horiz_z(0.0, L, x_e, y_plate, PLATE, 1)

	# Studs — north full span, south with door gap, east and west full
	_fill_vertical_x(0.0, W,       z_n, y_studs, STUD, 1)
	_fill_vertical_x(0.0, DOOR_X0, z_s, y_studs, STUD, 1)
	_fill_vertical_x(DOOR_X1, W,   z_s, y_studs, STUD, 1)
	_fill_vertical_z(0.0, L, x_w,  y_studs, STUD, 1)
	_fill_vertical_z(0.0, L, x_e,  y_studs, STUD, 1)

	# Top plates
	_fill_horiz_x(0.0, W, z_n, y_top, PLATE, 1)
	_fill_horiz_x(0.0, W, z_s, y_top, PLATE, 1)
	_fill_horiz_z(0.0, L, x_w, y_top, PLATE, 1)
	_fill_horiz_z(0.0, L, x_e, y_top, PLATE, 1)

# ── Phase 2 ───────────────────────────────────────────────────────────────────

func _add_roof() -> void:
	var slab  := _load_item(SLAB)
	var stud  := _load_item(STUD)
	var plate := _load_item(PLATE)
	if not (slab and stud and plate): return
	var roof_y := slab.size.y + plate.size.y + stud.size.z + plate.size.y
	_fill_roof(0.0, 0.0, W, L, roof_y, ROOF, 2)

# ── Phase 3 ───────────────────────────────────────────────────────────────────

func _add_interior() -> void:
	var stud     := _load_item(STUD)
	var cladding := _load_item(CLADDING)
	if not (stud and cladding): return

	# Position inner face just inside the stud face
	var inner := stud.size.y * 0.5 + cladding.size.y * 0.5

	# North, west, east walls — south skipped (has door)
	_fill_wall_x(0.0, W, inner,       CLADDING, 3)
	_fill_wall_z(0.0, L, inner,       CLADDING, 3)
	_fill_wall_z(0.0, L, W - inner,   CLADDING, 3)

# ── Phase 4 ───────────────────────────────────────────────────────────────────

func _add_kiuas() -> void:
	var stone := _load_item(STONE)
	if not stone: return
	# Kiuas position: back-left corner, on the foundation slab
	var slab := _load_item(SLAB)
	var y := (slab.size.y if slab else 0.15) + stone.size.y * 0.5
	_slot(Vector3(0.35, y, 0.35),
		BlueprintSlot.PlacementType.FLOOR, STONE, 4)
