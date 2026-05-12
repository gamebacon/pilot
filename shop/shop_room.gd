extends Node3D
class_name ShopRoom

@export var width: float  = 8.0
@export var depth: float  = 12.0
@export var height: float = 3.0
@export var door_width: float = 4.0

@export var floor_color: Color = Color(0.60, 0.58, 0.55, 1)
@export var wall_color:  Color = Color(0.88, 0.86, 0.82, 1)

func _ready() -> void:
	_build()

func _build() -> void:
	var t := 0.2  # wall thickness
	var hw := width  / 2.0
	var sd := width  / 2.0  # same as hw, for clarity

	# Floor
	_panel(Vector3(width, t, depth), Vector3(0, -t * 0.5, -depth * 0.5), floor_color)
	# Ceiling
	_panel(Vector3(width, t, depth), Vector3(0, height + t * 0.5, -depth * 0.5), wall_color)
	# Back wall
	_panel(Vector3(width + t * 2, height, t), Vector3(0, height * 0.5, -depth - t * 0.5), wall_color)
	# Left wall
	_panel(Vector3(t, height, depth), Vector3(-hw - t * 0.5, height * 0.5, -depth * 0.5), wall_color)
	# Right wall
	_panel(Vector3(t, height, depth), Vector3(hw + t * 0.5, height * 0.5, -depth * 0.5), wall_color)
	# Front-left (beside door)
	var side_w := (width - door_width) * 0.5
	_panel(Vector3(side_w, height, t), Vector3(-hw + side_w * 0.5, height * 0.5, t * 0.5), wall_color)
	# Front-right
	_panel(Vector3(side_w, height, t), Vector3(hw - side_w * 0.5, height * 0.5, t * 0.5), wall_color)

func _panel(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# Double-sided so walls are visible from outside the building too.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	body.position = pos
	add_child(body)
