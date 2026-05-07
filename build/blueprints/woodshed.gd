extends BlueprintData
class_name WoodshedBlueprint

# Firewood shed — 2.4 m wide (X) × 3.0 m deep (Z), open front and sides.
# Four 90×90 mm corner posts support a tarred flat roof.
# Phases:
#   0 — Set Corner Posts  (4 × 90×90 post)
#   1 — Lay Roof          (tarred panels)

const W := 2.4
const L := 3.0

const POST := "timber_post"
const ROOF := "roofing_panel"

func _init() -> void:
	display_name = "Firewood Shed"
	phase_names = [
		"Set Corner Posts",
		"Lay Roof",
	]
	_add_posts()
	_add_roof()

func _add_posts() -> void:
	var post := _load_item(POST)
	if not post: return
	var half_h := post.size.y * 0.5  # timber_post size.y = 3.0 → half_h = 1.5
	_place(Vector3(0.0, half_h, 0.0), POST, 0)
	_place(Vector3(W,   half_h, 0.0), POST, 0)
	_place(Vector3(0.0, half_h, L),   POST, 0)
	_place(Vector3(W,   half_h, L),   POST, 0)

func _add_roof() -> void:
	var post := _load_item(POST)
	if not post: return
	var roof_y := post.size.y  # top of posts
	_fill_roof(0.0, 0.0, W, L, roof_y, ROOF, 1)
