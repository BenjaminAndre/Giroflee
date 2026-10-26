class_name EditorKit
extends RefCounted
## Drives an EditorModel through EditorInput with synthetic events, in world coordinates, so
## editor tests read like a user's session.

var session: Session
var model: EditorModel
var input: EditorInput


static func create(seed_value: int = 1) -> EditorKit:
	var kit: EditorKit = EditorKit.new()
	kit.session = TestKit.session(seed_value)
	kit.model = EditorModel.new(kit.session)
	kit.model.set_viewport_size(Vector2(1600, 900))
	kit.input = EditorInput.new(kit.model)
	return kit


func doc() -> Document:
	return model.doc()


func sheet() -> Sheet:
	return model.sheet()


func key(keycode: Key, shift: bool = false, ctrl: bool = false, alt: bool = false) -> bool:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	return input.handle(event)


func key_up(keycode: Key) -> bool:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = false
	return input.handle(event)


func screen(world: Vector2) -> Vector2:
	return model.view().world_to_screen(world)


func _button(world: Vector2, index: MouseButton, pressed: bool, shift: bool, ctrl: bool, alt: bool, double: bool) -> bool:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = screen(world)
	event.global_position = event.position
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.double_click = double
	return input.handle(event)


func press(world: Vector2, shift: bool = false, double: bool = false, alt: bool = false) -> void:
	_button(world, MOUSE_BUTTON_LEFT, true, shift, false, alt, double)


func release(world: Vector2, shift: bool = false) -> void:
	_button(world, MOUSE_BUTTON_LEFT, false, shift, false, false, false)


func move(world: Vector2, shift: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = screen(world)
	event.global_position = event.position
	event.shift_pressed = shift
	input.handle(event)


func click(world: Vector2, shift: bool = false, double: bool = false, alt: bool = false) -> void:
	move(world, shift)
	press(world, shift, double, alt)
	release(world, shift)


func drag(from: Vector2, to: Vector2, shift: bool = false) -> void:
	move(from, shift)
	press(from, shift)
	var steps: int = 4
	for i: int in range(1, steps + 1):
		move(from.lerp(to, float(i) / float(steps)), shift)
	release(to, shift)


func wheel(index: MouseButton, at_world: Vector2, shift: bool = false, ctrl: bool = false) -> void:
	_button(at_world, index, true, shift, ctrl, false, false)


func entities_of(type: String) -> Array[Entity]:
	var out: Array[Entity] = []
	for entity_id: String in sheet().sorted_entity_ids():
		var entity: Entity = sheet().entities[entity_id]
		if entity.type == type:
			out.append(entity)
	return out


## Adds an entity directly through the session (test setup), returns its id.
func add(type: String, props: Dictionary, entity_id: String = "") -> String:
	var id: String = entity_id if not entity_id.is_empty() else model.new_id()
	var result: CommandResult = model.add_entities([{"id": id, "type": type, "props": props}])
	assert(result.ok, result.error)
	return id
