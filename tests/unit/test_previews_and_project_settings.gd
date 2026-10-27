extends GutTest
@warning_ignore_start("unsafe_call_argument")
## M2b: previews look final (FR-PREV), and the display settings are project-wide (FR-PROJ-1).

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


# --- FR-PREV: what you see while drawing is what you get -----------------------------------------


func _polygons(list: DrawList) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for op: DrawOp in list.ops:
		if op.kind == DrawOp.POLYGON:
			out.append(op.points)
	return out


func test_a_wall_in_progress_is_drawn_exactly_like_the_finished_wall() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.click(Vector2(6000, 2000))
	kit.move(Vector2(6000, 5000))
	var preview: DrawList = kit.model.preview_list()
	var wall_ops: Array[DrawOp] = []
	for op: DrawOp in preview.ops:
		if op.kind == DrawOp.POLYGON:
			wall_ops.append(op)
	assert_true(wall_ops.size() >= 1, "the first segment already shows as a wall")
	for op: DrawOp in wall_ops:
		assert_eq(op.fill, PlanTheme.BLACK, "same colour as a finished wall (not blue, not translucent)")
		assert_eq(op.fill.a, 1.0)
	kit.click(Vector2(6000, 5000), false, true)
	var final_polys: Array[PackedVector2Array] = _polygons(PlanRenderer.build(kit.doc(), kit.model.active_sheet_id, {"frame": false}))
	var preview_polys: Array[PackedVector2Array] = []
	for op: DrawOp in wall_ops:
		preview_polys.append(op.points)
	assert_eq(final_polys.size() >= 1, true)
	assert_eq(preview_polys[0], final_polys[0], "same geometry as the committed wall (same code path)")


func test_the_first_segment_is_visible_before_a_second_point_exists() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.move(Vector2(5000, 2000))
	var wall_polys: int = 0
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.POLYGON:
			wall_polys += 1
	assert_true(wall_polys >= 1, "rubber band is drawn as a wall from the very first click")


func test_the_length_readout_is_neutral_not_wall_coloured() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.move(Vector2(5000, 2000))
	var readouts: int = 0
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.TEXT:
			readouts += 1
			assert_ne(op.color, PlanTheme.BLUE, "not the blue that confused the author")
	assert_eq(readouts, 1)


func test_block_and_placement_previews_look_final_too() -> void:
	kit.key(KEY_S)
	kit.move(Vector2(3000, 3000))
	kit.press(Vector2(3000, 3000))
	kit.move(Vector2(5000, 4000))
	var block_fill: Color = Color(0, 0, 0, 0)
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.POLYGON:
			block_fill = op.fill
	assert_eq(block_fill, PlanTheme.GREY_FILL, "the block preview has the finished block's fill")
	kit.release(Vector2(5000, 4000))
	kit.key(KEY_E)
	kit.move(Vector2(9000, 5000))
	var stair_black: bool = false
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.POLYGON and op.fill == PlanTheme.BLACK:
			stair_black = true
	assert_true(stair_black, "stair preview is black like a placed stair")


# --- FR-PROJ-1: project-wide display settings ---------------------------------------------------


func test_display_settings_live_in_the_project_config_not_in_sheets() -> void:
	for key: String in ["frame_cols", "frame_rows", "title_pos_mm", "ghost_on", "hints"]:
		assert_true(Schema.CONFIG_SPEC.has(key), "%s is a project setting" % key)
		assert_false(Schema.SHEET_SPEC.has(key), "%s is no longer a sheet setting" % key)
	assert_true(Schema.SHEET_SPEC.has("ghost_sheets"), "which étages are ghosted stays per sheet")
	assert_true(Schema.SHEET_SPEC.has("scale_den") and Schema.SHEET_SPEC.has("paper_w_mm") and Schema.SHEET_SPEC.has("grid_step_mm"))
	var config: Dictionary = kit.doc().config
	assert_eq(config["frame_cols"], 17)
	assert_eq(config["frame_rows"], 8)
	assert_eq(config["title_pos_mm"], [366, 34])
	assert_eq(config["ghost_on"], false, "ghost view is off by default")
	assert_eq(config["hints"], true)


func test_changing_the_frame_changes_every_etage() -> void:
	kit.model.new_sheet()
	kit.model.set_config("frame_cols", 10)
	kit.model.set_config("frame_rows", 0)
	for sheet_id: String in kit.doc().plan_ids():
		var texts: Array[String] = []
		for op: DrawOp in PlanRenderer.build(kit.doc(), sheet_id).ops:
			if op.layer == "frame" and op.kind == DrawOp.TEXT:
				texts.append(op.text)
		assert_eq(texts.size(), 10, "10 column numbers and no row letters on every sheet")


func test_the_title_position_is_shared_by_every_etage() -> void:
	kit.model.new_sheet()
	kit.model.set_config("title_pos_mm", [100, 20])
	var positions: Array[Vector2] = []
	for sheet_id: String in kit.doc().plan_ids():
		var list: DrawList = PlanRenderer.build(kit.doc(), sheet_id)
		positions.append(list.ops[list.ops.size() - 1].points[0])
	assert_eq(positions[0], positions[1])
	assert_eq(positions[0], Vector2(5000, 13850), "x = 100 mm * 50, y = (297 - 20) mm * 50")


func test_ghost_switch_is_global_but_the_ghosted_etages_are_per_sheet() -> void:
	kit.model.new_sheet()
	kit.model.new_sheet()
	var order: Array[String] = kit.doc().plan_ids()
	kit.model.set_active_sheet(order[0])
	kit.add("wall", {"points": [[0, 0], [1000, 0]]}, "w-rez")
	kit.model.set_active_sheet(order[1])
	kit.model.set_sheet_props({"ghost_sheets": [order[0]]})
	kit.model.set_active_sheet(order[2])
	kit.model.set_sheet_props({"ghost_sheets": [order[1]]})
	assert_eq(PlanRenderer.build(kit.doc(), order[1]).count_layer("walls_ghost"), 0, "switch off: nothing ghosted anywhere")
	kit.model.toggle_ghost()
	assert_true(kit.doc().config["ghost_on"])
	assert_eq(PlanRenderer.build(kit.doc(), order[1]).count_layer("walls_ghost"), 1, "one switch turns it on for every étage")
	assert_eq(kit.doc().get_sheet(order[2]).props["ghost_sheets"], [order[1]], "each sheet keeps its own selection")
	kit.model.toggle_ghost()
	assert_false(kit.doc().config["ghost_on"])


func test_first_ghost_activation_picks_the_etage_below_when_none_is_chosen() -> void:
	kit.model.new_sheet()
	var below: String = kit.doc().plan_ids()[0]
	kit.model.toggle_ghost()
	assert_eq(kit.sheet().props["ghost_sheets"], [below])


func test_hints_toggle_is_global() -> void:
	kit.model.new_sheet()
	kit.model.toggle_hints()
	assert_false(kit.doc().config["hints"])
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	assert_false(kit.doc().config["hints"], "same on every étage")


func test_sheet_update_rejects_the_moved_properties() -> void:
	for key: String in ["frame_cols", "frame_rows", "title_pos_mm", "ghost_on", "hints"]:
		var result: CommandResult = kit.session.run_one("sheet.update", {"id": kit.model.active_sheet_id, "props": {key: 1}})
		assert_false(result.ok, "%s can only be set on the project" % key)


func test_a_new_etage_inherits_paper_scale_and_grid_only() -> void:
	kit.model.set_sheet_props({"scale_den": 100, "grid_step_mm": 250})
	kit.model.new_sheet()
	assert_eq(kit.sheet().props["scale_den"], 100)
	assert_eq(kit.sheet().props["grid_step_mm"], 250)
	assert_false(kit.sheet().props.has("frame_cols"))


func test_config_values_are_validated() -> void:
	assert_false(kit.model.set_config("frame_cols", -1).ok, "a negative count is refused")
	assert_false(kit.model.set_config("frame_rows", 27).ok, "rows are lettered A-Z at most")
	assert_false(kit.model.set_config("title_pos_mm", [1]).ok)
	assert_true(kit.model.set_config("frame_cols", 0).ok)
	assert_true(kit.model.set_config("ghost_on", true).ok)


# --- format 2 and its migration ------------------------------------------------------------------


func test_v1_files_migrate_through_every_format() -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file("res://tests/fixtures/project_v1.giroflee")
	assert_eq(loaded.error, "", "a version 1 file still opens")
	var doc: Document = loaded.document
	assert_eq(doc.config["frame_cols"], 12, "taken from the first sheet of the old file")
	assert_eq(doc.config["frame_rows"], 5)
	assert_eq(doc.config["title_pos_mm"], [300, 30])
	assert_eq(doc.config["ghost_on"], true)
	assert_eq(doc.config["hints"], false)
	for sheet_id: String in doc.sheet_order:
		var props: Dictionary = doc.get_sheet(sheet_id).props
		assert_false(props.has("frame_cols") or props.has("ghost_on") or props.has("hints") or props.has("title_pos_mm"))
	assert_eq(doc.get_sheet(doc.sheet_order[2]).props["ghost_sheets"], [doc.sheet_order[1]], "per-sheet ghost choice kept (the unifilaire is first)")
	assert_eq(doc.check_integrity(), "")


func test_a_migrated_file_saves_in_the_current_format_and_reloads_identically() -> void:
	var doc: Document = DocumentIO.load_file("res://tests/fixtures/project_v1.giroflee").document
	var text: String = DocumentIO.to_json(doc)
	assert_string_contains(text, "\"format_version\": 3")
	var again: DocumentIO.LoadResult = DocumentIO.from_json(text)
	assert_eq(again.error, "")
	assert_eq(DocumentIO.to_json(again.document), text)


func test_a_v1_file_without_sheets_migrates_with_defaults() -> void:
	var raw: Dictionary = {"format_version": 1, "pack_ref": "belgium", "config": Schema.default_config(), "cartouche": {}, "board": {}, "circuits": {}, "sheets": []}
	var config: Dictionary = raw["config"]
	for key: String in ["frame_cols", "frame_rows", "title_pos_mm", "ghost_on", "hints"]:
		config.erase(key)
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(raw)
	assert_eq(loaded.error, "")
	assert_eq(loaded.document.config["frame_cols"], 17)


func test_a_file_from_the_future_is_still_refused() -> void:
	var raw: Dictionary = {"format_version": 4}
	assert_string_contains(DocumentIO.from_dict(raw).error, "newer version")
