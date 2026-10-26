class_name EntityGeometry
extends RefCounted
## Geometry of plan entities in world millimetres (y up): drawing ops, bounds and distances.
## One source for rendering, hit testing and box selection.

const ARC_STEP_DEG: float = 10.0
const TEXT_WIDTH_FACTOR: float = 0.55


## [x, y] (integer mm, as stored in props) to a Vector2.
static func vec(value: Variant) -> Vector2:
	var arr: Array = value
	var x: int = arr[0]
	var y: int = arr[1]
	return Vector2(float(x), float(y))


## Point of an entity-local frame (origin, rotation CCW in degrees, optional mirrors) in world space.
static func to_world(origin: Vector2, rotation_deg: float, flip_h: bool, flip_v: bool, local: Vector2) -> Vector2:
	var mirrored: Vector2 = Vector2(-local.x if flip_h else local.x, -local.y if flip_v else local.y)
	return origin + mirrored.rotated(deg_to_rad(rotation_deg))


static func wall_weight_world(props: Dictionary, ctx: RenderContext) -> float:
	var weight: float = props["weight_mm"]
	return ctx.page_to_world(weight)


## Thick polyline as filled polygons with mitred corners.
##
## A path whose first and last points coincide is a closed ring. Offsetting a closed outline
## yields an outer polygon plus a hole, which a plain polygon fill cannot show, so a ring is
## drawn as two overlapping open halves that meet in the middle of two segments: every real
## corner is then an interior mitre, and no hole appears.
static func wall_polygons(points: Array, weight_world: float) -> Array[PackedVector2Array]:
	var path: PackedVector2Array = PackedVector2Array()
	for point: Variant in points:
		var p: Array = point
		path.append(vec(p))
	var result: Array[PackedVector2Array] = []
	if path.size() < 2 or weight_world <= 0.0:
		return result
	if path.size() >= 4 and path[0] == path[path.size() - 1]:
		path.remove_at(path.size() - 1)
		for half: PackedVector2Array in _ring_halves(path, weight_world * 0.5):
			result.append_array(_offset_open(half, weight_world))
		return result
	return _offset_open(path, weight_world)


static func _offset_open(path: PackedVector2Array, weight_world: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var polygons: Array[PackedVector2Array] = Geometry2D.offset_polyline(path, weight_world * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)
	for polygon: PackedVector2Array in polygons:
		result.append(polygon)
	return result


## The two open paths covering a ring of `n >= 3` distinct vertices. They end on the middle of
## a segment, extended by `overlap` so that no seam is visible.
static func _ring_halves(ring: PackedVector2Array, overlap: float) -> Array[PackedVector2Array]:
	var n: int = ring.size()
	var k: int = n / 2
	var d0: Vector2 = (ring[1] - ring[0]).normalized()
	var d1: Vector2 = (ring[(k + 1) % n] - ring[k]).normalized()
	var s0: Vector2 = (ring[0] + ring[1]) * 0.5
	var s1: Vector2 = (ring[k] + ring[(k + 1) % n]) * 0.5
	var first: PackedVector2Array = PackedVector2Array()
	first.append(s0 - d0 * overlap)
	for i: int in range(1, k + 1):
		first.append(ring[i])
	first.append(s1 + d1 * overlap)
	var second: PackedVector2Array = PackedVector2Array()
	second.append(s1 - d1 * overlap)
	for i: int in range(k + 1, n):
		second.append(ring[i])
	second.append(ring[0])
	second.append(s0 + d0 * overlap)
	return [first, second]


## Local rectangle [0,w] x [0,h] corners in CCW order, in world space.
static func local_rect(origin: Vector2, rotation_deg: float, w: float, h: float) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for local: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]:
		corners.append(to_world(origin, rotation_deg, false, false, local))
	return corners


## Door: grey quarter disc swept from the closed leaf (along local +x) to 90 degrees open.
static func door_polygon(props: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = vec(props["pos"])
	var rotation_deg: float = props["rotation"]
	var flip_h: bool = props["flip_h"]
	var flip_v: bool = props["flip_v"]
	var width: int = props["width_mm"]
	var w: float = float(width)
	var out: PackedVector2Array = PackedVector2Array()
	out.append(to_world(origin, rotation_deg, flip_h, flip_v, Vector2.ZERO))
	var angle: float = 0.0
	while angle <= 90.0 + 0.001:
		var a: float = deg_to_rad(angle)
		out.append(to_world(origin, rotation_deg, flip_h, flip_v, Vector2(w * cos(a), w * sin(a))))
		angle += ARC_STEP_DEG
	return out


## Window: grey rectangle of the opening's width, centred on the wall line.
static func window_polygon(props: Dictionary, ctx: RenderContext) -> PackedVector2Array:
	var origin: Vector2 = vec(props["pos"])
	var rotation_deg: float = props["rotation"]
	var flip_h: bool = props["flip_h"]
	var flip_v: bool = props["flip_v"]
	var width: int = props["width_mm"]
	var w: float = float(width)
	var half: float = ctx.page_to_world(PlanTheme.OPENING_THICKNESS) * 0.5
	var out: PackedVector2Array = PackedVector2Array()
	for local: Vector2 in [Vector2(0, -half), Vector2(w, -half), Vector2(w, half), Vector2(0, half)]:
		out.append(to_world(origin, rotation_deg, flip_h, flip_v, local))
	return out


static func opening_polygon(props: Dictionary, ctx: RenderContext) -> PackedVector2Array:
	var kind: String = props["kind"]
	if kind == "door":
		return door_polygon(props)
	return window_polygon(props, ctx)


## Stair outline rectangle: width along local x, steps * tread along local y.
static func stair_polygon(props: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = vec(props["pos"])
	var rotation_deg: float = props["rotation"]
	var flip_h: bool = props["flip_h"]
	var flip_v: bool = props["flip_v"]
	var width: int = props["width_mm"]
	var steps: int = props["steps"]
	var tread: int = props["tread_mm"]
	var out: PackedVector2Array = PackedVector2Array()
	var w: float = float(width)
	var length: float = float(steps * tread)
	for local: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(w, length), Vector2(0, length)]:
		out.append(to_world(origin, rotation_deg, flip_h, flip_v, local))
	return out


static func block_polygon(props: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = vec(props["pos"])
	var rotation_deg: float = props["rotation"]
	var size: Array = props["size"]
	var w: int = size[0]
	var h: int = size[1]
	return local_rect(origin, rotation_deg, float(w), float(h))


## Text height (em) in world mm.
static func text_size_world(props: Dictionary, ctx: RenderContext) -> float:
	var own: float = props["size_pt"]
	var role: String = props["role"]
	var pt: float = own if own > 0.0 else ctx.font_size_pt * PlanTheme.role_factor(role)
	return ctx.pt_to_world(pt)


static func text_rect(props: Dictionary, ctx: RenderContext) -> Rect2:
	var origin: Vector2 = vec(props["pos"])
	var size: float = text_size_world(props, ctx)
	var text: String = props["text"]
	var width: float = maxf(1.0, float(text.length())) * size * TEXT_WIDTH_FACTOR
	return Rect2(origin + Vector2(0.0, -size * 0.25), Vector2(width, size * 1.1))


## Appends the drawing ops of one entity. `ghost` draws it as a light-grey backdrop.
static func add_ops(entity: Entity, ctx: RenderContext, ghost: bool, out: DrawList) -> void:
	var props: Dictionary = entity.props
	var line_color: Color = PlanTheme.GHOST if ghost else PlanTheme.BLACK
	var fill_color: Color = PlanTheme.GHOST_FILL if ghost else PlanTheme.GREY_FILL
	var suffix: String = "_ghost" if ghost else ""
	match entity.type:
		"wall":
			var weight: float = wall_weight_world(props, ctx)
			var points: Array = props["points"]
			for polygon: PackedVector2Array in wall_polygons(points, weight):
				out.add(DrawOp.polygon(polygon, line_color, "walls" + suffix, entity.id))
		"opening":
			out.add(DrawOp.polygon(opening_polygon(props, ctx), fill_color, "openings" + suffix, entity.id))
		"stair":
			var outline: PackedVector2Array = stair_polygon(props)
			var weight: float = ctx.page_to_world(ctx.wall_weight)
			var closed: Array = []
			for corner: Vector2 in outline:
				closed.append([roundi(corner.x), roundi(corner.y)])
			closed.append(closed[0])
			for polygon: PackedVector2Array in wall_polygons(closed, weight):
				out.add(DrawOp.polygon(polygon, line_color, "stairs" + suffix, entity.id))
			for line: Array in _stair_step_lines(props):
				for polygon: PackedVector2Array in wall_polygons(line, weight * 0.6):
					out.add(DrawOp.polygon(polygon, line_color, "stairs" + suffix, entity.id))
		"grey_block":
			out.add(DrawOp.polygon(block_polygon(props), fill_color, "blocks" + suffix, entity.id))
		"symbol":
			SymbolGeometry.add_ops(entity, ctx, ghost, out)
		"text":
			if ghost:
				return
			var role: String = props["role"]
			var text: String = props["text"]
			var op: DrawOp = DrawOp.label(text, vec(props["pos"]), text_size_world(props, ctx), PlanTheme.role_color(role), "labels", entity.id)
			op.rotation_deg = props["rotation"]
			out.add(op)


static func _stair_step_lines(props: Dictionary) -> Array[Array]:
	var origin: Vector2 = vec(props["pos"])
	var rotation_deg: float = props["rotation"]
	var flip_h: bool = props["flip_h"]
	var flip_v: bool = props["flip_v"]
	var width: int = props["width_mm"]
	var steps: int = props["steps"]
	var tread: int = props["tread_mm"]
	var lines: Array[Array] = []
	for k: int in range(1, steps):
		var y: float = float(k * tread)
		var a: Vector2 = to_world(origin, rotation_deg, flip_h, flip_v, Vector2(0, y))
		var b: Vector2 = to_world(origin, rotation_deg, flip_h, flip_v, Vector2(float(width), y))
		lines.append([[roundi(a.x), roundi(a.y)], [roundi(b.x), roundi(b.y)]])
	return lines


## Bounding box of an entity in world mm (walls include their thickness).
static func bounds(entity: Entity, ctx: RenderContext) -> Rect2:
	var props: Dictionary = entity.props
	match entity.type:
		"wall":
			var points: Array = props["points"]
			var path: PackedVector2Array = PackedVector2Array()
			for point: Variant in points:
				var p: Array = point
				path.append(vec(p))
			return _bounds_of(path).grow(wall_weight_world(props, ctx) * 0.5)
		"opening":
			return _bounds_of(opening_polygon(props, ctx))
		"stair":
			return _bounds_of(stair_polygon(props))
		"grey_block":
			return _bounds_of(block_polygon(props))
		"text":
			return text_rect(props, ctx)
		"symbol":
			return SymbolGeometry.bounds(entity, ctx)
	var origin: Vector2 = vec(props["pos"]) if props.has("pos") else Vector2.ZERO
	return Rect2(origin, Vector2.ZERO).grow(100.0)


## Bounds of the entity's geometry without line thickness (a wall is just its centre line).
## This is what the transform box scales and rotates, so that scaling a wall moves its points
## exactly with the cursor.
static func core_bounds(entity: Entity, ctx: RenderContext) -> Rect2:
	if entity.type == "wall":
		var points: Array = entity.props["points"]
		var path: PackedVector2Array = PackedVector2Array()
		for point: Variant in points:
			path.append(vec(point))
		return _bounds_of(path)
	return bounds(entity, ctx)


## Distance from `p` to the entity's drawn shape; 0 when inside.
static func distance_to(entity: Entity, ctx: RenderContext, p: Vector2) -> float:
	var props: Dictionary = entity.props
	match entity.type:
		"wall":
			var points: Array = props["points"]
			var path: PackedVector2Array = PackedVector2Array()
			for point: Variant in points:
				var q: Array = point
				path.append(vec(q))
			return maxf(0.0, _distance_to_path(path, p) - wall_weight_world(props, ctx) * 0.5)
		"opening":
			return _distance_to_polygon(opening_polygon(props, ctx), p)
		"stair":
			return _distance_to_polygon(stair_polygon(props), p)
		"grey_block":
			return _distance_to_polygon(block_polygon(props), p)
		"text":
			var rect: Rect2 = text_rect(props, ctx)
			if rect.has_point(p):
				return 0.0
			var nearest: Vector2 = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
			return p.distance_to(nearest)
		"symbol":
			var body: Rect2 = SymbolGeometry.bounds(entity, ctx)
			if body.has_point(p):
				return 0.0
			var closest: Vector2 = Vector2(clampf(p.x, body.position.x, body.end.x), clampf(p.y, body.position.y, body.end.y))
			return p.distance_to(closest)
	return INF


static func _bounds_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var rect: Rect2 = Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		rect = rect.expand(p)
	return rect


static func _distance_to_path(path: PackedVector2Array, p: Vector2) -> float:
	var best: float = INF
	for i: int in range(path.size() - 1):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		best = minf(best, p.distance_to(closest))
	return best


static func _distance_to_polygon(polygon: PackedVector2Array, p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p, polygon):
		return 0.0
	var best: float = INF
	for i: int in polygon.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])
		best = minf(best, p.distance_to(closest))
	return best
