extends ItemData
class_name ToolItemData

## Extended ItemData for tools (axe, pickaxe) and weapons (sword).
## Durability is tracked per PhysicalItem instance, not here.

func _init() -> void:
	carry_stack = 1   # tools never stack

@export_enum("axe", "pickaxe", "sword") var tool_type: String = "axe"

## 1 = Wooden, 2 = Stone, 3 = Iron
@export var tool_level: int = 1

## Human-readable tier label shown in UI
@export var level_name: String = "Wooden"

## Starting durability for each instance of this tool
@export var durability_max: int = 60

## HP removed from a harvestable node per hit
@export var harvest_damage: float = 10.0

## Damage dealt to enemies per hit
@export var attack_damage: float = 10.0

## Which resource tags this tool can harvest ("tree", "rock")
@export var harvest_tags: PackedStringArray = []
