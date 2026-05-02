extends Node3D
class_name BlueprintInstance

var blueprint_data: BlueprintData = null
var current_phase: int = 0
var filled: Dictionary = {}       # slot_index (int) -> true
var ghost_nodes: Dictionary = {}  # slot_index (int) -> MeshInstance3D

# Semi-transparent ghost colors per phase
const PHASE_COLORS: Array[Color] = [
	Color(0.9, 0.70, 0.30, 0.38),  # 0 STRUCTURE — warm wood
	Color(0.25, 0.18, 0.10, 0.38), # 1 ROOFING   — dark timber
	Color(0.85, 0.85, 0.85, 0.38), # 2 INTERIOR  — light tile
]

# Ghost visual size by PlacementType int (FLOOR=0, WALL=1, ROOF=2)
const GHOST_SIZE: Array[Vector3] = [
	Vector3(0.92, 0.05, 0.92),  # FLOOR
	Vector3(0.92, 0.92, 0.12),  # WALL
	Vector3(0.92, 0.05, 0.92),  # ROOF
]

# Ghost Y centre relative to plot surface, by PlacementType int
const GHOST_Y: Array[float] = [
	0.025,  # FLOOR
	0.50,   # WALL  (mid-point of 1 m wall)
	1.05,   # ROOF  (just above walls)
]

func activate(data: BlueprintData) -> void:
	blueprint_data = data
	current_phase = 0
	_build_ghosts()

func _build_ghosts() -> void:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		var ghost := _make_ghost(slot)
		ghost_nodes[i] = ghost
		add_child(ghost)
		ghost.visible = (int(slot.phase) == current_phase)

func _make_ghost(slot: BlueprintSlot) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	var pt: int = int(slot.placement_type)
	box.size = GHOST_SIZE[pt]
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	var phase_idx: int = clampi(int(slot.phase), 0, PHASE_COLORS.size() - 1)
	mat.albedo_color = PHASE_COLORS[phase_idx]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Position and rotation in local space — blueprint_instance sits at the plot's origin
	mesh_inst.position = Vector3(
		(slot.cell.x + 0.5),
		GHOST_Y[pt],
		(slot.cell.y + 0.5)
	)
	mesh_inst.rotation_degrees.y = slot.rotation_y_deg
	return mesh_inst

# Returns [BlueprintSlot, slot_index] for the active phase at this cell, or []
func get_active_slot_at(cell: Vector2i) -> Array:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if slot.cell == cell and int(slot.phase) == current_phase and not filled.get(i, false):
			return [slot, i]
	return []

func fill_slot(index: int) -> void:
	filled[index] = true
	if ghost_nodes.has(index):
		ghost_nodes[index].hide()
	_check_phase_advance()

func _check_phase_advance() -> void:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if int(slot.phase) == current_phase and not filled.get(i, false):
			return
	# All slots in this phase filled — advance
	current_phase += 1
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if int(slot.phase) == current_phase and not filled.get(i, false):
			ghost_nodes[i].show()

func is_complete() -> bool:
	return filled.size() == blueprint_data.slots.size()
