extends Node

# Emitted whenever the active input device switches (controller ↔ keyboard/mouse).
signal input_changed(using_joy: bool)

# Switch to true for Nintendo Switch Pro controller (A↔B and X↔Y are swapped).
const NINTENDO_LAYOUT := true

# Tracks the active input device across the whole session.
# Static so static methods (action_label etc.) can read it without going through the singleton.
static var _using_joy: bool = false

func _ready() -> void:
	_using_joy = Input.get_connected_joypads().size() > 0
	# Also react if a controller is physically connected / disconnected at runtime.
	Input.joy_connection_changed.connect(_on_joy_connection)

func _on_joy_connection(_device: int, _connected: bool) -> void:
	var now := Input.get_connected_joypads().size() > 0
	if now != _using_joy:
		_using_joy = now
		input_changed.emit(_using_joy)

# "Last input wins": any joypad event → controller mode; any key or mouse button → KB/M mode.
# Mouse motion is intentionally excluded to avoid false positives from stick drift.
func _input(event: InputEvent) -> void:
	var was := _using_joy
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_using_joy = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_using_joy = false
	if _using_joy != was:
		input_changed.emit(_using_joy)

# ── Public API ────────────────────────────────────────────────────────────────

static func is_joy() -> bool:
	return _using_joy

# Reads from the InputMap so labels always match what is actually bound.
static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "[?]"
	var events := InputMap.action_get_events(action)
	if _using_joy:
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
