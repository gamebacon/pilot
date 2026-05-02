extends Resource
class_name BlueprintSlot

enum PlacementType { FLOOR = 0, WALL = 1, ROOF = 2 }
enum Phase { STRUCTURE = 0, ROOFING = 1, INTERIOR = 2 }

@export var cell: Vector2i = Vector2i(0, 0)
@export var placement_type: PlacementType = PlacementType.FLOOR
@export var required_item_id: String = "wood_plank"
@export var phase: Phase = Phase.STRUCTURE
@export var rotation_y_deg: float = 0.0  # 0 = N/S wall, 90 = E/W wall
