class_name SymbolGeometry
extends RefCounted
## Placing symbol artwork on the plan. The artwork is authored in page millimetres, y down, with its
## anchor at the origin (SRD 11.2). It becomes world millimetres by multiplying with the sheet scale
## and the project symbol scale, flipping y (the world is y up), then applying the symbol's own
## mirrors and rotation about its position. A symbol therefore keeps its size on the paper whatever
## the scale of the sheet.

const LABEL_ROLE: String = "symbol"
const BADGE_FACTOR: float = 0.75
const PLACEHOLDER_RADIUS: float = 3.0


## World millimetres per page millimetre of artwork.
static func unit(ctx: RenderContext) -> float:
	return ctx.scale * ctx.symbol_scale


static func def_of(entity: Entity, ctx: RenderContext) -> SymbolLibrary.Def:
	var type: String = entity.props["symbol_type"]
	if ctx.library == null:
		return null
	return ctx.library.def(type)


static func label_text(entity: Entity) -> String:
	var circuit: String = entity.props["circuit"]
	if circuit.is_empty():
		return ""
	var index: int = entity.props["index"]
	return "%s%s" % [circuit, str(index) if index > 0 else "?"]


static func count_text(entity: Entity) -> String:
	var count: int = entity.props["count"]
	return "x%d" % count if count > 1 else ""


## The symbol's strokes and fills in world millimetres:
## [{"points", "closed", "width", "stroke", "fill", "stroke_color", "fill_color", "fill_opacity"}].
static func world_shapes(entity: Entity, ctx: RenderContext) -> Array[Dictionary]:
	var def: SymbolLibrary.Def = def_of(entity, ctx)
	var k: float = unit(ctx)
	var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
	var rotation: float = entity.props["rotation"]
	var flip_h: bool = entity.props["flip_h"]
	var flip_v: bool = entity.props["flip_v"]
	if def == null:
		return _placeholder(origin, rotation, k)
	return shapes_of(def.plan, origin, rotation, flip_h, flip_v, k)


## The strokes and fills of `art` placed at `origin` (world mm, y up) with `k` world mm per page mm.
static func shapes_of(art: SvgArt, origin: Vector2, rotation: float, flip_h: bool, flip_v: bool, k: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for shape: SvgArt.Shape in art.shapes:
		var points: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in shape.points:
			points.append(EntityGeometry.to_world(origin, rotation, flip_h, flip_v, Vector2(p.x * k, -p.y * k)))
		out.append({
			"points": points, "closed": shape.closed, "width": shape.stroke_width * k,
			"stroke": shape.stroke, "fill": shape.fill,
			"stroke_color": shape.stroke_color, "fill_color": shape.fill_color, "fill_opacity": shape.fill_opacity,
		})
	return out


## How far the artwork reaches behind its anchor, opposite to the way it faces (world mm): the depth
## of a socket's back, which has to sit against the wall instead of across it. 0 for an unknown type.
static func back_depth(def: SymbolLibrary.Def, ctx: RenderContext) -> float:
	if def == null:
		return 0.0
	var art: Rect2 = def.plan.bounds()
	return maxf(0.0, art.end.y) * unit(ctx)


static func bounds(entity: Entity, ctx: RenderContext) -> Rect2:
	var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
	var rect: Rect2 = Rect2(origin, Vector2.ZERO)
	var widest: float = 0.0
	for shape: Dictionary in world_shapes(entity, ctx):
		var points: PackedVector2Array = shape["points"]
		for p: Vector2 in points:
			rect = rect.expand(p)
		var width: float = shape["width"]
		widest = maxf(widest, width)
	return rect.grow(widest * 0.5)


static func add_ops(entity: Entity, ctx: RenderContext, ghost: bool, out: DrawList) -> void:
	if ghost:
		return
	var def: SymbolLibrary.Def = def_of(entity, ctx)
	var color: Color = _body_color(entity, def, ctx)
	add_shape_ops(world_shapes(entity, ctx), color, def, "symbols", entity.id, out)
	_add_labels(entity, def, ctx, color, out)


## Draw ops for `shapes` (from `shapes_of`): `color` is the body colour, an explicit marker colour wins.
static func add_shape_ops(shapes: Array[Dictionary], color: Color, def: SymbolLibrary.Def, layer: String, entity_id: String, out: DrawList) -> void:
	for shape: Dictionary in shapes:
		var points: PackedVector2Array = shape["points"]
		var closed: bool = shape["closed"]
		var stroke: bool = shape["stroke"]
		var width: float = shape["width"]
		var filled: bool = shape["fill"]
		if filled and points.size() >= 3:
			var fill_color: Color = _shape_color(shape["fill_color"], color, def)
			fill_color.a = shape["fill_opacity"]
			out.add(DrawOp.polygon(points, fill_color, layer, entity_id))
		if stroke:
			out.add(DrawOp.polyline(points, _shape_color(shape["stroke_color"], color, def), width, layer, entity_id, closed))


## Where the circuit label is centred relative to the symbol when it was never placed explicitly:
## below and to the right of the body, like the reference plans.
static func default_label_offset(entity: Entity, ctx: RenderContext) -> Vector2:
	var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
	var body: Rect2 = bounds(entity, ctx)
	var size: float = label_size(ctx)
	return Vector2(maxf(body.end.x - origin.x, 0.0) + size * 0.9, minf(body.position.y - origin.y, 0.0) - size * 0.4)


## The count badge goes to the opposite side (upper left), away from the circuit label.
static func default_count_offset(entity: Entity, ctx: RenderContext) -> Vector2:
	var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
	var body: Rect2 = bounds(entity, ctx)
	var size: float = label_size(ctx) * BADGE_FACTOR
	return Vector2(minf(body.position.x - origin.x, 0.0) - size * 0.9, maxf(body.end.y - origin.y, 0.0) + size * 0.7)


## Label offset used for drawing: the stored one, or the default while it is still [0, 0].
static func effective_label_offset(entity: Entity, ctx: RenderContext) -> Vector2:
	var stored: Vector2 = EntityGeometry.vec(entity.props["label_offset"])
	return stored if stored != Vector2.ZERO else default_label_offset(entity, ctx)


static func effective_count_offset(entity: Entity, ctx: RenderContext) -> Vector2:
	var stored: Vector2 = EntityGeometry.vec(entity.props["count_offset"])
	return stored if stored != Vector2.ZERO else default_count_offset(entity, ctx)


static func label_size(ctx: RenderContext) -> float:
	return ctx.pt_to_world(ctx.font_size_pt * PlanTheme.role_factor(LABEL_ROLE))


## Rectangle (world mm) occupied by `text` centred on `center`, for collision tests.
static func text_box(text: String, center: Vector2, size: float) -> Rect2:
	var width: float = maxf(1.0, float(text.length())) * size * EntityGeometry.TEXT_WIDTH_FACTOR
	return Rect2(center - Vector2(width * 0.5, size * 0.5), Vector2(width, size))


static func _add_labels(entity: Entity, def: SymbolLibrary.Def, ctx: RenderContext, color: Color, out: DrawList) -> void:
	var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
	var size: float = label_size(ctx)
	if def != null and not def.caption.is_empty():
		out.add(_centered(def.caption, origin, size, PlanTheme.GREEN, entity.id))
	var label: String = label_text(entity)
	if not label.is_empty():
		out.add(_centered(label, origin + effective_label_offset(entity, ctx), size, color, entity.id))
	var badge: String = count_text(entity)
	if not badge.is_empty():
		out.add(_centered(badge, origin + effective_count_offset(entity, ctx), size * BADGE_FACTOR, color, entity.id))


static func _centered(text: String, center: Vector2, size: float, color: Color, entity_id: String) -> DrawOp:
	var op: DrawOp = DrawOp.label(text, center - Vector2(0.0, size * 0.35), size, color, "labels", entity_id)
	op.anchor = "center"
	return op


static func _body_color(entity: Entity, def: SymbolLibrary.Def, ctx: RenderContext) -> Color:
	if def == null:
		return PlanTheme.DARK_RED
	if def.marker:
		return PlanTheme.GREEN
	var circuit: String = entity.props["circuit"]
	if ctx.circuit_colors and not circuit.is_empty():
		if ctx.dimmed_circuits.has(circuit):
			return PlanTheme.GHOST
		return CircuitPalette.color(circuit)
	return PlanTheme.BLACK


## An explicit colour in the artwork (a marker's green) wins, unless the circuit is dimmed.
static func _shape_color(explicit: Variant, body: Color, def: SymbolLibrary.Def) -> Color:
	if explicit is Color and def != null and def.marker:
		var c: Color = explicit
		return c
	return body


## Drawn when the pack has no such type (an old project, a removed pack): visible and selectable.
static func _placeholder(origin: Vector2, rotation: float, k: float) -> Array[Dictionary]:
	var r: float = PLACEHOLDER_RADIUS * k
	var out: Array[Dictionary] = []
	var circle: PackedVector2Array = PackedVector2Array()
	for i: int in 20:
		var a: float = TAU * float(i) / 20.0
		circle.append(EntityGeometry.to_world(origin, rotation, false, false, Vector2(cos(a), sin(a)) * r))
	out.append({"points": circle, "closed": true, "width": 0.35 * k, "stroke": true, "fill": false, "stroke_color": null, "fill_color": null, "fill_opacity": 1.0})
	for diag: Array in [[Vector2(-r, -r), Vector2(r, r)], [Vector2(-r, r), Vector2(r, -r)]]:
		var a: Vector2 = diag[0]
		var b: Vector2 = diag[1]
		out.append({
			"points": PackedVector2Array([EntityGeometry.to_world(origin, rotation, false, false, a), EntityGeometry.to_world(origin, rotation, false, false, b)]),
			"closed": false, "width": 0.35 * k, "stroke": true, "fill": false, "stroke_color": null, "fill_color": null, "fill_opacity": 1.0,
		})
	return out
