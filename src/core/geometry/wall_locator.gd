class_name WallLocator
extends RefCounted
## Finds the wall segment nearest to a point, so doors and windows can attach to it
## (SRD 5.1: openings snap to walls and follow them).


class Hit:
	extends RefCounted
	var wall_id: String = ""
	## Closest point on the wall centreline.
	var point: Vector2 = Vector2.ZERO
	## Direction of the segment, degrees counter-clockwise from +x.
	var angle_deg: float = 0.0
	## Unit direction of the segment.
	var direction: Vector2 = Vector2.RIGHT
	## Distance along the whole polyline from its first point to `point`, in mm.
	var offset_mm: float = 0.0
	## +1 when the query point is to the left of the segment direction, -1 when to the right.
	var side: int = 1


## Nearest wall within `tolerance` of `p` (distance to the centreline), or null.
static func locate(sheet: Sheet, p: Vector2, tolerance: float, index: SpatialIndex = null) -> Hit:
	var best: Hit = null
	var best_distance: float = tolerance
	var candidates: Array[String] = index.query_point(p, tolerance) if index != null else sheet.sorted_entity_ids()
	for entity_id: String in candidates:
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != "wall":
			continue
		var points: Array = entity.props["points"]
		var travelled: float = 0.0
		for i: int in range(points.size() - 1):
			var a: Vector2 = EntityGeometry.vec(points[i])
			var b: Vector2 = EntityGeometry.vec(points[i + 1])
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
			var distance: float = p.distance_to(closest)
			if distance <= best_distance and a != b:
				best_distance = distance
				var hit: Hit = Hit.new()
				hit.wall_id = entity_id
				hit.point = closest
				hit.direction = (b - a).normalized()
				hit.angle_deg = rad_to_deg(hit.direction.angle())
				hit.offset_mm = travelled + a.distance_to(closest)
				var cross: float = hit.direction.cross(p - closest)
				hit.side = 1 if cross >= 0.0 else -1
				best = hit
			travelled += a.distance_to(b)
	return best
