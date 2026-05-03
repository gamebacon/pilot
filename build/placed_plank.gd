class_name PlacedPlank
extends StaticBody3D

# Plank dimensions
const PLANK_LENGTH := 2.0   # along local X
const PLANK_HEIGHT := 0.1   # thickness (local Y)
const PLANK_WIDTH  := 0.2   # width (local Z)

const HL := PLANK_LENGTH * 0.5
const HH := PLANK_HEIGHT * 0.5
const HW := PLANK_WIDTH  * 0.5

# Snap socket positions in local space.
# These are the points where another plank can attach.
const LOCAL_SOCKETS := [
	# End face centres — end-to-end joining
	Vector3(-HL,   0.0,  0.0),
	Vector3( HL,   0.0,  0.0),
	# Top face corners + midpoint — stacking on top
	Vector3(-HL,   HH,   HW),
	Vector3(-HL,   HH,  -HW),
	Vector3( 0.0,  HH,   0.0),
	Vector3( HL,   HH,   HW),
	Vector3( HL,   HH,  -HW),
	# Bottom face corners + midpoint — hanging / support from below
	Vector3(-HL,  -HH,   HW),
	Vector3(-HL,  -HH,  -HW),
	Vector3( 0.0, -HH,   0.0),
	Vector3( HL,  -HH,   HW),
	Vector3( HL,  -HH,  -HW),
	# Long-side midpoints — perpendicular attachment
	Vector3( 0.0,  0.0,  HW),
	Vector3( 0.0,  0.0, -HW),
]

func _ready() -> void:
	add_to_group("placed_planks")

# Returns all socket positions in world space.
func get_world_sockets() -> Array:
	var result := []
	for local_pos: Vector3 in LOCAL_SOCKETS:
		result.append(global_transform * local_pos)
	return result
