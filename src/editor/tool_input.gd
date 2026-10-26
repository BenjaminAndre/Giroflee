class_name ToolInput
extends RefCounted
## One pointer event as seen by a tool: world position (mm, y up) and modifiers.

var world: Vector2 = Vector2.ZERO
var screen: Vector2 = Vector2.ZERO
## World millimetres equivalent to the pick radius on screen (about 10 px).
var tolerance: float = 50.0
var shift: bool = false
var alt: bool = false
var ctrl: bool = false
var double_click: bool = false


static func make(p_world: Vector2, p_tolerance: float = 50.0) -> ToolInput:
	var input: ToolInput = ToolInput.new()
	input.world = p_world
	input.tolerance = p_tolerance
	return input
