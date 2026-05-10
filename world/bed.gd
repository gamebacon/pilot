extends StaticBody3D

func interact(_player: Node) -> void:
	if not GameState.shift_done:
		return
	var mgr := get_tree().get_first_node_in_group("day_manager")
	if mgr:
		mgr.end_day()

func get_interact_hint(_player: Node) -> String:
	if GameState.shift_active:
		return ""
	if not GameState.shift_done:
		return "Complete your shift first"
	return "%s  Sleep  →  Day %d" % [InputHelper.action_label("interact"), GameState.day + 1]
