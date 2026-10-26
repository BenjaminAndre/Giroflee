extends GutTest
## Smoke test of the replay harness (SRD TEST-3): a recorded session is injected into the
## viewport and must reach a node's input handler, with modifiers intact.


func test_replay_delivers_all_events_in_order() -> void:
	var probe: InputProbe = InputProbe.new()
	add_child_autofree(probe)

	var events: Array = ReplayPlayer.load_events("res://tests/replays/smoke_input.json")
	assert_eq(events.size(), 8, "replay file loaded")

	var player: ReplayPlayer = ReplayPlayer.new()
	await player.play(get_tree(), get_viewport(), events)

	assert_eq(probe.events.size(), 8)
	assert_eq(probe.key_presses("L"), 1)
	assert_eq(probe.key_presses("C"), 1)
	assert_eq(probe.key_presses("H"), 1)


func test_replay_preserves_modifiers_and_positions() -> void:
	var probe: InputProbe = InputProbe.new()
	add_child_autofree(probe)

	var events: Array = ReplayPlayer.load_events("res://tests/replays/smoke_input.json")
	var player: ReplayPlayer = ReplayPlayer.new()
	await player.play(get_tree(), get_viewport(), events)

	var shift_h: InputEventKey = null
	var wheel: InputEventMouseButton = null
	for event: InputEvent in probe.events:
		if event is InputEventKey:
			var key: InputEventKey = event
			if key.keycode == KEY_H:
				shift_h = key
		elif event is InputEventMouseButton:
			var button: InputEventMouseButton = event
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				wheel = button
	assert_not_null(shift_h)
	assert_true(shift_h.shift_pressed, "Shift+H keeps its modifier")
	assert_not_null(wheel)
	assert_true(wheel.ctrl_pressed, "Ctrl+wheel keeps its modifier")
	assert_eq(wheel.position, Vector2(100, 80))


func test_replay_respects_frame_timing() -> void:
	var probe: InputProbe = InputProbe.new()
	add_child_autofree(probe)

	var events: Array = [
		{"frame": 0, "type": "key", "key": "W", "pressed": true},
		{"frame": 3, "type": "key", "key": "D", "pressed": true},
	]
	var player: ReplayPlayer = ReplayPlayer.new()
	var start: int = Engine.get_process_frames()
	await player.play(get_tree(), get_viewport(), events)
	assert_true(Engine.get_process_frames() - start >= 3, "waited at least 3 frames")
	assert_eq(probe.key_presses("W"), 1)
	assert_eq(probe.key_presses("D"), 1)


func test_unknown_replay_file_yields_no_events() -> void:
	var events: Array = ReplayPlayer.load_events("res://tests/replays/does_not_exist.json")
	assert_eq(events.size(), 0)
	assert_push_error("cannot open")
