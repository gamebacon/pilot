class_name BuildingSlots

## Typed slot system for the building grid.
##
## Every slot carries a local Transform3D so snapping resolves both position
## AND orientation in one step:
##
##   ghost_world_T = target_slot_world_T * ghost_base_local_T.inverse()
##
## Slot types and their compatible pairings:
##   "wall_mount"  ←→  "wall_base"      (foundation / tower receives a wall)
##   "stack_mount" ←→  "stack_base"     (wall top receives a parapet or upper wall — future)
##
## Foundations do NOT use slots — they snap to a world grid instead.

# ── Slot basis helpers ────────────────────────────────────────────────────────

## Basis for a slot whose outward face points in `dir`.
## Y is always world-up so placed pieces stay level.
static func _face_basis(dir: Vector3) -> Basis:
	return Basis.looking_at(dir, Vector3.UP)

# ── Wall-mount slots (where a wall can connect TO this piece) ─────────────────

## Returns the four wall-mount slots for a piece with half-extents `h`.
## Slots sit at the midpoint of each vertical base edge, facing outward.
static func wall_mounts(h: Vector3) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for dir: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1),
						  Vector3(1, 0,  0), Vector3(-1, 0, 0)]:
		var pos := Vector3(dir.x * h.x, h.y, dir.z * h.z)
		slots.append({
			"type":      "wall_mount",
			"transform": Transform3D(_face_basis(dir), pos),
		})
	return slots

# ── Base slot (how this piece connects to a wall_mount) ──────────────────────

## The single base slot for a wall or parapet: bottom-centre, no rotation.
## Using identity basis means the ghost inherits the target slot's orientation
## exactly when the snap formula is applied.
static func wall_base(h: Vector3) -> Dictionary:
	return {
		"type":      "wall_base",
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, -h.y, 0)),
	}

# ── Per-piece-type accessors ──────────────────────────────────────────────────

## Slots on an existing PlacedPiece that other pieces may connect to.
static func mount_slots_for(piece_type: String, size: Vector3) -> Array[Dictionary]:
	var h := size * 0.5
	match piece_type:
		"foundation":
			return wall_mounts(h)
		"tower":
			return wall_mounts(h)
		_:
			return []

## The base slot used by the ghost when snapping onto a mount slot.
## Returns an empty Dictionary if this piece_type doesn't snap via slots.
static func base_slot_for(piece_type: String, size: Vector3) -> Dictionary:
	var h := size * 0.5
	match piece_type:
		"wall":
			return wall_base(h)
		_:
			return {}

## Whether two slot types are compatible for snapping.
static func compatible(a: String, b: String) -> bool:
	return (a == "wall_mount" and b == "wall_base") \
		or (a == "wall_base"  and b == "wall_mount")
