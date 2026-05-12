extends Node3D
class_name ShopShelf

@export var shelf_width: float = 6.0
@export var shelf_color: Color = Color(0.68, 0.52, 0.32, 1)

func _ready() -> void:
	_build()

func _build() -> void:
	var w  := shelf_width
	var hw := w * 0.5

	# ── Centre divider (the backbone, visible from both sides) ─────────────────
	_panel(Vector3(w, 1.6, 0.06), Vector3(0, 0.8, 0.0), shelf_color)

	# ── End caps (full depth, both sides) ─────────────────────────────────────
	_panel(Vector3(0.06, 1.6, 0.88), Vector3(-hw + 0.03, 0.8, 0.0), shelf_color)
	_panel(Vector3(0.06, 1.6, 0.88), Vector3( hw - 0.03, 0.8, 0.0), shelf_color)

	# ── Front shelves (+Z side) ────────────────────────────────────────────────
	_panel(Vector3(w, 0.04, 0.40), Vector3(0, 0.80, 0.22), shelf_color)   # lower
	_panel(Vector3(w, 0.04, 0.40), Vector3(0, 1.40, 0.22), shelf_color)   # upper

	# ── Back shelves (−Z side) ─────────────────────────────────────────────────
	_panel(Vector3(w, 0.04, 0.40), Vector3(0, 0.80, -0.22), shelf_color)  # lower
	_panel(Vector3(w, 0.04, 0.40), Vector3(0, 1.40, -0.22), shelf_color)  # upper

	# ── Base skirting ─────────────────────────────────────────────────────────
	_panel(Vector3(w, 0.08, 0.88), Vector3(0, 0.04, 0.0), shelf_color)

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
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	body.position = pos
	add_child(body)
