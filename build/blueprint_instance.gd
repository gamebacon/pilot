extends Node3D
class_name BlueprintInstance

const SNAP_RADIUS := 0.5  # max XZ distance to snap to a slot

var blueprint_data: BlueprintData = null
var current_phase: int = 0
var filled: Dictionary = {}      # slot_index -> true
var slot_zones: Dictionary = {}  # slot_index -> MeshInstance3D
var zone_phases: Dictionary = {} # slot_index -> phase_idx

func activate(data: BlueprintData) -> void:
	blueprint_data = data
	current_phase  = 0
	_build_zones()

# ── Zone construction ─────────────────────────────────────────────────────────

func _build_zones() -> void:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		var item := _load_item(slot.required_item_id)
		var size: Vector3 = item.size if item else Vector3.ONE

		var mi  := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mi.mesh = box

		var base: Color = item.color if item else Color(0.7, 0.5, 0.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color     = Color(base.r, base.g, base.b, 0.38)
		mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position          = slot.position
		mi.rotation_degrees  = slot.rotation_deg
		mi.visible           = (int(slot.phase) == current_phase)
		add_child(mi)

		slot_zones[i]  = mi
		zone_phases[i] = int(slot.phase)

func _load_item(item_id: String) -> ItemData:
	var path := "res://items/resources/" + item_id + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as ItemData
	return null

# ── Slot lookup ───────────────────────────────────────────────────────────────

# Returns [BlueprintSlot, index] of the nearest unfilled active slot within
# SNAP_RADIUS in the XZ plane, or [] if none found.
func get_nearest_active_slot(local_pos: Vector3) -> Array:
	var best_dist := SNAP_RADIUS
	var best_slot: BlueprintSlot = null
	var best_idx  := -1
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if int(slot.phase) != current_phase:    continue
		if filled.get(i, false):                continue
		var dx := local_pos.x - slot.position.x
		var dz := local_pos.z - slot.position.z
		var d  := sqrt(dx * dx + dz * dz)
		if d < best_dist:
			best_dist = d
			best_slot = slot
			best_idx  = i
	if best_slot:
		return [best_slot, best_idx]
	return []

# ── Slot filling ──────────────────────────────────────────────────────────────

func fill_slot(index: int) -> void:
	filled[index] = true
	var mi: MeshInstance3D = slot_zones.get(index)
	if mi:
		mi.hide()
	_check_phase_advance()

func _check_phase_advance() -> void:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if int(slot.phase) == current_phase and not filled.get(i, false):
			return
	current_phase += 1
	for i in slot_zones:
		if zone_phases[i] == current_phase:
			slot_zones[i].show()

func is_complete() -> bool:
	return filled.size() == blueprint_data.slots.size()
