extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export var price: int = 10
@export var description: String = ""

# Item category — use constants from GameConstants (CAT_TOOLS, CAT_WEAPONS, etc.)
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

@export var carry_stack: int = 32

# Placeable items — can be placed in the world via build mode
@export var is_placeable: bool = false

# Foundations can be placed freely on terrain; all other building pieces require
# snapping to an existing placed piece.
@export var is_foundation: bool = false

# Whether the player can rotate this piece in build mode.
@export var can_rotate: bool = true

# Interactables (chests, crafting tables, etc.) that can be set down anywhere
# without needing a foundation underneath.
@export var free_placement: bool = false

## Scale applied to the PhysicalItem node while held in the player's hand.
## Leave at 0.0 to auto-calculate: largest dimension is normalised to 0.40 m.
@export var held_scale: float = 0.0
