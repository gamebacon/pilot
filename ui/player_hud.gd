extends CanvasLayer

@onready var hint_label: Label = $HintLabel

var _player: Node = null

func _ready() -> void:
	hint_label.hide()

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint_label.hide()
		return

	var target: Node = _player.interact_target
	if target and target.has_method("get_interact_hint"):
		var hint: String = target.get_interact_hint(_player)
		if hint.is_empty():
			hint_label.hide()
		else:
			hint_label.text = hint
			hint_label.show()
	else:
		hint_label.hide()
