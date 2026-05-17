extends StaticBody3D
class_name PlacedObject

## A static world object created when the player places a crafted item.
## Call PlacedObject.make(data) to build one; then add it to the scene and set position/rotation.

var item_data: ItemData = null

static func make(data: ItemData) -> PlacedObject:
	var obj := PlacedObject.new()
	obj.item_data = data

	# Visual mesh
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = data.size
	mi.mesh   = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.color
	mi.set_surface_override_material(0, mat)
	obj.add_child(mi)

	# Collision
	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = data.size
	col.shape  = shape
	obj.add_child(col)

	obj.add_to_group("placed_objects")
	return obj
