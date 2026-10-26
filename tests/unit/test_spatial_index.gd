extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session
var sheet: Sheet
var ctx: RenderContext


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	TestKit.add_wall(s, "s1", "w-near", [[1000, 1000], [3000, 1000]])
	TestKit.add_wall(s, "s1", "w-far", [[15000, 12000], [17000, 12000]])
	TestKit.add_entity(s, "s1", "block", "grey_block", {"pos": [9000, 9000], "size": [500, 500]})
	sheet = s.document().get_sheet("s1")
	ctx = RenderContext.for_sheet(s.document(), sheet)


func test_queries_return_only_nearby_entities_sorted() -> void:
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	assert_eq(index.size(), 3)
	assert_eq(index.query_point(Vector2(2000, 1000), 100.0), ["w-near"])
	assert_eq(index.query_point(Vector2(9200, 9200), 50.0), ["block"])
	assert_eq(index.query_point(Vector2(6000, 6000), 100.0), [])
	assert_eq(index.query_rect(Rect2(0, 0, 20000, 20000)), ["block", "w-far", "w-near"])


func test_a_reversed_rect_works() -> void:
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	assert_eq(index.query_rect(Rect2(3500, 1500, -1000, -1000)), ["w-near"])


func test_entities_spanning_many_cells_are_found() -> void:
	TestKit.add_wall(s, "s1", "long", [[0, 5000], [60000, 5000]])
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	assert_true(index.query_point(Vector2(30000, 5000), 100.0).has("long"))
	assert_true(index.query_point(Vector2(59000, 5020), 100.0).has("long"))
	assert_false(index.query_point(Vector2(30000, 9000), 100.0).has("long"))


func test_negative_coordinates_work() -> void:
	TestKit.add_entity(s, "s1", "neg", "grey_block", {"pos": [-5000, -5000], "size": [500, 500]})
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	assert_eq(index.query_point(Vector2(-4800, -4800), 50.0), ["neg"])


func test_the_cache_follows_the_document_revision() -> void:
	var doc: Document = s.document()
	var first: SpatialIndex = SpatialIndex.for_sheet(doc, sheet, ctx)
	assert_same(SpatialIndex.for_sheet(doc, sheet, ctx), first, "no change: same index")
	TestKit.add_entity(s, "s1", "new", "grey_block", {"pos": [100, 100], "size": [100, 100]})
	var second: SpatialIndex = SpatialIndex.for_sheet(doc, sheet, ctx)
	assert_not_same(second, first, "rebuilt after a command")
	assert_true(second.query_point(Vector2(150, 150), 10.0).has("new"))
	s.undo()
	var third: SpatialIndex = SpatialIndex.for_sheet(doc, sheet, ctx)
	assert_false(third.query_point(Vector2(150, 150), 10.0).has("new"), "undo invalidates too")


func test_indexed_and_linear_queries_agree() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 60:
		var x: int = rng.randi_range(0, 20000)
		var y: int = rng.randi_range(0, 14000)
		TestKit.add_wall(s, "s1", "r%d" % i, [[x, y], [x + rng.randi_range(100, 3000), y + rng.randi_range(-500, 500)]])
	var index: SpatialIndex = SpatialIndex.build(sheet, ctx)
	for i: int in 80:
		var p: Vector2 = Vector2(rng.randf_range(0, 20000), rng.randf_range(0, 14000))
		assert_eq(HitTest.pick(sheet, ctx, p, 150.0, [], index), HitTest.pick(sheet, ctx, p, 150.0), "pick at %s" % str(p))
		var a: SnapEngine.Result = SnapEngine.snap(sheet, p, 150.0, {"index": index})
		var b: SnapEngine.Result = SnapEngine.snap(sheet, p, 150.0)
		assert_eq(a.pos, b.pos, "snap at %s" % str(p))
		assert_eq(a.kind, b.kind)
		var rect: Rect2 = Rect2(p, Vector2(rng.randf_range(100, 4000), rng.randf_range(100, 4000)))
		assert_eq(HitTest.in_rect(sheet, ctx, rect, [], index), HitTest.in_rect(sheet, ctx, rect), "box at %s" % str(rect))
		var wall_a: WallLocator.Hit = WallLocator.locate(sheet, p, 300.0, index)
		var wall_b: WallLocator.Hit = WallLocator.locate(sheet, p, 300.0)
		assert_eq(wall_a == null, wall_b == null)
		if wall_a != null:
			assert_eq(wall_a.wall_id, wall_b.wall_id)
