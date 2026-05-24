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

var max_hp:     int = 0   # 0 = indestructible (non-building placeables like chests)
var current_hp: int = 0

# ── Factory ───────────────────────────────────────────────────────────────────

## [p_scene] is an optional PackedScene (e.g. imported GLB) used as the visual.
## When provided the scene is instantiated as a child; the tinted box is skipped.
## Collision always uses a BoxShape3D from [p_size] regardless of scene.
## [p_visual_offset] is added to the default bottom-face alignment so that models
## with a non-bottom-centre pivot can be corrected without re-exporting from Blender.
static func build(p_size: Vector3, p_color: Color, p_scene: PackedScene = null, p_visual_offset: Vector3 = Vector3.ZERO) -> PlacedPiece:
	var piece        := PlacedPiece.new()
	piece.size        = p_size
	piece.color       = p_color

	var shape        := BoxShape3D.new()
	shape.size        = p_size
	var col          := CollisionShape3D.new()
	col.shape         = shape
	piece.add_child(col)

	if p_scene:
		# The PlacedPiece origin is at the bounding-box centre.  Shifting the
		# visual down by half-height aligns its root with the bottom face, which
		# is correct when the GLB origin is at the mesh's bottom-centre.
		# p_visual_offset lets callers compensate for a different pivot.
		var visual: Node3D = p_scene.instantiate() as Node3D
		visual.position    = Vector3(0.0, -p_size.y * 0.5, 0.0) + p_visual_offset
		piece.add_child(visual)
	else:
		var box          := BoxMesh.new()
		box.size          = p_size
		var mi           := MeshInstance3D.new()
		mi.mesh            = box
		mi.material_override = _tinted_mat(p_color)
		piece.add_child(mi)

	return piece

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

# ── Damage / destruction ──────────────────────────────────────────────────────

## Apply `amount` damage. Returns true if the piece was destroyed.
## No-op and returns false for indestructible pieces (max_hp == 0).
func take_damage(amount: int) -> bool:
	if max_hp == 0:
		return false
	current_hp = max(0, current_hp - amount)
	if current_hp <= 0:
		queue_free()
		return true
	return false
