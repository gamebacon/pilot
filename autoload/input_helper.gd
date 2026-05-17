class_name InputHelper

# Switch to true for Nintendo Switch Pro controller (A↔B and X↔Y are swapped).
# false = Xbox / PlayStation layout: A = bottom (confirm), B = right (cancel).
const NINTENDO_LAYOUT := true

# Reads from the InputMap so labels always match what is actually bound.
static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "[?]"
	var events := InputMap.action_get_events(action)
	var pad_connected := Input.get_connected_joypads().size() > 0
	if pad_connected:
		for e in events:
			if e is InputEventJoypadButton:
				return "[%s]" % _joy_button_label(e.button_index as JoyButton)
			if e is InputEventJoypadMotion:
				return "[%s]" % _joy_axis_label(e.axis as JoyAxis, e.axis_value)
	for e in events:
		if e is InputEventKey:
			return "[%s]" % OS.get_keycode_string(e.physical_keycode if e.keycode == 0 else e.keycode)
		if e is InputEventMouseButton:
			match e.button_index:
				MOUSE_BUTTON_LEFT:   return "[LMB]"
				MOUSE_BUTTON_RIGHT:  return "[RMB]"
				MOUSE_BUTTON_MIDDLE: return "[MMB]"
	return "[?]"

static func _joy_button_label(btn: JoyButton) -> String:
	match btn:
		JOY_BUTTON_A: return "B" if NINTENDO_LAYOUT else "A"
		JOY_BUTTON_B: return "A" if NINTENDO_LAYOUT else "B"
		JOY_BUTTON_X: return "Y" if NINTENDO_LAYOUT else "X"
		JOY_BUTTON_Y: return "X" if NINTENDO_LAYOUT else "Y"
		JOY_BUTTON_BACK:           return "View"
		JOY_BUTTON_START:          return "Menu"
		JOY_BUTTON_LEFT_STICK:     return "LS"
		JOY_BUTTON_RIGHT_STICK:    return "RS"
		JOY_BUTTON_LEFT_SHOULDER:  return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_DPAD_UP:        return "↑"
		JOY_BUTTON_DPAD_DOWN:      return "↓"
		JOY_BUTTON_DPAD_LEFT:      return "←"
		JOY_BUTTON_DPAD_RIGHT:     return "→"
	return "Btn%d" % btn

static func _joy_axis_label(axis: JoyAxis, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:  return "L2"
		JOY_AXIS_TRIGGER_RIGHT: return "R2"
		JOY_AXIS_LEFT_X:  return "L-Stick ←" if value < 0 else "L-Stick →"
		JOY_AXIS_LEFT_Y:  return "L-Stick ↑" if value < 0 else "L-Stick ↓"
		JOY_AXIS_RIGHT_X: return "R-Stick ←" if value < 0 else "R-Stick →"
		JOY_AXIS_RIGHT_Y: return "R-Stick ↑" if value < 0 else "R-Stick ↓"
	return "Axis%d" % axis
