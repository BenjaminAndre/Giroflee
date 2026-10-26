class_name InputProbe
extends Node
## Test helper: records every input event that reaches the unhandled-input stage.

var events: Array[InputEvent] = []


func _unhandled_input(event: InputEvent) -> void:
	events.append(event)


## Number of recorded key-press events for the given key name (e.g. "L").
func key_presses(key_name: String) -> int:
	var keycode: Key = OS.find_keycode_from_string(key_name)
	var count: int = 0
	for event: InputEvent in events:
		if event is InputEventKey:
			var key: InputEventKey = event
			if key.pressed and key.keycode == keycode:
				count += 1
	return count
