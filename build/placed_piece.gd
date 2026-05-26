class_name PlacedPiece
extends StaticBody3D

const GRID_SIZE: float = 3.0

var size:         Vector3 = Vector3(1.0, 1.0, 1.0)
var color:        Color   = Color(0.7, 0.46, 0.2)
var net_id:       int     = 0
var is_foundation: bool   = false

# ── Building piece identity ───────────────────────────────────────────────────
# Set from BuildingItemData at placement time.  Empty/0 for non-building items.

var piece_type: String = ""
var piece_tier: int    = 0

var max_hp: int = 0   # 0 = indestructible (non-building placeables like chests)
var health: HealthComponent = null

# ── Factory ───────────────────────────────────────────────────────────────────

## [p_scene] is an optional PackedScene (e.g. imported GLB) used as the visual.
## When provided the scene is instantiated as a child; the tinted box is skipped.
## Collision is a trimesh derived from the mesh when a scene is given, otherwise
## a BoxShape3D sized from [p_size].
## Assumes the GLB origin is at the mesh's bottom-centre (Apply Transforms in
## Blender on export). Any intentional XZ offset from the origin in Blender is
## preserved as-is — Godot treats your origin as the piece reference point.
## [p_visual_offset] is an optional additive correction on top of that.
static func build(p_size: Vector3, p_color: Color, p_scene: PackedScene = null, p_visual_offset: Vector3 = Vector3.ZERO) -> PlacedPiece:
	var piece        := PlacedPiece.new()
	piece.size        = p_size
	piece.color       = p_color

	var col := CollisionShape3D.new()
	piece.add_child(col)

	if p_scene:
		var visual: Node3D = p_scene.instantiate() as Node3D
		piece.add_child(visual)

		# Piece origin sits at the collision box centre.  Shift the visual down
		# by half-height so a bottom-origin mesh spans the full box correctly.
		# Any XZ displacement baked into the GLB (set in Blender) is kept intact.
		visual.position = Vector3(0.0, -p_size.y * 0.5, 0.0) + p_visual_offset

		# Trimesh collision — equivalent of Unity's MeshCollider.
		# Only valid on StaticBody3D, which PlacedPiece already is.
		# Call _node_offset_from while visual.position is still zero so the
		# result is the mi offset within the visual subtree only.
		var mi: MeshInstance3D = _find_mesh_instance(visual)
		if mi and mi.mesh:
			var mi_in_visual: Vector3 = _subtree_offset(mi, visual)
			col.position = visual.position + mi_in_visual
			col.shape    = mi.mesh.create_trimesh_shape()
		else:
			var box_shape    := BoxShape3D.new()
			box_shape.size    = p_size
			col.shape         = box_shape
	else:
		# No scene — plain tinted box mesh with matching box collider.
		var box_shape        := BoxShape3D.new()
		box_shape.size        = p_size
		col.shape             = box_shape

		var box              := BoxMesh.new()
		box.size              = p_size
		var mi               := MeshInstance3D.new()
		mi.mesh               = box
		mi.material_override  = _tinted_mat(p_color)
		piece.add_child(mi)

	return piece

static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found:
			return found
	return null

## Accumulated position of [target] relative to [root] (not including root).
## Use this to find where a nested MeshInstance3D sits within its parent scene.
static func _subtree_offset(target: Node3D, root: Node3D) -> Vector3:
	var offset:  Vector3 = Vector3.ZERO
	var current: Node    = target
	while current != root and current != null:
		offset  += (current as Node3D).position
		current  = current.get_parent()
	return offset

static func _tinted_mat(base: Color) -> StandardMaterial3D:
	var mat    := StandardMaterial3D.new()
	var v      := randf_range(-0.07, 0.07)
	mat.albedo_color = Color(
		clampf(base.r + v,        0.0, 1.0),
		clampf(base.g + v * 0.55, 0.0, 1.0),
		clampf(base.b + v * 0.30, 0.0, 1.0),
		base.a,
	)
	return mat

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("placed_pieces")
	if max_hp > 0:
		health = HealthComponent.new()
		add_child(health)
		health.setup(float(max_hp))

# ── Damage / destruction ──────────────────────────────────────────────────────

## Apply `amount` damage. Returns true if the piece was destroyed.
## No-op and returns false for indestructible pieces (max_hp == 0).
func take_damage(amount: float) -> bool:
	if not health: return false
	health.take_damage(amount)
	if health.is_dead():
		queue_free()
		return true
	return false
