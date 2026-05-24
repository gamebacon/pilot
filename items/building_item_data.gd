class_name BuildingItemData
extends ItemData

## Piece type — drives slot layout, grid behaviour, and enemy targeting.
## "foundation" | "wall" | "tower" | "parapet"
@export var piece_type: String = ""

## Material tier (1 = wood, 2 = wood solid, 3 = stone).
## Determines HP, craft cost, and which visual scene is used.
## Upgrading between tiers is not yet implemented — field is here for future use.
@export var piece_tier: int = 1

## Hit points when freshly placed.
@export var piece_hp: int = 100

## Item id of the next-tier variant (empty = already max tier).
## Reserved for the upgrade system — not read at runtime yet.
@export var upgrade_to: String = ""

## Optional scene (e.g. imported GLB) used as the visual for the placed piece
## and ghost preview. Leave empty to fall back to a plain box of [size].
## Collision always uses a BoxShape3D derived from [size] regardless of this.
@export var mesh_scene: PackedScene = null

## Additive offset applied to the mesh visual inside the placed piece (and ghost).
## The default places the mesh root at the bottom face of the collision box,
## which is correct when the GLB origin is at the mesh's bottom-centre (Blender:
## Object > Set Origin > Origin to Geometry, then snap to bottom).
## If your model's origin is at its geometric centre, set this to
## Vector3(0, size.y * 0.5, 0) to raise the visual back to the right height.
@export var visual_offset: Vector3 = Vector3.ZERO
