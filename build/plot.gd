extends StaticBody3D
class_name Plot

var blueprint_instances: Array[BlueprintInstance] = []

var _player:    Player   = null
var _ghost_root: Node3D  = null
var _ghost_data: BlueprintData = null
var _ghost_yrot: float   = 0.0

const GHOST_COLOR  := Color(0.45, 0.65, 1.0, 0.20)
const GRID_SIZE    := 0.5   # metres — ghost snaps to this grid on the plot surface
const MAX_LOOK_DIST := 20.0 # metres — beyond this the ghost hides
const PLOT_RADIUS  := 12.0  # metres — hide ghost if aim is far from plot centre

func _ready() -> void:
	add_to_group("plot")
	# Ensure PlacedPieces container exists
	if not has_node("PlacedPieces"):
		var n := Node3D.new()
		n.name = "PlacedPieces"
		add_child(n)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return
	_update_ghost()

func _update_ghost() -> void:
	var bp_item := _held_blueprint()
	if not bp_item:
		_hide_ghost()
		return

	var hit_pos = _look_hit_on_surface()
	if hit_pos == null:
		if _ghost_root:
			_ghost_root.visible = false
		return

	var data: BlueprintData = bp_item.item_data.blueprint_data
	if _ghost_data != data:
		_rebuild_ghost(data)

	_ghost_root.global_position    = _snap(hit_pos)
	_ghost_root.rotation_degrees.y = _ghost_yrot
	_ghost_root.visible            = true

# ── Ghost construction ────────────────────────────────────────────────────────

func _rebuild_ghost(data: BlueprintData) -> void:
	if _ghost_root:
		_ghost_root.queue_free()
	_ghost_root = Node3D.new()
	add_child(_ghost_root)
	_ghost_data = data

	var mat := StandardMaterial3D.new()
	mat.albedo_color = GHOST_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED

	for slot: BlueprintSlot in data.slots:
		var item := ItemRegistry.get_item(slot.required_item_id)
		var size := item.size if item else Vector3.ONE
		var box  := BoxMesh.new()
		box.size = size
		var mi   := MeshInstance3D.new()
		mi.mesh              = box
		mi.material_override = mat
		mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position          = slot.position
		mi.rotation_degrees  = slot.rotation_deg
		_ghost_root.add_child(mi)

func _hide_ghost() -> void:
	if _ghost_root:
		_ghost_root.queue_free()
		_ghost_root = null
	_ghost_data = null

# ── Ghost helpers ─────────────────────────────────────────────────────────────

# Returns the world-space point where the player's look ray hits the plot plane,
# or null if the aim is too far away or pointing above the horizon.
func _look_hit_on_surface() -> Variant:
	var cam    := _player.camera
	var origin := cam.global_position
	var dir    := -cam.global_transform.basis.z.normalized()
	var plane  := Plane(Vector3.UP, global_position.y)
	var hit    = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	if origin.distance_to(hit) > MAX_LOOK_DIST:
		return null
	var flat_dist := Vector2(hit.x - global_position.x, hit.z - global_position.z).length()
	if flat_dist > PLOT_RADIUS:
		return null
	return hit

# Snap a world-space position to the plot grid, locked to the plot's surface Y.
func _snap(world_pos: Vector3) -> Vector3:
	var local := to_local(world_pos)
	local.x    = round(local.x / GRID_SIZE) * GRID_SIZE
	local.z    = round(local.z / GRID_SIZE) * GRID_SIZE
	local.y    = 0.0
	return to_global(local)

func _held_blueprint() -> PhysicalItem:
	if not _player:
		return null
	for item: PhysicalItem in _player.inventory.items:
		if item.item_data and item.item_data.is_blueprint and item.item_data.blueprint_data:
			return item
	return null

# ── Rotation input ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (_ghost_root and _ghost_root.visible):
		return
	if event is InputEventKey and not event.echo:
		if event.is_action_pressed("rotate_y"):
			var sign := -1.0 if event.shift_pressed else 1.0
			_ghost_yrot += 90.0 * sign

# ── Interaction ───────────────────────────────────────────────────────────────

func get_interact_hint(_player: Node) -> String:
	if _ghost_root and _ghost_root.visible and _ghost_data:
		var place := InputHelper.action_label("interact")
		var rot   := InputHelper.action_label("rotate_y")
		return "%s  Place Blueprint    %s / Shift+%s  Rotate" % [place, rot, rot]
	return ""

func interact(player: Node) -> void:
	var bp_item := _held_blueprint()
	if not bp_item or not _ghost_data or not (_ghost_root and _ghost_root.visible):
		return
	_place_blueprint(_ghost_data, _ghost_root.global_position, _ghost_yrot)
	player.inventory.remove(bp_item)
	bp_item.queue_free()
	# Reset rotation for next placement
	_ghost_yrot = 0.0

func _place_blueprint(data: BlueprintData, world_pos: Vector3, y_rot: float) -> void:
	var scene: PackedScene = preload("res://build/blueprint_instance.tscn")
	var instance           := scene.instantiate() as BlueprintInstance
	add_child(instance)
	instance.global_position    = world_pos
	instance.rotation_degrees.y = y_rot
	instance.activate(data)
	blueprint_instances.append(instance)
