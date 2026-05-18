class_name GameConstants

# ── Shop categories ───────────────────────────────────────────────────────────
# Use these when setting ItemData.category so names stay consistent everywhere.
const CAT_BLUEPRINTS := "Blueprints"
const CAT_TIMBER     := "Timber & Framing"
const CAT_BOARDING   := "Boarding & Cladding"
const CAT_ROOFING    := "Roofing"
const CAT_MASONRY    := "Masonry"
const CAT_INSULATION := "Insulation"
const CAT_GLAZING    := "Glazing"
const CAT_SAUNA      := "Sauna"
const CAT_GROCERY    := "Grocery"
const CAT_TOOLS      := "Tools"
const CAT_WEAPONS    := "Weapons"

# Material sections displayed in this order in the shop (blueprints always first).
const MATERIAL_CATEGORY_ORDER: Array[String] = [
	"Timber & Framing",
	"Boarding & Cladding",
	"Roofing",
	"Masonry",
	"Insulation",
	"Glazing",
	"Sauna",
]

# ── Item resources ────────────────────────────────────────────────────────────
const ITEM_RES_DIR := "res://items/resources/"
