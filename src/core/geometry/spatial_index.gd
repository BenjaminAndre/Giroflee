class_name SpatialIndex
extends RefCounted
## Uniform grid over the bounding boxes of a sheet's entities (SRD ARCH-14), so picking,
## snapping and box selection only look at entities near the pointer instead of scanning the
## whole sheet. Rebuilt when the document changes (see `for_sheet`).

const CELL: float = 2000.0
## An entity covering more cells than this is kept in a short list that every query checks.
const MAX_CELLS_PER_ENTITY: int = 400

var _cells: Dictionary = {}
var _large: Array[String] = []
var _bounds: Dictionary = {}


## The index of `sheet`, cached on the document and rebuilt only when its revision changed.
static func for_sheet(doc: Document, sheet: Sheet, ctx: RenderContext) -> SpatialIndex:
	var cached: Variant = doc.spatial_cache.get(sheet.id)
	if cached is Dictionary:
		var entry: Dictionary = cached
		var revision: int = entry["revision"]
		if revision == doc.revision:
			var hit: SpatialIndex = entry["index"]
			return hit
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	doc.spatial_cache[sheet.id] = {"revision": doc.revision, "index": index}
	return index


static func build(sheet: Sheet, ctx: RenderContext) -> SpatialIndex:
	var index: SpatialIndex = SpatialIndex.new()
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		index._insert(entity_id, EntityGeometry.bounds(entity, ctx))
	return index


## Ids (sorted) of entities whose bounds intersect `rect`.
func query_rect(rect: Rect2) -> Array[String]:
	var area: Rect2 = rect.abs()
	var found: Dictionary = {}
	for entity_id: String in _large:
		var big: Rect2 = _bounds[entity_id]
		if area.intersects(big, true):
			found[entity_id] = true
	var first: Vector2i = _cell_of(area.position)
	var last: Vector2i = _cell_of(area.end)
	if (last.x - first.x + 1) * (last.y - first.y + 1) > MAX_CELLS_PER_ENTITY * 4:
		for key: Variant in _bounds.keys():
			var entity_id: String = key
			var all_bounds: Rect2 = _bounds[entity_id]
			if area.intersects(all_bounds, true):
				found[entity_id] = true
	else:
		for cx: int in range(first.x, last.x + 1):
			for cy: int in range(first.y, last.y + 1):
				var ids: Variant = _cells.get(Vector2i(cx, cy))
				if ids is Array:
					for raw_id: Variant in ids:
						var candidate: String = raw_id
						if found.has(candidate):
							continue
						var b: Rect2 = _bounds[candidate]
						if area.intersects(b, true):
							found[candidate] = true
	var out: Array[String] = []
	for key: Variant in found.keys():
		var entity_id: String = key
		out.append(entity_id)
	out.sort()
	return out


## Ids of entities whose bounds come within `radius` of `p`.
func query_point(p: Vector2, radius: float) -> Array[String]:
	return query_rect(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0))


func size() -> int:
	return _bounds.size()


func _insert(entity_id: String, bounds: Rect2) -> void:
	_bounds[entity_id] = bounds
	var first: Vector2i = _cell_of(bounds.position)
	var last: Vector2i = _cell_of(bounds.end)
	if (last.x - first.x + 1) * (last.y - first.y + 1) > MAX_CELLS_PER_ENTITY:
		_large.append(entity_id)
		return
	for cx: int in range(first.x, last.x + 1):
		for cy: int in range(first.y, last.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _cells.has(key):
				_cells[key] = []
			var ids: Array = _cells[key]
			ids.append(entity_id)


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))
