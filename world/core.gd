extends StaticBody3D

const MAX_HP:             float = 100.0
const CRAFTING_UI_SCRIPT        := preload("res://ui/crafting_ui.gd")

var health: HealthComponent = HealthComponent.new()

signal hp_changed(new_hp: int)
signal destroyed

var _crafting_ui: CraftingUI = null

func _ready() -> void:
	add_to_group("core")
	add_child(health)
	health.setup(MAX_HP)
	health.hp_changed.connect(func(current: float, _max: float) -> void:
		hp_changed.emit(int(current))
	)
	health.died.connect(destroyed.emit)

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
	health.take_damage(amount)
	if NetworkManager.is_active():
		_sync_hp.rpc(int(health.current_hp))

@rpc("authority", "reliable", "call_remote")
func _sync_hp(new_hp: int) -> void:
	health.current_hp = float(new_hp)
	hp_changed.emit(new_hp)
