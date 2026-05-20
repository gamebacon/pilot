class_name PlaceableItemData
extends ItemData

## Path to the scene to instantiate when this item is placed via build mode.
## Stored as a String so the resource doesn't eagerly load the scene at startup.
@export var placement_scene_path: String = ""

func get_placement_scene() -> PackedScene:
	if placement_scene_path.is_empty():
		return null
	return load(placement_scene_path) as PackedScene
