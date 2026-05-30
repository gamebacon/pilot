class_name PlacedPiece
extends DamageableBody

const GRID_SIZE: float = 3.0

## Delay before the nav mesh is rebaked after a placement or destruction.
## Debounced so rapid successive events (e.g. building a wall row) only
## trigger one expensive bake at the end, not one per piece.
const NAV_REBAKE_DELAY: float = 0.4

var size:         Vector3 = Vector3(1.0, 1.0, 1.0)
var color:        Color   = Color(0.7, 0.46, 0.2)
var net_id:       int     = 0
var is_foundation: bool   = false
var blocker_priority = 0;

# ── Building piece identity ───────────────────────────────────────────────────
# Set from BuildingItemData at placement time.  Empty/0 for non-building items.

var piece_type: String = ""
var piece_tier: int    = 0

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

const SND_HIT := preload("res://audio/sfx/item_collide.mp3")

func _ready() -> void:
	bar_height = size.y + 0.4
	hit_sound  = SND_HIT
	add_to_group("placed_pieces")
	# All placed pieces join nav_static so the nav mesh knows about them:
	# • Foundations: horizontal top surface becomes a walkable nav region.
	# • Walls: vertical geometry is carved out of the nav mesh, forcing enemies
	#   to route around intact walls.  Destroying a wall → rebake → path opens.
	# All placed pieces are physical obstacles — both walls and foundations
	# must be reachable by the enemy blocker-fallback targeting system.
	# Foundations are also walkable surfaces (nav_static bakes their top face).
	add_to_group("nav_static")

	# add_to_group("enemy_blockers")

	if piece_type == "wall" or piece_type == "tower" or piece_type == "foundation":
		add_to_group("enemy_blockers")
		set_meta("blocker_priority", blocker_priority)

	_request_nav_rebake()
	super()

# ── Multiplayer sync ──────────────────────────────────────────────────────────

func _on_hp_changed(current: float, maximum: float) -> void:
	super(current, maximum)
	if NetworkManager.is_active():
		_rpc_hp_sync.rpc(current, maximum)

@rpc("authority", "call_remote", "unreliable")
func _rpc_hp_sync(current: float, maximum: float) -> void:
	damageable.show_hit(current, maximum)

func _on_destroyed() -> void:
	if NetworkManager.is_active():
		_rpc_destroy.rpc()
	else:
		_destroy_local()

@rpc("authority", "call_local", "reliable")
func _rpc_destroy() -> void:
	_destroy_local()

func _destroy_local() -> void:
	if is_foundation:
		_cascade_destroy_supported()
	var world: Node = get_tree().get_first_node_in_group("world")
	if world:
		world.unregister_piece(net_id)
	# Remove from nav_static before freeing so the rebake sees the gap.
	remove_from_group("nav_static")
	_request_nav_rebake()
	queue_free()

## Server-only: destroys all non-foundation placed nodes sitting on this foundation.
## Runs on the server so each node's _on_destroyed() fires exactly once, triggering
## its own RPC to sync removal (and loot scatter for chests) to all peers.
func _cascade_destroy_supported() -> void:
	if NetworkManager.is_active() and not multiplayer.is_server():
		return
	const Y_TOL:        float = 0.15
	const MAX_HEIGHT:   float = 4.0   # tallest placeable that can sit on a foundation
	var foundation_top_y: float  = global_position.y + size.y * 0.5
	var foundation_xz:    Vector2 = Vector2(global_position.x, global_position.z)
	var half_x: float = size.x * 0.5 + 0.5
	var half_z: float = size.z * 0.5 + 0.5
	var world: Node = get_tree().get_first_node_in_group("world")
	if not world: return
	var candidates: Array[Node3D] = world.get_all_placed_nodes()
	var to_destroy: Array[Node3D] = []
	for node: Node3D in candidates:
		if node == self: continue
		if node is PlacedPiece and (node as PlacedPiece).is_foundation: continue
		var node_xz: Vector2 = Vector2(node.global_position.x, node.global_position.z)
		if absf(node_xz.x - foundation_xz.x) >= half_x: continue
		if absf(node_xz.y - foundation_xz.y) >= half_z: continue
		var bottom_y: float
		if node is PlacedPiece:
			bottom_y = node.global_position.y - (node as PlacedPiece).size.y * 0.5
		else:
			# Scene-based placeables (chests, etc.): ghost is placed so its centre
			# is above the surface, so test the centre against a Y window instead.
			bottom_y = node.global_position.y - MAX_HEIGHT * 0.5
		if absf(bottom_y - foundation_top_y) < Y_TOL + MAX_HEIGHT * 0.5:
			to_destroy.append(node)
	for node: Node3D in to_destroy:
		if is_instance_valid(node) and node.has_method("_on_destroyed"):
			node._on_destroyed()

## Schedules a nav-mesh rebake after NAV_REBAKE_DELAY seconds.
## Debounced via metadata on the NavigationRegion3D node: if a rebake is
## already pending the timer is left alone (it will fire for all queued
## changes at once).
func _request_nav_rebake() -> void:
	var nav: NavigationRegion3D = get_tree().get_first_node_in_group("nav_region") as NavigationRegion3D
	if not nav:
		return
	if nav.has_meta("rebake_pending"):
		return
	nav.set_meta("rebake_pending", true)
	get_tree().create_timer(NAV_REBAKE_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(nav):
			nav.remove_meta("rebake_pending")
			nav.bake_navigation_mesh()
	)
