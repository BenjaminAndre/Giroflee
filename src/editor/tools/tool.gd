class_name Tool
extends RefCounted
## Base class of the editing tools. A tool turns pointer and key events into commands (through
## the EditorModel and its Session) and can describe a live preview. Tools never touch the
## Document directly (SRD ARCH-2).


func tool_name() -> String:
	return ""


func press(_model: EditorModel, _input: ToolInput) -> void:
	pass


func move(_model: EditorModel, _input: ToolInput) -> void:
	pass


func release(_model: EditorModel, _input: ToolInput) -> void:
	pass


## Keys the tool wants for itself (e.g. Enter to finish a wall). Return true when consumed.
func key(_model: EditorModel, _event: InputEventKey) -> bool:
	return false


## Abandons a gesture in progress. Returns true when there was one.
func cancel(_model: EditorModel) -> bool:
	return false


## True while a gesture is in progress.
func is_active() -> bool:
	return false


## Entity property overrides to draw while the gesture runs: {entity_id: props}.
func overrides(_model: EditorModel) -> Dictionary:
	return {}


## Extra options for the renderer while the tool is in use (the unifilaire's selection and drop mark).
func render_options(_model: EditorModel) -> Dictionary:
	return {}


## Extra ops drawn on top of the sheet (placement ghost, rubber band, readouts).
func preview(_model: EditorModel) -> DrawList:
	return DrawList.new()


## Rectangles / handles drawn by the canvas for the gesture (box selection etc.).
func overlay_rect() -> Rect2:
	return Rect2()


func has_overlay_rect() -> bool:
	return false


## One-line hint for the status bar.
func hint(_model: EditorModel) -> String:
	return ""


## Preview ops of a temporary entity (a placement ghost), drawn in the "preview" layer.
static func entity_preview(model: EditorModel, type: String, props: Dictionary) -> DrawList:
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec(type), props, true)
	var list: DrawList = DrawList.new()
	if not JsonUtil.flag(normalized, "ok"):
		return list
	var full: Dictionary = normalized["props"]
	var temp: Entity = Entity.new("__preview__", type, full)
	var inner: DrawList = DrawList.new()
	EntityGeometry.add_ops(temp, model.ctx(), false, inner)
	for op: DrawOp in inner.ops:
		op.layer = "preview"
		list.add(op)
	return list
