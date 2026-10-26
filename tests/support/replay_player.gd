class_name ReplayPlayer
extends RefCounted
## Plays a recorded input session ("automated gameplay", SRD TEST-3) into a viewport.
##
## Replay file format (JSON, hand-writable):
##   { "format_version": 1,
##     "events": [
##       { "frame": 0, "type": "key", "key": "L", "pressed": true, "mods": ["shift"] },
##       { "frame": 2, "type": "mouse_motion", "pos": [100, 80] },
##       { "frame": 3, "type": "mouse_button", "button": "left", "pressed": true, "pos": [100, 80] },
##       { "frame": 4, "type": "wheel", "direction": "up", "pos": [100, 80], "mods": ["ctrl"] } ] }
##
## Time is counted in rendered frames, not milliseconds, so replays are deterministic.

const FORMAT_VERSION: int = 1


## Loads and validates a replay file. Returns the events as an Array, or an empty Array on error.
static func load_events(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplayPlayer: cannot open %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("ReplayPlayer: %s is not a JSON object" % path)
		return []
	var data: Dictionary = parsed
	if roundi(_num(data, "format_version", 0.0)) != FORMAT_VERSION:
		push_error("ReplayPlayer: unsupported format_version in %s" % path)
		return []
	var events: Variant = data.get("events", [])
	if not (events is Array):
		return []
	return events


## Plays `events` into `viewport`, one frame step at a time. Must be awaited.
func play(tree: SceneTree, viewport: Viewport, events: Array) -> void:
	var frame: int = 0
	for item: Variant in events:
		var ev: Dictionary = item
		var target_frame: int = roundi(_num(ev, "frame", 0.0))
		while frame < target_frame:
			await tree.process_frame
			frame += 1
		var input_event: InputEvent = _to_input_event(ev)
		if input_event != null:
			viewport.push_input(input_event)
	await tree.process_frame


func _to_input_event(ev: Dictionary) -> InputEvent:
	match str(ev.get("type", "")):
		"key":
			return _key_event(ev)
		"mouse_motion":
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position = _pos(ev)
			motion.global_position = motion.position
			_apply_mods(motion, ev)
			return motion
		"mouse_button":
			return _button_event(ev, _button_index(str(ev.get("button", "left"))), _flag(ev, "pressed", true))
		"wheel":
			var wheel: MouseButton = MOUSE_BUTTON_WHEEL_UP
			match str(ev.get("direction", "up")):
				"down":
					wheel = MOUSE_BUTTON_WHEEL_DOWN
				"left":
					wheel = MOUSE_BUTTON_WHEEL_LEFT
				"right":
					wheel = MOUSE_BUTTON_WHEEL_RIGHT
			return _button_event(ev, wheel, true)
	push_error("ReplayPlayer: unknown event type '%s'" % str(ev.get("type", "")))
	return null


func _key_event(ev: Dictionary) -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	var keycode: Key = OS.find_keycode_from_string(str(ev.get("key", "")))
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = _flag(ev, "pressed", true)
	_apply_mods(key, ev)
	return key


func _button_event(ev: Dictionary, index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = index
	button.pressed = pressed
	button.position = _pos(ev)
	button.global_position = button.position
	_apply_mods(button, ev)
	return button


func _button_index(name: String) -> MouseButton:
	match name:
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
	return MOUSE_BUTTON_LEFT


func _pos(ev: Dictionary) -> Vector2:
	var raw: Variant = ev.get("pos", [0, 0])
	if raw is Array:
		var arr: Array = raw
		if arr.size() >= 2:
			var x: float = arr[0]
			var y: float = arr[1]
			return Vector2(x, y)
	return Vector2.ZERO


static func _num(source: Dictionary, key: String, fallback: float) -> float:
	var value: float = source.get(key, fallback)
	return value


static func _flag(source: Dictionary, key: String, fallback: bool) -> bool:
	var value: bool = source.get(key, fallback)
	return value


func _apply_mods(event: InputEventWithModifiers, ev: Dictionary) -> void:
	var mods: Variant = ev.get("mods", [])
	if not (mods is Array):
		return
	var list: Array = mods
	event.shift_pressed = list.has("shift")
	event.alt_pressed = list.has("alt")
	event.ctrl_pressed = list.has("ctrl")
	event.meta_pressed = list.has("meta")
