extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var price: int = 10
@export var description: String = ""

# Shop section — e.g. "Timber & Framing", "Boarding & Cladding", "Masonry" etc.
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

# Blueprint items — set is_blueprint = true and assign blueprint_data
@export var is_blueprint: bool = false
@export var blueprint_data: BlueprintData
