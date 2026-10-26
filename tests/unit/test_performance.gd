extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD ARCH-14 targets smooth interaction with at least 2000 entities on a sheet. These are
## generous sanity bounds (a slow CI machine must still pass), plus a printed measurement.

const COUNT: int = 2000


func _big_session() -> Session:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "s1")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var items: Array = []
	for i: int in COUNT:
		var x: int = rng.randi_range(0, 20000)
		var y: int = rng.randi_range(0, 14000)
		match i % 4:
			0:
				items.append({"id": "w%d" % i, "type": "wall", "props": {"points": [[x, y], [x + 800, y], [x + 800, y + 500]]}})
			1:
				items.append({"id": "b%d" % i, "type": "grey_block", "props": {"pos": [x, y], "size": [600, 400]}})
			2:
				items.append({"id": "o%d" % i, "type": "opening", "props": {"kind": "door", "pos": [x, y], "width_mm": 900}})
			_:
				items.append({"id": "t%d" % i, "type": "text", "props": {"pos": [x, y], "text": "Pièce"}})
	var result: CommandResult = s.run_one("entity.add", {"sheet": "s1", "items": items})
	assert_true(result.ok, result.error)
	return s


func test_rendering_picking_and_snapping_scale_to_two_thousand_entities() -> void:
	var s: Session = _big_session()
	var doc: Document = s.document()
	var sheet: Sheet = doc.get_sheet("s1")
	assert_eq(sheet.entities.size(), COUNT)

	var t0: int = Time.get_ticks_usec()
	var list: DrawList = PlanRenderer.build(doc, "s1")
	var build_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0

	var ctx: RenderContext = RenderContext.for_sheet(doc, sheet)
	t0 = Time.get_ticks_usec()
	var index: SpatialIndex = SpatialIndex.for_sheet(doc, sheet, ctx)
	var index_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0

	t0 = Time.get_ticks_usec()
	for i: int in 200:
		HitTest.pick(sheet, ctx, Vector2(10000 + i * 10, 7000), 100.0, [], index)
	var pick_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0

	t0 = Time.get_ticks_usec()
	for i: int in 200:
		SnapEngine.snap(sheet, Vector2(10000 + i * 10, 7000), 100.0, {"index": index})
	var snap_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0

	t0 = Time.get_ticks_usec()
	for i: int in 20:
		HitTest.pick(sheet, ctx, Vector2(10000 + i * 10, 7000), 100.0)
	var linear_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0

	gut.p("2000 entities: build %.1f ms (%d ops), index %.1f ms, pick %.3f ms (linear scan: %.1f ms), snap %.3f ms" % [build_ms, list.ops.size(), index_ms, pick_ms, linear_ms, snap_ms])
	assert_true(list.ops.size() >= COUNT)
	assert_lt(build_ms, 1500.0, "full rebuild stays well under 1.5 s (it only happens when the document changes)")
	assert_lt(pick_ms, 4.0, "picking per mouse move fits a 16 ms frame with room to spare")
	assert_lt(snap_ms, 4.0, "snapping per mouse move")
	assert_lt(pick_ms * 3.0, linear_ms, "the index is clearly faster than scanning everything")
