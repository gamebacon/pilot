extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var price: int = 10
@export var description: String = ""

# Shop section — use constants from GameConstants (CAT_TIMBER, CAT_SAUNA, etc.)
@export var category: String = ""

# --- Audio (all optional — leave empty to use defaults) ---
@export_group("Audio")
@export var sound_collide: AudioStream
@export var sound_pickup: AudioStream
@export var sound_place: AudioStream
@export var sound_walk: AudioStream

# Physical appearance
@export var color: Color = Color(0.75, 0.52, 0.22, 1.0)
@export var size: Vector3 = Vector3(0.4, 0.1, 1.2)

# Physics
@export var mass: float = 2.0

@export var carry_stack: int = 1

# Placeable items — can be placed in the world via build mode
@export var is_placeable: bool = false

## Scale applied to the PhysicalItem node while held in the player's hand.
## Leave at 0.0 to auto-calculate: largest dimension is normalised to 0.40 m.
@export var held_scale: float = 0.0

# Blueprint items — set is_blueprint = true and assign blueprint_data
@export var is_blueprint: bool = false
@export var blueprint_data: BlueprintData
