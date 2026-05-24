extends Resource
class_name OreData

## Data resource that defines one type of ore deposit in the world.
## Assign to a HarvestableDeposit node. OreRegistry holds the full set.

@export var display_name: String = ""

@export_group("Drops")
@export var drop_item_id:   String = "stone"
@export var drop_count_min: int    = 1
@export var drop_count_max: int    = 3

@export_group("Mining")
## Total HP of this deposit — higher means more hits required.
@export var resource_hp: int = 40
## Minimum tool tier required: 1 = Wooden, 2 = Stone, 3 = Iron.
@export var required_tool_level: int = 1
## Relative world-gen frequency. Lower = spawns less often.
@export var spawn_weight: float = 50.0

@export_group("Visual")
@export var ore_color: Color  = Color(0.52, 0.50, 0.46)
## Bounding-box size of the deposit mesh (X/Z = width, Y = height).
@export var ore_size: Vector3 = Vector3(0.80, 0.60, 0.80)
