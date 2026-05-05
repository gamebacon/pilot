extends Resource
class_name BlueprintSlot

enum PlacementType { FLOOR = 0, WALL = 1, ROOF = 2 }
enum Phase { STRUCTURE = 0, ROOFING = 1, INTERIOR = 2 }

@export var position: Vector3 = Vector3.ZERO    # local to plot origin
@export var rotation_deg: Vector3 = Vector3.ZERO
@export var placement_type: PlacementType = PlacementType.FLOOR
@export var required_item_id: String = ""
@export var phase: Phase = Phase.STRUCTURE
