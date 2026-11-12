class_name EditorInput
extends RefCounted
## Turns raw input events into editor actions. Key bindings are the ones approved in SRD
## section 7 (WA-1: nothing is bound here that the author has not approved); the conventional
## editing keys named by FR-EDIT-1 (Delete, Ctrl+A, arrows) are marked ASSUMED below and listed
## for confirmation. The UI forwards every unhandled event here, so the same code serves the
## window, replay tests and unit tests.

signal palette_requested
signal new_window_requested
signal save_requested
signal save_as_requested
signal open_requested

const WHEEL_PAN_PIXELS: float = 60.0
const WHEEL_ZOOM_STEP: float = 1.15

var model: EditorModel
var space_down: bool = false

var _panning: bool = false
var _last_screen: Vector2 = Vector2.ZERO
## Last pointer position on screen, to refresh previews when only a modifier key changes.
var _pointer: Vector2 = Vector2.ZERO
var _has_pointer: bool = false


func _init(p_model: EditorModel) -> void:
	model = p_model


## Returns true when the event was used.
func handle(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		return _handle_key(key_event)
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		return _handle_button(button)
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		return _handle_motion(motion)
	return false


# --- keys ---------------------------------------------------------------------------------


func _handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_SPACE:
		space_down = event.pressed
		return true
	if _is_modifier(event):
		_refresh_for_modifiers(event)
		return false
	if not event.pressed:
		return false
	# the second key of "C letter" / "X digit"
	if not model.pending_prefix.is_empty() and not event.ctrl_pressed and not event.alt_pressed and not _is_modifier(event):
		return _complete_prefix(event)
	# a tool may want the key first (Enter / Backspace while drawing a wall)
	if not event.ctrl_pressed and not event.alt_pressed and model.tool.key(model, event):
		return true
	if event.ctrl_pressed:
		return _handle_ctrl_key(event)
	if event.alt_pressed or event.meta_pressed:
		return false
	var digit: int = digit_of(event)
	if digit > 0:
		model.use_quickbar(digit)
		return true
	match event.keycode:
		KEY_ESCAPE:
			_escape()
			return true
		KEY_W:
			model.set_tool("wall")
		KEY_D:
			model.set_tool("door")
		KEY_F:
			model.set_tool("window")
		KEY_E:
			model.set_tool("stair")
		KEY_S:
			model.set_tool("block")
		KEY_T:
			model.set_tool("text")
		KEY_L:
			model.set_tool("lamp")
		KEY_I:
			model.set_tool("switch_two_way" if event.shift_pressed else "switch")
		KEY_P:
			model.set_tool("socket")
		KEY_A:
			model.pipette()
		KEY_C:
			_start_prefix("C")
		KEY_X:
			_start_prefix("X")
		KEY_H:
			_flip(true)
		KEY_V:
			_flip(false)
		KEY_R:
			_rotate(event.shift_pressed)
		KEY_F2:
			model.edit_selection_text()
		KEY_DELETE, KEY_BACKSPACE: # ASSUMED (FR-EDIT-1 "delete")
			model.delete_selection()
		KEY_LEFT:
			model.nudge(-1, 0) # ASSUMED (FR-EDIT-1 "arrow-key nudge")
		KEY_RIGHT:
			model.nudge(1, 0)
		KEY_UP:
			model.nudge(0, 1)
		KEY_DOWN:
			model.nudge(0, -1)
		_:
			return false
	return true


## Shift, Ctrl or Alt went down or up: previews that depend on them (the Alt-place index, scaling
## from the centre, the cursor over a handle) are recomputed at once, without waiting for the pointer to move.
func _refresh_for_modifiers(event: InputEventKey) -> void:
	if not _has_pointer:
		return
	model.tool.move(model, _tool_input(_pointer, event))
	model.changed.emit()


func _start_prefix(prefix: String) -> void:
	model.pending_prefix = prefix
	model.changed.emit()


## Second key of "C letter" (circuit) or "X digit" (count). Anything else cancels the command.
func _complete_prefix(event: InputEventKey) -> bool:
	var prefix: String = model.pending_prefix
	model.pending_prefix = ""
	if event.keycode != KEY_ESCAPE:
		if prefix == "C" and event.keycode >= KEY_A and event.keycode <= KEY_Z:
			model.assign_circuit(String.chr(event.keycode))
		elif prefix == "X":
			var digit: int = digit_of(event)
			if digit > 0:
				model.set_count(digit)
	model.changed.emit()
	return true


static func _is_modifier(event: InputEventKey) -> bool:
	return event.keycode == KEY_SHIFT or event.keycode == KEY_CTRL or event.keycode == KEY_ALT or event.keycode == KEY_META


## 1-9 for a digit key, 0 otherwise. The physical key counts, so the top row works on any layout
## (on AZERTY the digits need Shift, the keys themselves do not).
static func digit_of(event: InputEventKey) -> int:
	for code: int in [event.physical_keycode, event.keycode]:
		if code >= KEY_1 and code <= KEY_9:
			return code - KEY_0
		if code >= KEY_KP_1 and code <= KEY_KP_9:
			return code - KEY_KP_0
	return 0


func _handle_ctrl_key(event: InputEvent) -> bool:
	var key_event: InputEventKey = event
	var slot: int = digit_of(key_event)
	if slot > 0:
		model.store_quickbar(slot) # FR-QB-3: Ctrl + digit stores the active tool
		return true
	match key_event.keycode:
		KEY_Z:
			model.undo()
		KEY_Y:
			model.redo()
		KEY_C:
			model.copy_selection()
		KEY_X:
			model.cut_selection()
		KEY_V:
			if model.hover_snap != null:
				model.paste(model.hover)
			else:
				model.paste()
		KEY_D:
			model.duplicate_selection()
		KEY_A: # ASSUMED (FR-EDIT-1 "select-all")
			model.select_all()
		KEY_T:
			model.new_sheet()
		KEY_TAB:
			model.cycle_sheet(-1 if key_event.shift_pressed else 1)
		KEY_N:
			new_window_requested.emit()
		KEY_S:
			if key_event.shift_pressed:
				save_as_requested.emit()
			else:
				save_requested.emit()
		KEY_O:
			open_requested.emit()
		KEY_P:
			palette_requested.emit()
		_:
			return false
	return true


func _escape() -> void:
	if model.tool.cancel(model):
		return
	if model.tool_name != "select":
		model.set_tool("select")
		return
	model.clear_selection()


## H / V: flip the placement ghost while placing, otherwise the selection.
func _flip(horizontal: bool) -> void:
	if model.is_placement_tool():
		model.flip_placement(horizontal)
	else:
		model.flip_selection(horizontal)


## R rotates one way (clockwise on screen), Shift+R the other way.
func _rotate(counter_clockwise: bool) -> void:
	if model.is_placement_tool():
		model.rotate_placement(counter_clockwise)
	else:
		model.rotate_selection(counter_clockwise)


# --- mouse --------------------------------------------------------------------------------


func _tool_input(screen: Vector2, event: InputEventWithModifiers) -> ToolInput:
	var input: ToolInput = ToolInput.new()
	input.screen = screen
	input.world = model.view().screen_to_world(screen)
	input.tolerance = model.tolerance()
	input.shift = event.shift_pressed
	input.alt = event.alt_pressed
	input.ctrl = event.ctrl_pressed
	return input


func _handle_button(event: InputEventMouseButton) -> bool:
	var view: ViewTransform = model.view()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
			if not event.pressed:
				return false
			_wheel(event, view)
			return true
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_last_screen = event.position
			return true
		MOUSE_BUTTON_LEFT:
			if event.pressed and space_down:
				_panning = true
				_last_screen = event.position
				return true
			if not event.pressed and _panning:
				_panning = false
				return true
			_pointer = event.position
			_has_pointer = true
			var input: ToolInput = _tool_input(event.position, event)
			input.double_click = event.double_click
			model.hover = input.world
			model.hover_snap = model.snap(input.world)
			if event.pressed:
				model.tool.press(model, input)
			else:
				model.tool.release(model, input)
			model.changed.emit()
			return true
		MOUSE_BUTTON_RIGHT:
			return _handle_right_button(event)
	return false


## Shift + right-click copies settings, Alt + right-click detaches a symbol (select tool on a plan).
func _handle_right_button(event: InputEventMouseButton) -> bool:
	if not event.pressed or model.tool_name != "select" or model.sheet().kind != "plan":
		return false
	var world: Vector2 = model.view().screen_to_world(event.position)
	model.hover = world
	if event.shift_pressed:
		model.copy_settings_at(world)
	elif event.alt_pressed:
		model.detach_at(world)
	else:
		return false
	model.changed.emit()
	return true


func _handle_motion(event: InputEventMouseMotion) -> bool:
	if _panning:
		model.view().pan_by_screen(event.position - _last_screen)
		_last_screen = event.position
		model.changed.emit()
		return true
	_pointer = event.position
	_has_pointer = true
	var input: ToolInput = _tool_input(event.position, event)
	model.hover = input.world
	model.hover_snap = model.snap(input.world)
	model.tool.move(model, input)
	model.changed.emit()
	return true


## Wheel: vertical pan; Shift = horizontal pan; Ctrl = zoom at the cursor (SRD FR-PLAN-2).
func _wheel(event: InputEventMouseButton, view: ViewTransform) -> void:
	var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT
	var sign: float = 1.0 if up else -1.0
	if event.ctrl_pressed:
		var factor: float = WHEEL_ZOOM_STEP if sign > 0.0 else 1.0 / WHEEL_ZOOM_STEP
		view.zoom_at(event.position, factor)
	elif event.shift_pressed or event.button_index == MOUSE_BUTTON_WHEEL_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		view.pan_by_screen(Vector2(sign * WHEEL_PAN_PIXELS, 0.0))
	else:
		view.pan_by_screen(Vector2(0.0, sign * WHEEL_PAN_PIXELS))
	model.changed.emit()
