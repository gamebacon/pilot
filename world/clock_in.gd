extends StaticBody3D

func interact(_player: Node) -> void:
	if GameState.shift_active or GameState.shift_done:
		return
	var mgr := get_tree().get_first_node_in_group("day_manager")
	if mgr:
		mgr.start_shift()

func get_interact_hint(_player: Node) -> String:
	if GameState.shift_active or GameState.shift_done:
		return ""
	return "%s  Clock In — Day %d" % [InputHelper.action_label("interact"), GameState.day]
