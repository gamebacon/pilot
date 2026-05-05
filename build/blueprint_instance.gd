extends Node3D
class_name BlueprintInstance

var blueprint_data: BlueprintData = null
var current_phase: int = 0
var filled: Dictionary = {}      # slot_index -> true
var slot_zones: Dictionary = {}  # slot_index -> zone_mesh_index
var zone_meshes: Array[MeshInstance3D] = []
var zone_phases: Array[int] = []

func activate(data: BlueprintData) -> void:
	blueprint_data = data
	current_phase = 0
	_build_zones()

# ── Zone construction ────────────────────────────────────────────────────────

func _build_zones() -> void:
	# Group slot indices by (phase, placement_type)
	var groups: Dictionary = {}
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		var key := Vector2i(int(slot.phase), int(slot.placement_type))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)

	for key in groups:
		var phase_idx: int = key.x
		var pt: int = key.y
		var indices: Array = groups[key]
		if pt == BlueprintSlot.PlacementType.WALL:
			_build_wall_zones(indices, phase_idx)
		else:
			_build_slab_zone(indices, phase_idx, pt)

# Floor and roof: one flat slab covering the bounding box of all cells
func _build_slab_zone(indices: Array, phase_idx: int, pt: int) -> void:
	var min_x := 9999;  var min_z := 9999
	var max_x := -9999; var max_z := -9999
	var item_id: String = blueprint_data.slots[indices[0]].required_item_id
	for idx in indices:
		var c: Vector2i = blueprint_data.slots[idx].cell
		min_x = mini(min_x, c.x); min_z = mini(min_z, c.y)
		max_x = maxi(max_x, c.x); max_z = maxi(max_z, c.y)

	var size := Vector3((max_x - min_x + 1) * 0.98, 0.05, (max_z - min_z + 1) * 0.98)
	var y    := 0.025 if pt == BlueprintSlot.PlacementType.FLOOR else 2.30
	var pos  := Vector3((min_x + max_x + 1) * 0.5, y, (min_z + max_z + 1) * 0.5)
	var zone_idx := _add_zone(size, pos, item_id, phase_idx)
	for idx in indices:
		slot_zones[idx] = zone_idx

# Walls: split into connected runs, orient each run correctly
func _build_wall_zones(indices: Array, phase_idx: int) -> void:
	var visited: Dictionary = {}
	for start_idx in indices:
		if visited.has(start_idx):
			continue
		# BFS — find connected wall run
		var component: Array = []
		var queue := [start_idx]
		visited[start_idx] = true
		while not queue.is_empty():
			var curr: int = queue.pop_front()
			component.append(curr)
			var cc: Vector2i = blueprint_data.slots[curr].cell
			for other in indices:
				if visited.has(other): continue
				var oc: Vector2i = blueprint_data.slots[other].cell
				if abs(oc.x - cc.x) + abs(oc.y - cc.y) == 1:
					visited[other] = true
					queue.append(other)

		var min_x := 9999;  var min_z := 9999
		var max_x := -9999; var max_z := -9999
		var item_id: String = blueprint_data.slots[component[0]].required_item_id
		for idx in component:
			var c: Vector2i = blueprint_data.slots[idx].cell
			min_x = mini(min_x, c.x); min_z = mini(min_z, c.y)
			max_x = maxi(max_x, c.x); max_z = maxi(max_z, c.y)

		var span_x := max_x - min_x + 1
		var span_z := max_z - min_z + 1
		# Orient panel to face inward — thin in the short axis
		var size: Vector3
		if span_x >= span_z:  # horizontal run along X
			size = Vector3(span_x * 1.0, 2.20, 0.08)
		else:                  # vertical run along Z
			size = Vector3(0.08, 2.20, span_z * 1.0)

		var pos := Vector3((min_x + max_x + 1) * 0.5, 1.10, (min_z + max_z + 1) * 0.5)
		var zone_idx := _add_zone(size, pos, item_id, phase_idx)
		for idx in component:
			slot_zones[idx] = zone_idx

func _add_zone(size: Vector3, pos: Vector3, item_id: String, phase_idx: int) -> int:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box

	var item_res := load("res://items/resources/" + item_id + ".tres") as ItemData
	var base: Color = item_res.color if item_res else Color(0.7, 0.5, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color     = Color(base.r, base.g, base.b, 0.38)
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position          = pos
	mi.visible           = (phase_idx == current_phase)
	add_child(mi)

	zone_meshes.append(mi)
	zone_phases.append(phase_idx)
	return zone_meshes.size() - 1

# ── Slot access ───────────────────────────────────────────────────────────────

func get_active_slot_at(cell: Vector2i) -> Array:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if slot.cell == cell and int(slot.phase) == current_phase and not filled.get(i, false):
			return [slot, i]
	return []

func fill_slot(index: int) -> void:
	filled[index] = true
	# Hide zone mesh when all its slots are filled
	var zone_idx: int = slot_zones.get(index, -1)
	if zone_idx >= 0:
		var all_done := true
		for si in slot_zones:
			if slot_zones[si] == zone_idx and not filled.get(si, false):
				all_done = false
				break
		if all_done:
			zone_meshes[zone_idx].hide()
	_check_phase_advance()

func _check_phase_advance() -> void:
	for i in range(blueprint_data.slots.size()):
		var slot: BlueprintSlot = blueprint_data.slots[i]
		if int(slot.phase) == current_phase and not filled.get(i, false):
			return
	current_phase += 1
	for i in range(zone_meshes.size()):
		if zone_phases[i] == current_phase:
			zone_meshes[i].show()

func is_complete() -> bool:
	return filled.size() == blueprint_data.slots.size()
