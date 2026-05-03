extends Node

@export var player_path: NodePath

# How close (metres) a ghost socket must be to a placed socket to snap
const SNAP_DIST := 0.3
# Degrees rotated per key press
const ROT_STEP  := 22.5
# Max ray distance when aiming
const MAX_REACH := 15.0

# Base wood colour for placed planks (slight per-plank tonal variation is added on place)
const COLOR_WOOD := Color(0.70, 0.46, 0.20)

var _player: CharacterBody3D
var _active    := false
var _snapping  := false
var _planks_root: Node3D

@onready var _ghost: MeshInstance3D = $Ghost
@onready var _label: Label          = $UI/Label

var _mat_free: StandardMaterial3D  # semi-transparent wood — no snap
var _mat_snap: StandardMaterial3D  # green tint — snap active

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_player = get_node(player_path)


	# Container for all placed planks in the scene
	_planks_root      = Node3D.new()
	_planks_root.name = "PlacedPlanks"

	# Use get_parent() or the node itself as the anchor, not current_scene
	get_parent().call_deferred("add_child", _planks_root)

	_mat_free = _ghost_mat(Color(COLOR_WOOD.r, COLOR_WOOD.g, COLOR_WOOD.b, 0.50))
	_mat_snap = _ghost_mat(Color(0.25, 0.90, 0.35, 0.55))

	var box  := BoxMesh.new()
	box.size = Vector3(PlacedPlank.PLANK_LENGTH, PlacedPlank.PLANK_HEIGHT, PlacedPlank.PLANK_WIDTH)
	_ghost.mesh             = box
	_ghost.material_override = _mat_free
	_ghost.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.hide()

	_label.text = (
		"PLANK MODE    [LMB] Place    [RMB / B] Exit\n"
		+ "[R / Shift+R] Yaw    [X / Shift+X] Pitch    [Z / Shift+Z] Roll"
	)
	_label.hide()

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if _active: _exit()
		else:       _enter()
		return

	if not _active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var sign := -1.0 if event.shift_pressed else 1.0
		match event.keycode:
			KEY_R: _ghost.rotation_degrees.y += ROT_STEP * sign
			KEY_X: _ghost.rotation_degrees.x += ROT_STEP * sign
			KEY_Z: _ghost.rotation_degrees.z += ROT_STEP * sign

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:  _place()
			MOUSE_BUTTON_RIGHT: _exit()

# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _active:
		_update_ghost()

func _update_ghost() -> void:
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var from  := camera.global_position
	var dir   := -camera.global_transform.basis.z   # forward
	var to    := from + dir * MAX_REACH

	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit   := space.intersect_ray(query)

	if hit.is_empty():
		_ghost.hide()
		return

	_ghost.show()
	# Sit the plank on top of whatever surface was hit
	var basis := _ghost.global_transform.basis
	# Project each local half-extent onto the surface normal
	var half_extent: float = (
		abs(basis.x.dot(hit.normal)) * PlacedPlank.HL +
		abs(basis.y.dot(hit.normal)) * PlacedPlank.HH +
		abs(basis.z.dot(hit.normal)) * PlacedPlank.HW
	)
	_ghost.global_position = hit.position + hit.normal * half_extent
	# _ghost.global_position = hit.position + hit.normal * PlacedPlank.HH

	# Snap: translate ghost so the closest socket pair aligns — rotation unchanged
	var offset := _find_snap_offset()
	_snapping   = offset != Vector3.ZERO
	if _snapping:
		_ghost.global_position  += offset
		_ghost.material_override = _mat_snap
	else:
		_ghost.material_override = _mat_free

# ── Snap logic ───────────────────────────────────────────────────────────────

func _find_snap_offset() -> Vector3:
	var ghost_sockets := _ghost_world_sockets()
	var best_dist     := SNAP_DIST
	var best_offset   := Vector3.ZERO

	for plank in get_tree().get_nodes_in_group("placed_planks"):
		for placed_pos: Vector3 in plank.get_world_sockets():
			for ghost_pos: Vector3 in ghost_sockets:
				var d := ghost_pos.distance_to(placed_pos)
				if d < best_dist:
					best_dist   = d
					best_offset = placed_pos - ghost_pos

	return best_offset

func _ghost_world_sockets() -> Array:
	var result := []
	for local_pos: Vector3 in PlacedPlank.LOCAL_SOCKETS:
		result.append(_ghost.global_transform * local_pos)
	return result

# ── Placement ────────────────────────────────────────────────────────────────
func _place() -> void:
	if not _ghost.visible:
		return

	var plank := PlacedPlank.new()
	_planks_root.add_child(plank)

	# Capture transform NOW (before any deferred frame changes it)
	var t := _ghost.global_transform
	plank.set_deferred("global_transform", t)

	var shape := BoxShape3D.new()
	shape.size = Vector3(PlacedPlank.PLANK_LENGTH, PlacedPlank.PLANK_HEIGHT, PlacedPlank.PLANK_WIDTH)
	var col := CollisionShape3D.new()
	col.shape = shape
	plank.add_child(col)

	var box := BoxMesh.new()
	box.size = Vector3(PlacedPlank.PLANK_LENGTH, PlacedPlank.PLANK_HEIGHT, PlacedPlank.PLANK_WIDTH)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _wood_mat()
	plank.add_child(mi)

	print("plank global pos: ", plank.global_position)
	print("ghost global pos: ", _ghost.global_position)

# ── Mode enter / exit ─────────────────────────────────────────────────────────

func _enter() -> void:
	_active = true
	_ghost.show()
	_label.show()

func _exit() -> void:
	_active = false
	_ghost.hide()
	_label.hide()

# ── Material helpers ──────────────────────────────────────────────────────────

func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _wood_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var v   := randf_range(-0.07, 0.07)
	mat.albedo_color = Color(
		clampf(COLOR_WOOD.r + v,        0.0, 1.0),
		clampf(COLOR_WOOD.g + v * 0.55, 0.0, 1.0),
		clampf(COLOR_WOOD.b + v * 0.30, 0.0, 1.0)
	)
	return mat
