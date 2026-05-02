extends RigidBody3D
class_name PhysicalItem

@export var item_data: ItemData

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var label: Label3D = $Label3D

func _ready() -> void:
	if item_data:
		_apply_item_data()

func _apply_item_data() -> void:
	# Mesh
	var box := BoxMesh.new()
	box.size = item_data.size
	mesh_instance.mesh = box

	# Material / color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_data.color
	if item_data.color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat

	# Collision
	var shape := BoxShape3D.new()
	shape.size = item_data.size
	collision_shape.shape = shape

	# Physics
	mass = item_data.mass

	# Label
	label.text = item_data.display_name

func interact(player: Node) -> void:
	player.pick_up(self)

func get_interact_hint(_player: Node) -> String:
	var n: String = item_data.display_name if item_data else "item"
	return "[E]  Pick up  %s" % n
