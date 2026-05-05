extends Resource
class_name BlueprintData

@export var display_name: String = ""
@export var phase_names: Array[String] = []
@export var slots: Array[BlueprintSlot] = []

# ── Item loading ──────────────────────────────────────────────────────────────

func _load_item(item_id: String) -> ItemData:
	var path := "res://items/resources/" + item_id + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as ItemData
	push_error("BlueprintData: missing item resource: " + item_id)
	return null

# ── Primitive slot builder ────────────────────────────────────────────────────

func _slot(pos: Vector3, type: BlueprintSlot.PlacementType, item_id: String,
		phase: int, rot: Vector3 = Vector3.ZERO) -> void:
	var s := BlueprintSlot.new()
	s.position       = pos
	s.rotation_deg   = rot
	s.placement_type = type
	s.required_item_id = item_id
	s.phase          = phase
	slots.append(s)

# ── Layout helpers — all positions derive from item.size, nothing hardcoded ───

# Pack a flat rectangular region with the item lying on its face.
# y_offset raises the layer (e.g. for benches above floor level).
func _fill_floor(x0: float, z0: float, x1: float, z1: float,
		item_id: String, phase: int, y_offset: float = 0.0) -> void:
	var item := _load_item(item_id)
	if not item: return
	var sx := item.size.x
	var sz := item.size.z
	var hy := item.size.y * 0.5
	var x := x0 + sx * 0.5
	while x <= x1 - sx * 0.5 + 0.001:
		var z := z0 + sz * 0.5
		while z <= z1 - sz * 0.5 + 0.001:
			_slot(Vector3(x, y_offset + hy, z),
				BlueprintSlot.PlacementType.FLOOR, item_id, phase)
			z += sz
		x += sx

# Wall running along the X axis (e.g. north or south wall), centred at z_pos.
# Items stand on end: item.size.x = step, item.size.z = wall height,
# item.size.y = wall thickness (faces in Z direction).
func _fill_wall_x(x0: float, x1: float, z_pos: float,
		item_id: String, phase: int) -> void:
	var item := _load_item(item_id)
	if not item: return
	var step   := item.size.x
	var height := item.size.z
	var x := x0 + step * 0.5
	while x <= x1 - step * 0.5 + 0.001:
		_slot(Vector3(x, height * 0.5, z_pos),
			BlueprintSlot.PlacementType.WALL, item_id, phase,
			Vector3(-90, 0, 0))
		x += step

# Wall running along the Z axis (e.g. west or east wall), centred at x_pos.
# After rotation the item.size.x step moves along Z; thickness faces in X.
func _fill_wall_z(z0: float, z1: float, x_pos: float,
		item_id: String, phase: int) -> void:
	var item := _load_item(item_id)
	if not item: return
	var step   := item.size.x
	var height := item.size.z
	var z := z0 + step * 0.5
	while z <= z1 - step * 0.5 + 0.001:
		_slot(Vector3(x_pos, height * 0.5, z),
			BlueprintSlot.PlacementType.WALL, item_id, phase,
			Vector3(-90, 90, 0))
		z += step

# Pack a flat roof region at height y_base (top of walls).
func _fill_roof(x0: float, z0: float, x1: float, z1: float, y_base: float,
		item_id: String, phase: int) -> void:
	var item := _load_item(item_id)
	if not item: return
	var sx := item.size.x
	var sz := item.size.z
	var hy := item.size.y * 0.5
	var x := x0 + sx * 0.5
	while x <= x1 - sx * 0.5 + 0.001:
		var z := z0 + sz * 0.5
		while z <= z1 - sz * 0.5 + 0.001:
			_slot(Vector3(x, y_base + hy, z),
				BlueprintSlot.PlacementType.ROOF, item_id, phase)
			z += sz
		x += sx
