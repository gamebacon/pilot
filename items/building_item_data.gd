class_name BuildingItemData
extends ItemData

## Piece type — drives slot layout, grid behaviour, and enemy targeting.
## "foundation" | "wall" | "tower" | "parapet"
@export var piece_type: String = ""

## Material tier (1 = wood, 2 = wood solid, 3 = stone).
## Determines HP, craft cost, and which visual scene is used.
## Upgrading between tiers is not yet implemented — field is here for future use.
@export var piece_tier: int = 1

## Hit points when freshly placed.
@export var piece_hp: int = 100

## Item id of the next-tier variant (empty = already max tier).
## Reserved for the upgrade system — not read at runtime yet.
@export var upgrade_to: String = ""
