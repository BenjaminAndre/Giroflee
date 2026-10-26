class_name DrawOp
extends RefCounted
## One backend-agnostic drawing primitive (SRD ARCH-12). All coordinates and lengths are
## world millimetres with y pointing up; backends flip y when they draw.

const POLYGON: String = "polygon"
const POLYLINE: String = "polyline"
const TEXT: String = "text"

var kind: String = POLYGON
## Role of the op, used for grouping in exports (walls, openings, labels, frame, ghost...).
var layer: String = ""
## Entity that produced the op ("" for page decorations); used by tests and picking aids.
var entity_id: String = ""
var points: PackedVector2Array = PackedVector2Array()
var color: Color = Color.BLACK
## Polygon: fill colour (alpha 0 = no fill). Polyline: unused.
var fill: Color = Color(0, 0, 0, 0)
## Polyline / polygon outline width in world mm (0 = no outline).
var width: float = 0.0
var closed: bool = false
var dashed: bool = false
# text
var text: String = ""
## Em height of the text in world mm.
var size: float = 0.0
var rotation_deg: float = 0.0
## "left", "center" or "right" (relative to the anchor point `points[0]`).
var anchor: String = "left"
var bold: bool = false


static func polygon(p_points: PackedVector2Array, p_fill: Color, p_layer: String, p_entity: String = "") -> DrawOp:
	var op: DrawOp = DrawOp.new()
	op.kind = POLYGON
	op.points = p_points
	op.fill = p_fill
	op.layer = p_layer
	op.entity_id = p_entity
	op.closed = true
	return op


static func polyline(p_points: PackedVector2Array, p_color: Color, p_width: float, p_layer: String, p_entity: String = "", p_closed: bool = false) -> DrawOp:
	var op: DrawOp = DrawOp.new()
	op.kind = POLYLINE
	op.points = p_points
	op.color = p_color
	op.width = p_width
	op.layer = p_layer
	op.entity_id = p_entity
	op.closed = p_closed
	return op


static func label(p_text: String, p_pos: Vector2, p_size: float, p_color: Color, p_layer: String, p_entity: String = "") -> DrawOp:
	var op: DrawOp = DrawOp.new()
	op.kind = TEXT
	op.text = p_text
	op.points = PackedVector2Array([p_pos])
	op.size = p_size
	op.color = p_color
	op.layer = p_layer
	op.entity_id = p_entity
	return op
