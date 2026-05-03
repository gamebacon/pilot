class_name PlacedPlank
extends StaticBody3D

# A placed building piece. Size and colour are set on creation by the placer.

var size:  Vector3 = Vector3(1.0, 1.0, 1.0)
var color: Color   = Color(0.7, 0.46, 0.2)

# Snap socket positions in local space, computed from the piece's size.
# 6 face centres + 8 corners = 14 attachment points.
static func sockets_for(s: Vector3) -> Array:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	return [
		# Face centres
		Vector3(-hx, 0.0, 0.0), Vector3( hx, 0.0, 0.0),
		Vector3(0.0, -hy, 0.0), Vector3(0.0,  hy, 0.0),
		Vector3(0.0, 0.0, -hz), Vector3(0.0, 0.0,  hz),
		# Corners
		Vector3(-hx, -hy, -hz), Vector3( hx, -hy, -hz),
		Vector3(-hx, -hy,  hz), Vector3( hx, -hy,  hz),
		Vector3(-hx,  hy, -hz), Vector3( hx,  hy, -hz),
		Vector3(-hx,  hy,  hz), Vector3( hx,  hy,  hz),
	]

func _ready() -> void:
	add_to_group("placed_planks")

# Returns all socket positions in world space.
func get_world_sockets() -> Array:
	var result := []
	for local_pos: Vector3 in PlacedPlank.sockets_for(size):
		result.append(global_transform * local_pos)
	return result
