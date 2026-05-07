extends BlueprintData
class_name TerraceBlueprint

# Garden terrace / outdoor deck — 2.4 m wide (X) × 1.5 m deep (Z).
# A single phase: lay 20 pine decking boards directly on the ground.
# Simple first build — no foundation, no walls.

const W := 2.4
const L := 1.5

const DECKING := "pine_decking"

func _init() -> void:
	display_name = "Garden Terrace"
	phase_names = [
		"Lay Decking",
	]
	_fill_floor(0.0, 0.0, W, L, DECKING, 0)
