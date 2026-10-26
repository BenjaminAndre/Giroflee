class_name SnapEngine
extends RefCounted
## Snapping of a cursor position (SRD FR-PLAN-1): object points (wall endpoints and midpoints,
## block and stair corners) win within the tolerance, otherwise the grid. Results are whole
## millimetres.

const NONE: String = "none"
const GRID: String = "grid"
const VERTEX: String = "vertex"
const MIDPOINT: String = "midpoint"


class Result:
	extends RefCounted
	var pos: Vector2 = Vector2.ZERO
	var kind: String = NONE
	var source_id: String = ""


## Options: {"grid": bool (default true), "objects": bool (default true), "exclude": Array of
## entity ids not to snap to (e.g. the ones being dragged), "index": SpatialIndex to look only
## at nearby entities}.
static func snap(sheet: Sheet, p: Vector2, tolerance: float, options: Dictionary = {}) -> Result:
	var use_grid: bool = true
	if options.has("grid"):
		use_grid = options["grid"]
	var use_objects: bool = true
	if options.has("objects"):
		use_objects = options["objects"]
	var exclude: Array = []
	if options.has("exclude"):
		exclude = options["exclude"]

	var result: Result = Result.new()
	result.pos = Vector2(roundf(p.x), roundf(p.y))
	if use_objects:
		var best: float = tolerance
		var candidates: Array[String] = sheet.sorted_entity_ids()
		if options.has("index"):
			var index: SpatialIndex = options["index"]
			candidates = index.query_point(p, tolerance)
		for entity_id: String in candidates:
			if exclude.has(entity_id):
				continue
			var entity: Entity = sheet.entities[entity_id]
			for candidate: Dictionary in _candidates(entity):
				var point: Vector2 = candidate["pos"]
				var distance: float = p.distance_to(point)
				if distance <= best:
					best = distance
					result.pos = Vector2(roundf(point.x), roundf(point.y))
					result.kind = candidate["kind"]
					result.source_id = entity_id
		if result.kind != NONE:
			return result
	if use_grid:
		var step_value: int = sheet.props["grid_step_mm"]
		var step: float = float(step_value)
		result.pos = Vector2(roundf(p.x / step) * step, roundf(p.y / step) * step)
		result.kind = GRID
	return result


## Constrains `to` so that the segment from `from` is horizontal or vertical (the dominant axis).
static func orthogonal(from: Vector2, to: Vector2) -> Vector2:
	var d: Vector2 = to - from
	if absf(d.x) >= absf(d.y):
		return Vector2(to.x, from.y)
	return Vector2(from.x, to.y)


static func _candidates(entity: Entity) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var props: Dictionary = entity.props
	match entity.type:
		"wall":
			var points: Array = props["points"]
			for i: int in points.size():
				var a: Vector2 = EntityGeometry.vec(points[i])
				out.append({"pos": a, "kind": VERTEX})
				if i + 1 < points.size():
					var b: Vector2 = EntityGeometry.vec(points[i + 1])
					out.append({"pos": (a + b) * 0.5, "kind": MIDPOINT})
		"grey_block":
			for corner: Vector2 in EntityGeometry.block_polygon(props):
				out.append({"pos": corner, "kind": VERTEX})
		"stair":
			for corner: Vector2 in EntityGeometry.stair_polygon(props):
				out.append({"pos": corner, "kind": VERTEX})
	return out
