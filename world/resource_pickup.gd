extends StaticBody3D
class_name ResourcePickup

## Interactable resource pickup — stone or wood.
## Created programmatically by world_generator (stones) and harvestable_tree (logs).

var resource_type: String = "stone"

func get_interact_hint(_player: Node) -> String:
	return "Pick up " + resource_type.capitalize()

func interact(player: Node) -> void:
	player.add_resource(resource_type, 1)
	queue_free()

# ── Factory ───────────────────────────────────────────────────────────────────
# Call this static method to build the full node (collision + mesh).

static func make(type: String) -> StaticBody3D:
	var script := load("res://world/resource_pickup.gd")
	var body   := StaticBody3D.new()
	body.set_script(script)
	body.set("resource_type", type)

	var col := CollisionShape3D.new()
	var mi  := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()

	if type == "stone":
		var shape   := SphereShape3D.new()
		shape.radius = 0.24
		col.shape    = shape
		col.position = Vector3(0.0, 0.24, 0.0)

		var mesh   := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.40
		mi.mesh     = mesh
		mi.position = Vector3(0.0, 0.24, 0.0)
		mat.albedo_color = Color(0.52, 0.50, 0.46)
		mat.roughness    = 0.85
	else:  # wood log
		var shape    := BoxShape3D.new()
		shape.size   = Vector3(0.32, 0.20, 0.58)
		col.shape    = shape
		col.position = Vector3(0.0, 0.10, 0.0)

		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.30, 0.18, 0.55)
		mi.mesh   = mesh
		mi.position = Vector3(0.0, 0.09, 0.0)
		mat.albedo_color = Color(0.46, 0.28, 0.12)
		mat.roughness    = 0.90

	mi.set_surface_override_material(0, mat)
	body.add_child(col)
	body.add_child(mi)
	return body
