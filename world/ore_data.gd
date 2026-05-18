extends Resource
class_name OreData

## Data resource that defines one type of ore deposit in the world.
## Assign to a HarvestableDeposit node. OreRegistry holds the full set.

enum Rarity { COMMON = 0, UNCOMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }

const RARITY_NAMES: Array[String] = [
	"Common", "Uncommon", "Rare", "Epic", "Legendary"
]
## Rarity label colours used in UI hints.
const RARITY_COLORS: Array[Color] = [
	Color(0.80, 0.80, 0.80),   # Common    — white/grey
	Color(0.30, 0.90, 0.30),   # Uncommon  — green
	Color(0.30, 0.60, 1.00),   # Rare      — blue
	Color(0.80, 0.30, 1.00),   # Epic      — purple
	Color(1.00, 0.85, 0.20),   # Legendary — gold
]

@export var display_name: String = ""
@export var rarity: Rarity = Rarity.COMMON

@export_group("Drops")
@export var drop_item_id: String = "stone"
@export var drop_count_min: int  = 1
@export var drop_count_max: int  = 3

@export_group("Mining")
## Total HP of this deposit — higher means more hits required.
@export var resource_hp: int = 40
## Minimum pickaxe tier required: 1 = Wooden, 2 = Stone, 3 = Iron.
@export var required_tool_level: int = 1
## Relative world-gen frequency. Higher = spawns more often.
@export var spawn_weight: float = 50.0

@export_group("Visual")
@export var ore_color: Color    = Color(0.52, 0.50, 0.46)
## Bounding-box size of the deposit mesh (X/Z = width, Y = height).
@export var ore_size: Vector3   = Vector3(0.80, 0.60, 0.80)

# ── Helpers ───────────────────────────────────────────────────────────────────

func rarity_label() -> String:
	return RARITY_NAMES[clampi(int(rarity), 0, 4)]

func rarity_color() -> Color:
	return RARITY_COLORS[clampi(int(rarity), 0, 4)]

## Name of the pickaxe tier required, for hint text.
func required_pickaxe_name() -> String:
	match required_tool_level:
		1: return "Wooden Pickaxe"
		2: return "Stone Pickaxe"
		3: return "Iron Pickaxe"
		_: return "Better Pickaxe"
