class_name LabelSolver
extends RefCounted
## Places the circuit label and the count badge of every symbol of a sheet so that they stay clear of
## walls, openings, symbols, texts and each other (SRD FR-LABEL). For each symbol it tries eight spots
## around the body and keeps the one with the fewest collisions; the badge starts from the side
## opposite the label. Symbols whose label was pinned by hand are left alone and count as obstacles.
## Pure: returns the offsets to store, applying them is the caller's business (an entity.update).
## `only` limits the solving to those ids (the other symbols stay where they are and count as
## obstacles); `extra` are symbols not in the sheet yet (a placement being made), always solved.

const GAP_FACTOR: float = 0.25
const WALL_PENALTY: float = 1000.0
const OBJECT_PENALTY: float = 100.0
## Eight directions in a fixed order of preference: the same for every symbol keeps plans tidy.
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, -1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, -1),
	Vector2(-1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1),
]


## {symbol id: {"label_offset": [x, y], "count_offset": [x, y]}} for every unpinned symbol showing a
## label (and/or a badge: only the keys that apply are present), whole world millimetres. Deterministic.
static func solve(sheet: Sheet, ctx: RenderContext, only: Array = [], extra: Array[Entity] = []) -> Dictionary:
	var walls: Array[PackedVector2Array] = []
	var objects: Array[Rect2] = []
	var symbols: Array[Entity] = []
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		match entity.type:
			"wall":
				var points: Array = entity.props["points"]
				walls.append_array(EntityGeometry.wall_polygons(points, EntityGeometry.wall_weight_world(entity.props, ctx)))
			"opening":
				walls.append(EntityGeometry.opening_polygon(entity.props, ctx))
			"text":
				objects.append(EntityGeometry.text_rect(entity.props, ctx))
			"symbol":
				objects.append(SymbolGeometry.bounds(entity, ctx))
				symbols.append(entity)
	for entity: Entity in extra:
		objects.append(SymbolGeometry.bounds(entity, ctx))
		symbols.append(entity)
	var size: float = SymbolGeometry.label_size(ctx)
	var placed: Array[Rect2] = []
	for entity: Entity in symbols:
		if _is_fixed(entity, only):
			var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
			var label: String = SymbolGeometry.label_text(entity)
			var badge: String = SymbolGeometry.count_text(entity)
			if not label.is_empty():
				placed.append(SymbolGeometry.text_box(label, origin + SymbolGeometry.effective_label_offset(entity, ctx), size))
			if not badge.is_empty():
				placed.append(SymbolGeometry.text_box(badge, origin + SymbolGeometry.effective_count_offset(entity, ctx), size * SymbolGeometry.BADGE_FACTOR))
	var out: Dictionary = {}
	for entity: Entity in symbols:
		if _is_fixed(entity, only):
			continue
		var origin: Vector2 = EntityGeometry.vec(entity.props["pos"])
		var body: Rect2 = SymbolGeometry.bounds(entity, ctx)
		var entry: Dictionary = {}
		var label_direction: int = -1
		var label: String = SymbolGeometry.label_text(entity)
		if not label.is_empty():
			var pick: Dictionary = _pick(label, size, body, origin, 0, walls, objects, placed)
			var offset: Vector2 = pick["offset"]
			var box: Rect2 = pick["box"]
			entry["label_offset"] = [roundi(offset.x), roundi(offset.y)]
			label_direction = pick["direction"]
			placed.append(box)
		var badge: String = SymbolGeometry.count_text(entity)
		if not badge.is_empty():
			var start: int = (label_direction + 4) % DIRECTIONS.size() if label_direction >= 0 else 0
			var pick: Dictionary = _pick(badge, size * SymbolGeometry.BADGE_FACTOR, body, origin, start, walls, objects, placed)
			var offset: Vector2 = pick["offset"]
			var box: Rect2 = pick["box"]
			entry["count_offset"] = [roundi(offset.x), roundi(offset.y)]
			placed.append(box)
		if not entry.is_empty():
			out[entity.id] = entry
	return out


## Pinned by hand, or not among the ids to solve: its labels stay and block others.
static func _is_fixed(entity: Entity, only: Array) -> bool:
	return entity.props["label_pinned"] or (not only.is_empty() and not only.has(entity.id))


## The best of the eight spots around `body`, trying `start` first (earlier spots win ties):
## {"offset": centre relative to `origin`, "box": world rectangle, "direction": index}.
static func _pick(text: String, size: float, body: Rect2, origin: Vector2, start: int, walls: Array[PackedVector2Array], objects: Array[Rect2], placed: Array[Rect2]) -> Dictionary:
	var width: float = SymbolGeometry.text_box(text, Vector2.ZERO, size).size.x
	var gap: float = size * GAP_FACTOR
	var half: Vector2 = Vector2(body.size.x * 0.5 + width * 0.5 + gap, body.size.y * 0.5 + size * 0.5 + gap)
	var best: Dictionary = {}
	var best_score: float = INF
	for k: int in DIRECTIONS.size():
		var direction: int = (start + k) % DIRECTIONS.size()
		var dir: Vector2 = DIRECTIONS[direction]
		var center: Vector2 = body.get_center() + Vector2(dir.x * half.x, dir.y * half.y)
		var box: Rect2 = SymbolGeometry.text_box(text, center, size)
		var score: float = float(k) + _collisions(box, walls, objects, placed)
		if score < best_score:
			best_score = score
			best = {"offset": center - origin, "box": box, "direction": direction}
	return best


static func _collisions(box: Rect2, walls: Array[PackedVector2Array], objects: Array[Rect2], placed: Array[Rect2]) -> float:
	var score: float = 0.0
	var outline: PackedVector2Array = PackedVector2Array([
		box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y),
	])
	for wall: PackedVector2Array in walls:
		if not Geometry2D.intersect_polygons(outline, wall).is_empty():
			score += WALL_PENALTY
	for other: Rect2 in objects:
		if other.intersects(box):
			score += OBJECT_PENALTY
	for other: Rect2 in placed:
		if other.intersects(box):
			score += OBJECT_PENALTY
	return score
