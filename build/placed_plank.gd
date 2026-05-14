class_name PlacedPlank
extends StaticBody3D

var size:   Vector3 = Vector3(1.0, 1.0, 1.0)
var color:  Color   = Color(0.7, 0.46, 0.2)
var net_id: int     = 0  # 0 = not networked (blueprint pieces)

# Creates a fully assembled PlacedPlank ready to add to the scene.
static func build(p_size: Vector3, p_color: Color) -> PlacedPlank:
	var piece := PlacedPlank.new()
	piece.size  = p_size
	piece.color = p_color

	var shape := BoxShape3D.new()
	shape.size = p_size
	var col    := CollisionShape3D.new()
	col.shape  = shape
	piece.add_child(col)

	var box := BoxMesh.new()
	box.size = p_size
	var mi   := MeshInstance3D.new()
	mi.mesh              = box
	mi.material_override = _tinted_mat(p_color)
	piece.add_child(mi)

	return piece

# Wood-grain tonal variation: stronger shift on R, weaker on G/B.
static func _tinted_mat(base: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var v   := randf_range(-0.07, 0.07)
	mat.albedo_color = Color(
		clampf(base.r + v,        0.0, 1.0),
		clampf(base.g + v * 0.55, 0.0, 1.0),
		clampf(base.b + v * 0.30, 0.0, 1.0),
		base.a
	)
	return mat

# ── Socket system ─────────────────────────────────────────────────────────────

# 6 face centres + 8 corners = 14 attachment points in local space.
static func sockets_for(s: Vector3) -> Array:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	return [
		Vector3(-hx, 0.0, 0.0), Vector3( hx, 0.0, 0.0),
		Vector3(0.0, -hy, 0.0), Vector3(0.0,  hy, 0.0),
		Vector3(0.0, 0.0, -hz), Vector3(0.0, 0.0,  hz),
		Vector3(-hx, -hy, -hz), Vector3( hx, -hy, -hz),
		Vector3(-hx, -hy,  hz), Vector3( hx, -hy,  hz),
		Vector3(-hx,  hy, -hz), Vector3( hx,  hy, -hz),
		Vector3(-hx,  hy,  hz), Vector3( hx,  hy,  hz),
	]

func _ready() -> void:
	add_to_group("placed_planks")

func get_world_sockets() -> Array:
	var result := []
	for local_pos: Vector3 in PlacedPlank.sockets_for(size):
		result.append(global_transform * local_pos)
	return result
