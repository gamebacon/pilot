extends StaticBody3D

const MAX_HP         := 100
const CRAFTING_UI_SCRIPT := preload("res://ui/crafting_ui.gd")

var hp: int = MAX_HP

signal hp_changed(new_hp: int)
signal destroyed

var _crafting_ui: CraftingUI = null

func _ready() -> void:
	add_to_group("core")

# ── Interaction ───────────────────────────────────────────────────────────────

func get_interact_hint(_player: Node) -> String:
	return InputHelper.action_label("interact") + "  Craft"

func interact(player: Node) -> void:
	if not _crafting_ui or not is_instance_valid(_crafting_ui):
		_crafting_ui = CRAFTING_UI_SCRIPT.new()
		get_tree().current_scene.add_child(_crafting_ui)
	_crafting_ui.open(player)

# ── Combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - int(ceil(amount)))
	if NetworkManager.is_active():
		_sync_hp.rpc(hp)
	hp_changed.emit(hp)
	if hp == 0:
		destroyed.emit()

@rpc("authority", "reliable", "call_remote")
func _sync_hp(new_hp: int) -> void:
	hp = new_hp
	hp_changed.emit(hp)
