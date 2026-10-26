class_name SelectionTransform
extends RefCounted
## What scaling and rotating a selection does to each kind of entity (SRD FR-HANDLE-4, -5).
## Pure functions: they return the new properties of every entity ({id: props}); nothing is
## modified. Followers (openings hosted by a transformed wall) move and turn with it but keep
## their own size.


## `ids` plus what travels with them: the openings hosted by walls in `ids` and the symbols anchored
## to symbols in `ids` (the whole stack). Returns {"ids": Array, "followers": Array (sorted)}.
static func with_followers(sheet: Sheet, ids: Array) -> Dictionary:
	var followers: Array = []
	for entity_id: String in sheet.sorted_entity_ids():
		if ids.has(entity_id):
			continue
		var entity: Entity = sheet.entities[entity_id]
		if entity.type != "opening":
			continue
		var host: String = entity.props["host_wall"]
		if not host.is_empty() and ids.has(host):
			followers.append(entity_id)
	for carried: String in AnchorRules.descendants(sheet, ids):
		if not followers.has(carried):
			followers.append(carried)
	followers.sort()
	return {"ids": ids + followers, "followers": followers}


## New props for scaling `entities` by (sx, sy) about `anchor` (world mm).
static func scale(entities: Array, ctx: RenderContext, anchor: Vector2, sx: float, sy: float, followers: Array = []) -> Dictionary:
	var result: Dictionary = {}
	for item: Variant in entities:
		var entity: Entity = item
		var props: Dictionary = entity.props.duplicate(true)
		if entity.type == "wall":
			var points: Array = props["points"]
			var scaled: Array = []
			for point: Variant in points:
				scaled.append(_scale_point(point, anchor, sx, sy))
			props["points"] = scaled
		else:
			props["pos"] = _scale_point(props["pos"], anchor, sx, sy)
			if not followers.has(entity.id):
				_scale_size(entity.type, props, ctx, sx, sy)
		result[entity.id] = props
	return result


## New props for rotating `entities` by `angle_deg` (counter-clockwise) about `pivot`.
static func rotate(entities: Array, pivot: Vector2, angle_deg: float) -> Dictionary:
	var result: Dictionary = {}
	var angle: float = deg_to_rad(angle_deg)
	for item: Variant in entities:
		var entity: Entity = item
		var props: Dictionary = entity.props.duplicate(true)
		if entity.type == "wall":
			var points: Array = props["points"]
			var turned: Array = []
			for point: Variant in points:
				turned.append(_rotate_point(point, pivot, angle))
			props["points"] = turned
		else:
			props["pos"] = _rotate_point(props["pos"], pivot, angle)
			if props.has("rotation"):
				var current: float = props["rotation"]
				props["rotation"] = snappedf(fposmod(current + angle_deg, 360.0), 0.01)
		result[entity.id] = props
	return result


static func _scale_point(point: Variant, anchor: Vector2, sx: float, sy: float) -> Array:
	var p: Vector2 = EntityGeometry.vec(point)
	return [roundi(anchor.x + (p.x - anchor.x) * sx), roundi(anchor.y + (p.y - anchor.y) * sy)]


static func _rotate_point(point: Variant, pivot: Vector2, angle: float) -> Array:
	var p: Vector2 = EntityGeometry.vec(point)
	var turned: Vector2 = (p - pivot).rotated(angle) + pivot
	return [roundi(turned.x), roundi(turned.y)]


## Factors along the entity's own local axes when the world is scaled by (sx, sy).
static func _local_factors(props: Dictionary, sx: float, sy: float) -> Vector2:
	var rotation: float = 0.0
	if props.has("rotation"):
		rotation = props["rotation"]
	var theta: float = deg_to_rad(rotation)
	var c: float = cos(theta)
	var s: float = sin(theta)
	var lx: float = sqrt(pow(sx * c, 2.0) + pow(sy * s, 2.0))
	var ly: float = sqrt(pow(sx * s, 2.0) + pow(sy * c, 2.0))
	return Vector2(lx, ly)


static func _scale_size(type: String, props: Dictionary, ctx: RenderContext, sx: float, sy: float) -> void:
	var local: Vector2 = _local_factors(props, sx, sy)
	match type:
		"grey_block":
			var size: Array = props["size"]
			var w: int = size[0]
			var h: int = size[1]
			props["size"] = [maxi(1, roundi(float(w) * local.x)), maxi(1, roundi(float(h) * local.y))]
		"opening":
			var width: int = props["width_mm"]
			props["width_mm"] = maxi(1, roundi(float(width) * local.x))
		"stair":
			var stair_width: int = props["width_mm"]
			var tread: int = props["tread_mm"]
			props["width_mm"] = maxi(1, roundi(float(stair_width) * local.x))
			props["tread_mm"] = maxi(1, roundi(float(tread) * local.y))
		"text":
			var own: float = props["size_pt"]
			var role: String = props["role"]
			var current: float = own if own > 0.0 else ctx.font_size_pt * PlanTheme.role_factor(role)
			props["size_pt"] = snappedf(current * sqrt(sx * sy), 0.01)
