extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Drawing an electric symbol: pack artwork placed on the plan (SRD 5.1, 6.2, FR-SYM-1, FR-LOOK-2).

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


func _symbol(props: Dictionary) -> Entity:
	var base: Dictionary = {"symbol_type": "lamp", "pos": [10000, 5000], "circuit": "A", "index": 1}
	base.merge(props, true)
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec("symbol"), base, true)
	assert_true(normalized["ok"], str(normalized["error"]))
	return Entity.new("sym", "symbol", normalized["props"])


func _ops(entity: Entity, ctx: RenderContext = null) -> DrawList:
	var list: DrawList = DrawList.new()
	EntityGeometry.add_ops(entity, ctx if ctx != null else _ctx(), false, list)
	return list


func _body_ops(list: DrawList) -> Array[DrawOp]:
	var out: Array[DrawOp] = []
	for op: DrawOp in list.ops:
		if op.layer == "symbols":
			out.append(op)
	return out


func _texts(list: DrawList) -> Array[DrawOp]:
	var out: Array[DrawOp] = []
	for op: DrawOp in list.ops:
		if op.kind == DrawOp.TEXT:
			out.append(op)
	return out


# --- context -----------------------------------------------------------------------------------


func test_the_render_context_carries_the_pack_library_and_symbol_scale() -> void:
	var ctx: RenderContext = _ctx()
	assert_not_null(ctx.library)
	assert_true(ctx.library.has_type("lamp"))
	assert_eq(ctx.symbol_scale, 1.0)
	assert_false(ctx.circuit_colors, "exports are black and white by default (FR-LOOK-2)")
	assert_eq(ctx.dimmed_circuits, [])


func test_symbol_scale_is_a_project_setting_that_must_be_positive() -> void:
	assert_eq(doc.config["symbol_scale"], 1.0)
	assert_true(s.run_one("doc.set", {"section": "config", "key": "symbol_scale", "value": 1.5}).ok)
	assert_false(s.run_one("doc.set", {"section": "config", "key": "symbol_scale", "value": 0}).ok)
	assert_false(s.run_one("doc.set", {"section": "config", "key": "symbol_scale", "value": 10}).ok, "an absurd scale is refused")


# --- size and placement --------------------------------------------------------------------------


func test_a_lamp_is_three_page_millimetres_in_radius_at_the_sheet_scale() -> void:
	var bounds: Rect2 = EntityGeometry.bounds(_symbol({}), _ctx())
	assert_almost_eq(bounds.get_center().x, 10000.0, 1.0)
	assert_almost_eq(bounds.get_center().y, 5000.0, 1.0)
	assert_almost_eq(bounds.size.x, 2.0 * 3.0 * 50.0 + 0.35 * 50.0, 2.0, "diameter 6 mm of page at 1:50, plus the stroke")


func test_symbols_keep_their_size_on_the_page_when_the_scale_changes() -> void:
	s.run_one("sheet.update", {"id": "s1", "props": {"scale_den": 100}})
	var bounds: Rect2 = EntityGeometry.bounds(_symbol({}), _ctx())
	assert_almost_eq(bounds.size.x, 2.0 * 3.0 * 100.0 + 0.35 * 100.0, 2.0, "twice as many world mm: the same size on paper")


func test_the_project_symbol_scale_resizes_every_symbol() -> void:
	s.run_one("doc.set", {"section": "config", "key": "symbol_scale", "value": 2.0})
	var bounds: Rect2 = EntityGeometry.bounds(_symbol({}), _ctx())
	assert_almost_eq(bounds.size.x, 2.0 * 3.0 * 50.0 * 2.0 + 0.35 * 50.0 * 2.0, 3.0, "FR-CSYM-2: one scale for the type everywhere")


func test_artwork_y_down_becomes_world_y_up_so_rotation_zero_faces_down() -> void:
	var socket: Entity = _symbol({"symbol_type": "socket", "circuit": "B"})
	var bounds: Rect2 = EntityGeometry.bounds(socket, _ctx())
	assert_true(bounds.position.y < 5000.0 - 100.0, "the bowl hangs below the anchor on the page")
	assert_true(bounds.end.y < 5000.0 + 150.0, "only the short earth tick is on the other side")


func test_rotation_is_counter_clockwise() -> void:
	var turned: Entity = _symbol({"symbol_type": "socket", "circuit": "B", "rotation": 90})
	var bounds: Rect2 = EntityGeometry.bounds(turned, _ctx())
	assert_true(bounds.end.x > 10000.0 + 100.0, "rotating 'down' by +90 degrees CCW points it to +x")


func test_flip_h_mirrors_the_artwork() -> void:
	var plain: Rect2 = EntityGeometry.bounds(_symbol({"symbol_type": "switch"}), _ctx())
	var flipped: Rect2 = EntityGeometry.bounds(_symbol({"symbol_type": "switch", "flip_h": true}), _ctx())
	assert_true(plain.end.x - 10000.0 > 100.0, "the switch lever leans right")
	assert_true(10000.0 - flipped.position.x > 100.0, "flipped, it leans left")


func test_flip_v_mirrors_vertically() -> void:
	var plain: Rect2 = EntityGeometry.bounds(_symbol({"symbol_type": "switch"}), _ctx())
	var flipped: Rect2 = EntityGeometry.bounds(_symbol({"symbol_type": "switch", "flip_v": true}), _ctx())
	assert_true(plain.end.y - 5000.0 > 100.0, "lever up on the page")
	assert_true(5000.0 - flipped.position.y > 100.0, "flipped, lever down")


# --- drawing ops -----------------------------------------------------------------------------------


func test_a_lamp_is_drawn_as_stroked_polylines_in_black() -> void:
	var body: Array[DrawOp] = _body_ops(_ops(_symbol({})))
	assert_true(body.size() >= 2, "circle and cross")
	for op: DrawOp in body:
		assert_eq(op.kind, DrawOp.POLYLINE)
		assert_eq(op.color, PlanTheme.BLACK)
		assert_almost_eq(op.width, 0.35 * 50.0, 0.01, "stroke width is a page weight")
		assert_eq(op.entity_id, "sym")
	assert_true(body[0].closed, "the circle is closed")


func test_panel_and_meter_are_green_markers_with_a_caption() -> void:
	var panel: DrawList = _ops(_symbol({"symbol_type": "panel", "circuit": ""}))
	for op: DrawOp in _body_ops(panel):
		assert_eq(op.color, PlanTheme.GREEN, "markers are green, as on the reference plans")
	var captions: Array[DrawOp] = _texts(panel)
	assert_eq(captions.size(), 1)
	assert_eq(captions[0].text, "TGBT")
	assert_eq(captions[0].color, PlanTheme.GREEN)
	assert_eq(_texts(_ops(_symbol({"symbol_type": "meter", "circuit": ""})))[0].text, "kWh")


func test_symbols_are_not_drawn_in_the_ghost_view() -> void:
	var list: DrawList = DrawList.new()
	EntityGeometry.add_ops(_symbol({}), _ctx(), true, list)
	assert_eq(list.ops.size(), 0)


func test_an_unknown_symbol_type_is_drawn_as_a_marked_placeholder_not_dropped() -> void:
	var entity: Entity = _symbol({"symbol_type": "teleporter"})
	var list: DrawList = _ops(entity)
	assert_true(list.ops.size() >= 1, "never silently invisible")
	var bounds: Rect2 = EntityGeometry.bounds(entity, _ctx())
	assert_true(bounds.size.x > 10.0, "and still selectable")


# --- labels --------------------------------------------------------------------------------------------


func test_the_label_is_circuit_letter_plus_index() -> void:
	assert_eq(SymbolGeometry.label_text(_symbol({"circuit": "A", "index": 2})), "A2")
	assert_eq(SymbolGeometry.label_text(_symbol({"circuit": "H", "index": 11})), "H11")
	assert_eq(SymbolGeometry.label_text(_symbol({"circuit": "B", "index": 0})), "B?", "no index assigned yet")
	assert_eq(SymbolGeometry.label_text(_symbol({"circuit": "", "index": 0})), "", "no circuit, no label")
	assert_eq(SymbolGeometry.label_text(_symbol({"symbol_type": "panel", "circuit": ""})), "", "markers carry no label")


func test_the_count_badge_is_a_separate_xn_text() -> void:
	assert_eq(SymbolGeometry.count_text(_symbol({"count": 1})), "")
	assert_eq(SymbolGeometry.count_text(_symbol({"count": 3})), "x3")
	var texts: Array[DrawOp] = _texts(_ops(_symbol({"symbol_type": "socket", "count": 3, "index": 4})))
	var found: Array[String] = []
	for op: DrawOp in texts:
		found.append(op.text)
	assert_true(found.has("A4") and found.has("x3"), "two separate texts: %s" % str(found))


func test_the_count_badge_is_away_from_the_circuit_label() -> void:
	var texts: Array[DrawOp] = _texts(_ops(_symbol({"symbol_type": "socket", "count": 3, "index": 4})))
	var label: Vector2 = Vector2.ZERO
	var badge: Vector2 = Vector2.ZERO
	for op: DrawOp in texts:
		if op.text == "A4":
			label = op.points[0]
		elif op.text == "x3":
			badge = op.points[0]
	assert_true(label.distance_to(badge) > 150.0, "never adjacent to the letter (SRD 5.2)")


func test_default_label_position_is_to_the_lower_right_like_the_reference_plans() -> void:
	var offset: Vector2 = SymbolGeometry.default_label_offset(_symbol({}), _ctx())
	assert_true(offset.x > 0.0 and offset.y < 0.0)
	var label: DrawOp = _texts(_ops(_symbol({})))[0]
	assert_true(label.points[0].x > 10000.0 and label.points[0].y < 5000.0)
	assert_eq(label.anchor, "center")


func test_an_explicit_label_offset_wins() -> void:
	var entity: Entity = _symbol({"label_offset": [-500, 400]})
	var label: DrawOp = _texts(_ops(entity))[0]
	assert_almost_eq(label.points[0].x, 9500.0, 0.5)
	assert_true(absf(label.points[0].y - 5400.0) < 120.0, "centred on the offset (baseline adjusted)")


func test_label_text_size_follows_the_project_font() -> void:
	var label: DrawOp = _texts(_ops(_symbol({})))[0]
	assert_almost_eq(label.size, _ctx().pt_to_world(10.0 * 0.8), 0.01, "symbol labels are 0.8 x the base size")
	s.run_one("doc.set", {"section": "config", "key": "font_size_pt", "value": 20})
	assert_almost_eq(_texts(_ops(_symbol({})))[0].size, _ctx().pt_to_world(16.0), 0.01)


# --- circuit colours and focus ----------------------------------------------------------------------


func test_circuit_colours_are_an_on_screen_option_only() -> void:
	var ctx: RenderContext = _ctx()
	ctx.circuit_colors = true
	var coloured: DrawList = _ops(_symbol({"circuit": "C"}), ctx)
	for op: DrawOp in _body_ops(coloured):
		assert_eq(op.color, CircuitPalette.color("C"))
	assert_ne(CircuitPalette.color("C"), PlanTheme.BLACK)
	for op: DrawOp in _body_ops(_ops(_symbol({"circuit": "C"}))):
		assert_eq(op.color, PlanTheme.BLACK, "export: black and white")


func test_a_dimmed_circuit_is_drawn_grey() -> void:
	var ctx: RenderContext = _ctx()
	ctx.circuit_colors = true
	ctx.dimmed_circuits = ["C"]
	for op: DrawOp in _body_ops(_ops(_symbol({"circuit": "C"}), ctx)):
		assert_eq(op.color, PlanTheme.GHOST)
	for op: DrawOp in _body_ops(_ops(_symbol({"circuit": "D"}), ctx)):
		assert_eq(op.color, CircuitPalette.color("D"), "other circuits are unaffected")


func test_markers_ignore_circuit_colours() -> void:
	var ctx: RenderContext = _ctx()
	ctx.circuit_colors = true
	for op: DrawOp in _body_ops(_ops(_symbol({"symbol_type": "panel", "circuit": ""}), ctx)):
		assert_eq(op.color, PlanTheme.GREEN)


func test_the_renderer_passes_display_options_to_the_context() -> void:
	TestKit.add_entity(s, "s1", "lamp", "symbol", {"symbol_type": "lamp", "pos": [3000, 3000], "circuit": "A", "index": 1})
	var plain: DrawList = PlanRenderer.build(doc, "s1", {"frame": false})
	var coloured: DrawList = PlanRenderer.build(doc, "s1", {"frame": false, "circuit_colors": true})
	var dimmed: DrawList = PlanRenderer.build(doc, "s1", {"frame": false, "circuit_colors": true, "dimmed": ["A"]})
	assert_eq(_body_ops(plain)[0].color, PlanTheme.BLACK)
	assert_eq(_body_ops(coloured)[0].color, CircuitPalette.color("A"))
	assert_eq(_body_ops(dimmed)[0].color, PlanTheme.GHOST)


func test_symbols_are_drawn_above_walls_and_below_nothing_else_of_theirs() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [4000, 0]])
	TestKit.add_entity(s, "s1", "lamp", "symbol", {"symbol_type": "lamp", "pos": [3000, 3000], "circuit": "A", "index": 1})
	var layers: Array[String] = []
	for op: DrawOp in PlanRenderer.build(doc, "s1", {"frame": false}).ops:
		if not layers.has(op.layer):
			layers.append(op.layer)
	assert_true(layers.find("walls") < layers.find("symbols"), "symbols above walls")


# --- picking ---------------------------------------------------------------------------------------------


func test_a_symbol_can_be_picked_on_its_body() -> void:
	TestKit.add_entity(s, "s1", "lamp", "symbol", {"symbol_type": "lamp", "pos": [3000, 3000], "circuit": "A", "index": 1})
	var ctx: RenderContext = _ctx()
	assert_eq(HitTest.pick(sheet, ctx, Vector2(3040, 2980), 20.0), "lamp")
	assert_eq(HitTest.pick(sheet, ctx, Vector2(3600, 3000), 20.0), "")


func test_symbols_win_a_click_over_the_wall_they_sit_on() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 3000], [8000, 3000]])
	TestKit.add_entity(s, "s1", "sock", "symbol", {"symbol_type": "socket", "pos": [3000, 3000], "circuit": "B", "index": 1})
	assert_eq(HitTest.pick(sheet, _ctx(), Vector2(3000, 2950), 40.0), "sock")
	assert_eq(HitTest.pick(sheet, _ctx(), Vector2(6000, 3000), 40.0), "w")
