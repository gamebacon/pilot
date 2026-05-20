class_name InventoryController
extends RefCounted

## Middle layer between InventoryWindow (UI) and Inventory (data).
## Owns slot insertion/take rules and shift-click transfer logic.
## Subclass to create specialised behaviour (armor slots, fuel slots, output-only, …).

## Primary inventory (external, e.g. chest).  Set by the window on open.
var inv: Inventory = null

## Player's own inventory.  Non-null only in dual-inventory mode (chest+player, shop+player, …).
var player_inv: Inventory = null

# ── Slot rules — override per slot type ───────────────────────────────────────

## Return false to prevent placing [item_data] into the slot at position [pos].
func can_insert(_pos: int, _item_data: ItemData) -> bool:
	return true

## Return false to prevent taking items from the slot at position [pos]
## (e.g. a locked crafting-output slot before the recipe is complete).
func can_take(_pos: int) -> bool:
	return true

# ── Transfer rules ────────────────────────────────────────────────────────────

## Shift-click handler.  Try to move [items] (taken from [from_pos] in [from_inv])
## somewhere sensible.  Return any items that couldn't be placed.
func quick_transfer(items: Array[PhysicalItem], _from_pos: int, _from_inv: Inventory = null) -> Array[PhysicalItem]:
	return items
