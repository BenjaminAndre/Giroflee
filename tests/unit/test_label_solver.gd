extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD FR-LABEL: circuit labels and count badges are placed clear of walls, symbols and each other.

var s: Session
var doc: Document
var sheet: Sheet


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	doc = s.document()
	sheet = doc.get_sheet("s1")


func _ctx() -> RenderContext:
	return RenderContext.for_sheet(doc, sheet)


func _add(id: String, pos: Array, extra: Dictionary = {}) -> void:
	var props: Dictionary = {"symbol_type": "lamp", "pos": pos, "circuit": "A", "index": 1}
	props.merge(extra, true)
	assert_true(TestKit.add_entity(s, "s1", id, "symbol", props).ok, s.last_error)


func _box(id: String, key: String, ctx: RenderContext, text: String, scale: float = 1.0) -> Rect2:
	var solved: Dictionary = LabelSolver.solve(sheet, ctx)
	var entry: Dictionary = solved[id]
	var offset: Array = entry[key]
	var origin: Vector2 = EntityGeometry.vec(sheet.entities[id].props["pos"])
	return SymbolGeometry.text_box(text, origin + EntityGeometry.vec(offset), SymbolGeometry.label_size(ctx) * scale)


func test_a_lone_symbol_gets_its_label_in_the_first_preferred_spot() -> void:
	_add("a", [10000, 10000])
	var solved: Dictionary = LabelSolver.solve(sheet, _ctx())
	var entry: Dictionary = solved["a"]
	var offset: Array = entry["label_offset"]
	assert_gt(int(offset[0]), 0, "to the right of the symbol")
	assert_lt(int(offset[1]), 0, "and above it")
	assert_false(entry.has("count_offset"), "no badge for a single point")


func test_a_label_avoids_a_wall() -> void:
	_add("a", [10000, 10000])
	var ctx: RenderContext = _ctx()
	var plain: Dictionary = LabelSolver.solve(sheet, ctx)
	var plain_entry: Dictionary = plain["a"]
	var first: Array = plain_entry["label_offset"]
	# a wall right through the preferred spot
	var spot: Vector2 = Vector2(10000, 10000) + EntityGeometry.vec(first)
	assert_true(TestKit.add_wall(s, "s1", "w", [[int(spot.x) - 2000, int(spot.y)], [int(spot.x) + 2000, int(spot.y)]]).ok, s.last_error)
	var box: Rect2 = _box("a", "label_offset", ctx, "A1")
	for polygon: PackedVector2Array in EntityGeometry.wall_polygons([[int(spot.x) - 2000, int(spot.y)], [int(spot.x) + 2000, int(spot.y)]], EntityGeometry.wall_weight_world(sheet.entities["w"].props, ctx)):
		var outline: PackedVector2Array = PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
		assert_true(Geometry2D.intersect_polygons(outline, polygon).is_empty(), "the label does not sit on the wall")


func test_neighbouring_symbols_do_not_get_overlapping_labels() -> void:
	_add("a", [10000, 10000])
	_add("b", [10500, 10000], {"index": 2})
	_add("c", [11000, 10000], {"index": 3})
	var ctx: RenderContext = _ctx()
	var boxes: Array[Rect2] = [_box("a", "label_offset", ctx, "A1"), _box("b", "label_offset", ctx, "A2"), _box("c", "label_offset", ctx, "A3")]
	for i: int in boxes.size():
		for j: int in range(i + 1, boxes.size()):
			assert_false(boxes[i].intersects(boxes[j]), "labels %d and %d are apart" % [i, j])


func test_the_badge_goes_to_the_opposite_side_of_the_label() -> void:
	_add("a", [10000, 10000], {"count": 3})
	var entry: Dictionary = LabelSolver.solve(sheet, _ctx())["a"]
	var label: Array = entry["label_offset"]
	var badge: Array = entry["count_offset"]
	assert_lt(int(label[0]) * int(badge[0]) + int(label[1]) * int(badge[1]), 0, "pointing away from each other")


func test_a_pinned_label_is_left_alone_and_others_keep_clear_of_it() -> void:
	_add("a", [10000, 10000], {"label_pinned": true, "label_offset": [400, -300]})
	_add("b", [10400, 9700], {"index": 2})
	var ctx: RenderContext = _ctx()
	var solved: Dictionary = LabelSolver.solve(sheet, ctx)
	assert_false(solved.has("a"), "pinned: not touched")
	var pinned: Rect2 = SymbolGeometry.text_box("A1", Vector2(10400, 9700), SymbolGeometry.label_size(ctx))
	assert_false(_box("b", "label_offset", ctx, "A2").intersects(pinned), "b avoids the pinned label")


func test_symbols_without_a_label_or_badge_are_skipped() -> void:
	_add("a", [10000, 10000], {"circuit": ""})
	assert_true(LabelSolver.solve(sheet, _ctx()).is_empty())


func test_solving_twice_gives_the_same_offsets() -> void:
	_add("a", [10000, 10000], {"count": 2})
	_add("b", [10300, 10000], {"index": 2})
	assert_eq(LabelSolver.solve(sheet, _ctx()), LabelSolver.solve(sheet, _ctx()))
