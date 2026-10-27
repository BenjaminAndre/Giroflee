extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Placing the unifilaire on its page and drawing it (SRD section 8, FR-UNI-6, FR-UNI-7).

var s: Session
var doc: Document
var uni: Sheet


func before_each() -> void:
	s = TestKit.session()
	assert_true(s.run_one("sheet.add", {"id": "uni", "kind": "unifilaire", "props": Document.unifilaire_props()}).ok, s.last_error)
	TestKit.add_sheet(s, "p1", "Rez")
	doc = s.document()
	uni = doc.get_sheet("uni")


func _sym(id: String, type: String, circuit: String, index: int, extra: Dictionary = {}) -> void:
	var props: Dictionary = {"symbol_type": type, "pos": [1000, 1000], "circuit": circuit, "index": index}
	props.merge(extra, true)
	assert_true(TestKit.add_entity(s, "p1", id, "symbol", props).ok, s.last_error)


func _put(section: String, key: String, value: Variant) -> void:
	assert_true(s.run_one("doc.set", {"section": section, "key": key, "value": value}).ok, s.last_error)


func _layout() -> UnifilaireLayout:
	var model: UniModel = UnifilaireBuilder.derive(doc)
	return UnifilaireLayout.compute(doc, uni, model)


func _list(options: Dictionary = {}) -> DrawList:
	return PlanRenderer.build(doc, "uni", options)


func _texts(list: DrawList) -> Array[String]:
	var out: Array[String] = []
	for op: DrawOp in list.ops:
		if op.kind == DrawOp.TEXT:
			out.append(op.text)
	return out


# --- layout -----------------------------------------------------------------------------------------


func test_columns_sit_side_by_side_inside_the_page() -> void:
	for letter: String in ["A", "B", "C", "D"]:
		_sym("s%s" % letter, "lamp", letter, 1)
	var layout: UnifilaireLayout = _layout()
	assert_eq(layout.slot_x.size(), 4)
	for i: int in layout.slot_x.size():
		assert_gte(layout.slot_x[i], layout.x_cols0)
		assert_lte(layout.slot_x[i] + layout.slot_w[i], layout.x_end + 0.01)
		if i > 0:
			assert_almost_eq(layout.slot_x[i], layout.slot_x[i - 1] + layout.slot_w[i - 1], 0.001, "no gap and no overlap")
	assert_eq(layout.warnings, [])


func test_devices_take_a_slot_on_the_bus() -> void:
	_sym("a", "lamp", "A", 1)
	_sym("b", "lamp", "B", 1)
	_put("board", "bus", [{"type": "circuit", "letter": "A"}, {"type": "device", "id": "d", "catalog": "diff_40a_30ma_a"}, {"type": "circuit", "letter": "B"}])
	var layout: UnifilaireLayout = _layout()
	assert_eq(layout.slot_w[1], UnifilaireLayout.DEVICE_W)
	assert_almost_eq(layout.slot_x[2], layout.slot_x[1] + UnifilaireLayout.DEVICE_W, 0.001)


func test_too_many_circuits_shrink_the_columns_then_warn() -> void:
	for i: int in 26:
		_sym("s%d" % i, "lamp", char(65 + i), 1)
	var layout: UnifilaireLayout = _layout()
	assert_eq(layout.col_w, UnifilaireLayout.MIN_COL_W)
	assert_true(layout.warnings.size() > 0, "the content cannot fit the page width")


func test_rows_shrink_to_fit_and_warn_when_cramped() -> void:
	_sym("a", "lamp", "A", 1)
	assert_eq(_layout().row_h, UnifilaireLayout.MAX_ROW_H, "a few rows get the comfortable height")
	_sym("b", "lamp", "A", 30)
	var cramped: UnifilaireLayout = _layout()
	assert_lt(cramped.row_h, UnifilaireLayout.MIN_ROW_H)
	assert_true(cramped.warnings.size() > 0)
	assert_lt(cramped.row_center(30), 297.0 - PlanTheme.CARTOUCHE_HEIGHT, "the last row stays above the cartouche")


func test_points_are_regions_and_clicking_finds_them() -> void:
	_sym("sw", "switch", "A", 1)
	_sym("la", "lamp", "A", 1)
	_sym("so", "socket", "A", 3)
	var layout: UnifilaireLayout = _layout()
	var column: UnifilaireLayout.Region = layout.region_of("column", "A")
	var x: float = column.rect.get_center().x
	var third: UnifilaireLayout.Region = layout.hit(Vector2(x, layout.row_center(3)))
	assert_eq([third.kind, third.letter, third.index], ["point", "A", 3])
	assert_eq(third.symbol_ids, ["so"])
	var first: UnifilaireLayout.Region = layout.hit(Vector2(x, layout.row_center(1)))
	assert_eq(first.symbol_ids, ["la", "sw"])
	assert_eq(layout.hit(Vector2(x, layout.y_bus - 12.0)).kind, "column", "the header is the column")
	assert_null(layout.hit(Vector2(5.0, 5.0)))


func test_insertion_index_follows_the_pointer_along_the_bus() -> void:
	_sym("a", "lamp", "A", 1)
	_sym("b", "lamp", "B", 1)
	var layout: UnifilaireLayout = _layout()
	assert_eq(layout.insertion_index(layout.slot_x[0] + 1.0), 0)
	assert_eq(layout.insertion_index(layout.slot_x[1] + 1.0), 1)
	assert_eq(layout.insertion_index(layout.bus_end() + 50.0), 2)


# --- drawing ----------------------------------------------------------------------------------------


func test_the_page_shows_letters_titles_protection_and_ruler() -> void:
	_sym("a", "lamp", "A", 1)
	_put("circuits", "A", {"title": "Salon", "breaker": "breaker_c40_3ka"})
	var texts: Array[String] = _texts(_list())
	for wanted: String in ["A", "Salon", "C40 A", "3 kA", "XGB 3G2,5 Cca", "1", "8"]:
		assert_true(texts.has(wanted), "shows '%s'" % wanted)
	assert_true(texts.has("Unifilaire"), "the sheet title is drawn like on a plan")
	var ruler: Array[String] = []
	for op: DrawOp in _list().ops:
		if op.layer == "unifilaire_ruler":
			ruler.append(op.text)
	assert_eq(ruler, ["1", "2", "3", "4", "5", "6", "7", "8"], "the ruler stops at the minimum rows")


func test_the_head_chain_and_devices_are_drawn_from_the_catalogue() -> void:
	_sym("a", "lamp", "A", 1)
	_put("board", "head", [{"id": "h1", "catalog": "meter_kwh_27a"}, {"id": "h2", "catalog": "breaker_c40_3ka"}])
	_put("board", "bus", [{"type": "device", "id": "d", "catalog": "diff_40a_30ma_a"}, {"type": "circuit", "letter": "A"}])
	var texts: Array[String] = _texts(_list())
	for wanted: String in ["kWh", "27 A", "C40 A", "30 mA A"]:
		assert_true(texts.has(wanted), wanted)
	assert_false(texts.has("Tête de ligne ?"))


func test_a_missing_head_chain_is_flagged_on_the_page() -> void:
	_sym("a", "lamp", "A", 1)
	assert_true(_texts(_list()).has("Tête de ligne ?"))


func test_collapsed_items_show_their_count_and_open_points_a_question_mark() -> void:
	_sym("so", "socket", "A", 1, {"count": 3})
	_sym("sw", "switch", "A", 2)
	var texts: Array[String] = _texts(_list())
	assert_true(texts.has("x3"))
	assert_true(texts.has("?"))


func test_a_spare_column_says_so() -> void:
	_put("board", "bus", [{"type": "circuit", "letter": "F"}])
	var texts: Array[String] = _texts(_list())
	assert_true(texts.has("F"))
	assert_true(texts.has("Réserve"))


func test_every_symbol_of_a_point_is_drawn_with_its_unifilaire_artwork() -> void:
	_sym("sw", "switch", "A", 1)
	_sym("la", "lamp", "A", 1)
	var shapes: int = 0
	for op: DrawOp in _list().ops:
		if op.layer == "unifilaire_symbols":
			shapes += 1
	assert_gt(shapes, 2, "the switch (circle and tick) and the lamp (circle and cross)")


func test_the_selection_is_tinted_and_the_drop_mark_drawn() -> void:
	_sym("a", "lamp", "A", 1)
	var plain: DrawList = _list()
	var tinted: DrawList = _list({"selected": {"kind": "column", "letter": "A"}})
	assert_gt(tinted.ops.size(), plain.ops.size())
	var marks: int = 0
	for op: DrawOp in _list({"drop_at": 0}).ops:
		if op.layer == "unifilaire_drop":
			marks += 1
	assert_eq(marks, 1)


func test_drawing_is_deterministic_and_changes_with_the_plans() -> void:
	_sym("a", "lamp", "A", 1)
	var first: DrawList = _list()
	var again: DrawList = _list()
	assert_eq(first.ops.size(), again.ops.size())
	for i: int in first.ops.size():
		assert_eq(first.ops[i].points, again.ops[i].points)
		assert_eq(first.ops[i].text, again.ops[i].text)
	_sym("b", "lamp", "B", 1)
	assert_gt(_list().ops.size(), first.ops.size())


func test_the_plan_renderer_still_draws_plans_and_the_unifilaire_has_no_plan_content() -> void:
	_sym("a", "lamp", "A", 1)
	var plan: DrawList = PlanRenderer.build(doc, "p1")
	var found: bool = false
	for op: DrawOp in plan.ops:
		found = found or op.layer == "symbols"
	assert_true(found)
	for op: DrawOp in _list().ops:
		assert_ne(op.layer, "symbols", "the plan symbols are not drawn on the unifilaire")
