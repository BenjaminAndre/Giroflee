class_name UiHarness
extends RefCounted
## Builds a real EditorWindow inside a test and drives it with ReplayPlayer events, the way a
## user would (SRD TEST-3). Mouse positions are given in world mm and converted to the
## viewport coordinates of the canvas.

var window: EditorWindow
var events: Array = []
var _frame: int = 0


## Creates the window under `parent`, shows an empty project and waits for the layout.
static func create(test: GutTest, document: Document = null) -> UiHarness:
	var harness: UiHarness = UiHarness.new()
	harness.window = EditorWindow.new()
	harness.window.slot = 98
	test.add_child_autofree(harness.window)
	harness.window.size = Vector2(1600, 900)
	harness.window.open_document(document, "")
	await test.get_tree().process_frame
	await test.get_tree().process_frame
	return harness


func model() -> EditorModel:
	return window.model


func at(world: Vector2) -> Vector2:
	return window.canvas.global_position + window.model.view().world_to_screen(world)


func next_frame() -> void:
	_frame += 1


func key(name: String, mods: Array = []) -> void:
	events.append({"frame": _frame, "type": "key", "key": name, "pressed": true, "mods": mods})
	next_frame()


func move(world: Vector2) -> void:
	var p: Vector2 = at(world)
	events.append({"frame": _frame, "type": "mouse_motion", "pos": [p.x, p.y]})


func click(world: Vector2, double_click: bool = false, mods: Array = []) -> void:
	move(world)
	var p: Vector2 = at(world)
	events.append({"frame": _frame, "type": "mouse_button", "button": "left", "pressed": true, "pos": [p.x, p.y], "double_click": double_click, "mods": mods})
	events.append({"frame": _frame, "type": "mouse_button", "button": "left", "pressed": false, "pos": [p.x, p.y], "mods": mods})
	next_frame()


func drag(from: Vector2, to: Vector2) -> void:
	move(from)
	var a: Vector2 = at(from)
	var b: Vector2 = at(to)
	events.append({"frame": _frame, "type": "mouse_button", "button": "left", "pressed": true, "pos": [a.x, a.y]})
	next_frame()
	for i: int in range(1, 5):
		var p: Vector2 = a.lerp(b, float(i) / 4.0)
		events.append({"frame": _frame, "type": "mouse_motion", "pos": [p.x, p.y]})
		next_frame()
	events.append({"frame": _frame, "type": "mouse_button", "button": "left", "pressed": false, "pos": [b.x, b.y]})
	next_frame()


## Plays everything queued so far into the window's viewport and clears the queue.
func play(test: GutTest) -> void:
	var player: ReplayPlayer = ReplayPlayer.new()
	await player.play(test.get_tree(), window.get_viewport(), events)
	events = []
	_frame = 0
	await test.get_tree().process_frame
