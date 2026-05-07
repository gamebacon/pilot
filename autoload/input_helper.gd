class_name InputHelper

# Returns a short bracketed label for the first event bound to an action,
# e.g. action_label("interact") → "[E]", action_label("place") → "[LMB]".
# If nothing is bound, returns "[?]".
static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "[?]"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return "[%s]" % OS.get_keycode_string(e.physical_keycode if e.keycode == 0 else e.keycode)
		if e is InputEventMouseButton:
			match e.button_index:
				MOUSE_BUTTON_LEFT:   return "[LMB]"
				MOUSE_BUTTON_RIGHT:  return "[RMB]"
				MOUSE_BUTTON_MIDDLE: return "[MMB]"
	return "[?]"
