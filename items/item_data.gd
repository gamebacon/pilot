extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var price: int = 10
@export var description: String = ""

# Physical appearance
@export var color: Color = Color(0.75, 0.52, 0.22, 1.0)
@export var size: Vector3 = Vector3(0.4, 0.1, 1.2)

# Physics
@export var mass: float = 2.0

# How many the player can carry at once (e.g. stones stack, glass doesn't)
@export var carry_stack: int = 1

# The scene to place during building (assigned later when build system is ready)
@export var build_scene: PackedScene
