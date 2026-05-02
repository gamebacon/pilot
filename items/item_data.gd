extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var price: int = 10
@export var description: String = ""
@export var icon: Texture2D
# The scene to spawn when this item is placed during building
@export var build_scene: PackedScene
