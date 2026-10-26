class_name HitTest
extends RefCounted
## Picking and box selection on a plan sheet. Later entities in the draw order win a click.

## Stacking order, top first (mirrors PlanRenderer.TYPE_ORDER reversed, symbols on top).
const PICK_ORDER: Array[String] = ["symbol", "text", "wall", "opening", "stair", "grey_block"]


## Topmost entity within `tolerance` world mm of `p`, or "". `exclude` ids are skipped. With a
## SpatialIndex only the entities near `p` are examined.
static func pick(sheet: Sheet, ctx: RenderContext, p: Vector2, tolerance: float, exclude: Array = [], index: SpatialIndex = null) -> String:
	var best_id: String = ""
	var best_rank: int = 1000
	var best_distance: float = INF
	var candidates: Array[String] = index.query_point(p, tolerance) if index != null else sheet.sorted_entity_ids()
	for entity_id: String in candidates:
		if exclude.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		var distance: float = EntityGeometry.distance_to(entity, ctx, p)
		if distance > tolerance:
			continue
		var rank: int = PICK_ORDER.find(entity.type)
		if rank < 0:
			rank = PICK_ORDER.size()
		# higher in the stack wins; among equals the nearer one; then the later id
		if rank < best_rank or (rank == best_rank and distance <= best_distance):
			best_id = entity_id
			best_rank = rank
			best_distance = distance
	return best_id


## Entities whose bounds touch `rect` (box selection), in id order.
static func in_rect(sheet: Sheet, ctx: RenderContext, rect: Rect2, exclude: Array = [], index: SpatialIndex = null) -> Array[String]:
	var out: Array[String] = []
	var area: Rect2 = rect.abs()
	var candidates: Array[String] = index.query_rect(area) if index != null else sheet.sorted_entity_ids()
	for entity_id: String in candidates:
		if exclude.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if area.intersects(EntityGeometry.bounds(entity, ctx), true):
			out.append(entity_id)
	return out
