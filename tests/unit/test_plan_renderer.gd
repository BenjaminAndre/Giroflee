extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1", "Rez")


func _doc() -> Document:
	return s.document()


func test_unknown_sheet_gives_an_empty_list() -> void:
	assert_eq(PlanRenderer.build(_doc(), "nope").ops.size(), 0)


func test_floor_title_is_the_sheet_name_in_dark_red() -> void:
	var list: DrawList = PlanRenderer.build(_doc(), "s1")
	var titles: Array[DrawOp] = []
	for op: DrawOp in list.ops:
		if op.layer == "floor_title":
			titles.append(op)
	assert_eq(titles.size(), 1)
	assert_eq(titles[0].text, "Rez")
	assert_eq(titles[0].color, PlanTheme.DARK_RED)
	assert_true(titles[0].bold)
	s.run_one("sheet.update", {"id": "s1", "props": {"name": "+1"}})
	var again: DrawList = PlanRenderer.build(_doc(), "s1")
	assert_eq(again.ops[again.ops.size() - 1].text, "+1", "typed once, shown everywhere (DRY)")


func test_title_position_is_in_page_millimetres_from_the_top_left() -> void:
	var list: DrawList = PlanRenderer.build(_doc(), "s1")
	var title: DrawOp = list.ops[list.ops.size() - 1]
	# default [366, 34] on A3 landscape at 1:50: x = 366 * 50, y = (297 - 34) * 50
	assert_eq(title.points[0], Vector2(18300, 13150))


func test_draw_order_follows_the_layer_stack() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [4000, 0]])
	TestKit.add_entity(s, "s1", "b", "grey_block", {"pos": [0, 0], "size": [500, 500]})
	TestKit.add_entity(s, "s1", "t", "text", {"pos": [0, 0], "text": "Salon"})
	TestKit.add_entity(s, "s1", "d", "opening", {"kind": "door", "pos": [500, 0], "width_mm": 900})
	var layers: Array[String] = []
	for op: DrawOp in PlanRenderer.build(_doc(), "s1", {"frame": false}).ops:
		if not layers.has(op.layer):
			layers.append(op.layer)
	assert_eq(layers, ["blocks", "openings", "walls", "labels", "floor_title"])


func test_output_is_deterministic() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [4000, 0], [4000, 3000]])
	TestKit.add_entity(s, "s1", "b", "grey_block", {"pos": [0, 0], "size": [500, 500]})
	var a: DrawList = PlanRenderer.build(_doc(), "s1")
	var b: DrawList = PlanRenderer.build(_doc(), "s1")
	assert_eq(a.ops.size(), b.ops.size())
	for i: int in a.ops.size():
		assert_eq(a.ops[i].points, b.ops[i].points)
		assert_eq(a.ops[i].layer, b.ops[i].layer)


func test_every_entity_op_is_tagged_with_its_entity() -> void:
	TestKit.add_wall(s, "s1", "wall-1", [[0, 0], [4000, 0]])
	var list: DrawList = PlanRenderer.build(_doc(), "s1", {"frame": false})
	assert_true(list.ops_for_entity("wall-1").size() >= 1)


func test_ghost_view_draws_the_chosen_sheets_in_grey_when_on() -> void:
	TestKit.add_sheet(s, "s2", "Cave")
	TestKit.add_wall(s, "s2", "cave-wall", [[0, 0], [5000, 0]])
	TestKit.add_entity(s, "s2", "cave-text", "text", {"pos": [0, 0], "text": "Cave 1"})
	s.run_one("sheet.update", {"id": "s1", "props": {"ghost_sheets": ["s2"]}})
	assert_eq(PlanRenderer.build(_doc(), "s1").count_layer("walls_ghost"), 0, "off by default (FR-PLAN-7)")
	s.run_one("sheet.update", {"id": "s1", "props": {"ghost_on": true}})
	var list: DrawList = PlanRenderer.build(_doc(), "s1")
	assert_eq(list.count_layer("walls_ghost"), 1)
	assert_eq(list.count_layer("labels"), 0, "ghost shows no text")
	assert_eq(list.ops[0].layer, "walls_ghost", "ghost is drawn first, below everything")
	assert_eq(PlanRenderer.build(_doc(), "s1", {"ghost": false}).count_layer("walls_ghost"), 0, "option override")


func test_frame_can_be_switched_off_and_by_axis() -> void:
	assert_true(PlanRenderer.build(_doc(), "s1").count_layer("frame") > 0)
	assert_eq(PlanRenderer.build(_doc(), "s1", {"frame": false}).count_layer("frame"), 0)
	s.run_one("sheet.update", {"id": "s1", "props": {"frame_cols": 0, "frame_rows": 0}})
	assert_eq(PlanRenderer.build(_doc(), "s1").count_layer("frame"), 0, "0 and 0 removes the frame")


func test_frame_labels_columns_and_rows() -> void:
	var texts: Array[String] = []
	for op: DrawOp in PlanRenderer.build(_doc(), "s1").ops:
		if op.layer == "frame" and op.kind == DrawOp.TEXT:
			texts.append(op.text)
	assert_eq(texts.size(), 17 + 8)
	assert_true(texts.has("1") and texts.has("17") and texts.has("A") and texts.has("H"))
	s.run_one("sheet.update", {"id": "s1", "props": {"frame_cols": 0}})
	var rows_only: Array[String] = []
	for op: DrawOp in PlanRenderer.build(_doc(), "s1").ops:
		if op.layer == "frame" and op.kind == DrawOp.TEXT:
			rows_only.append(op.text)
	assert_eq(rows_only.size(), 8, "0 columns removes the numbered band only")


func test_frame_geometry_stays_inside_the_page() -> void:
	var page: Rect2 = FrameBuilder.page_rect(_doc().get_sheet("s1"))
	assert_eq(page, Rect2(0, 0, 21000, 14850))
	for op: DrawOp in PlanRenderer.build(_doc(), "s1").ops:
		if op.layer == "frame" and op.kind == DrawOp.POLYLINE:
			for p: Vector2 in op.points:
				assert_true(page.grow(1.0).has_point(p), "frame point %s inside the page" % str(p))
