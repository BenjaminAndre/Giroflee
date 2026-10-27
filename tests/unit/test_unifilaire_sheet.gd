extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD FR-TAB-1, FR-TAB-3: one unifilaire sheet, always first; étages can be reordered but never
## placed before it. Format 3 adds the sheet to older files (FR-FILE-2).

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	doc = s.document()


func _add_uni(index: Variant = null) -> CommandResult:
	var payload: Dictionary = {"id": "uni", "kind": "unifilaire", "props": Document.unifilaire_props()}
	if index != null:
		payload["index"] = index
	return s.run_one("sheet.add", payload)


func _add_plan(id: String, index: Variant = null) -> CommandResult:
	var payload: Dictionary = {"id": id, "kind": "plan", "props": {"name": id}}
	if index != null:
		payload["index"] = index
	return s.run_one("sheet.add", payload)


# --- the unifilaire sheet -------------------------------------------------------------------------


func test_the_unifilaire_is_added_first_even_after_plans() -> void:
	_add_plan("p1")
	_add_plan("p2")
	assert_true(_add_uni().ok, s.last_error)
	assert_eq(doc.sheet_order, ["uni", "p1", "p2"])
	assert_eq(doc.unifilaire_sheet().id, "uni")
	assert_eq(doc.check_integrity(), "")


func test_a_second_unifilaire_is_refused() -> void:
	_add_uni()
	assert_false(_add_uni().ok)
	assert_string_contains(s.last_error, "already")


func test_the_unifilaire_cannot_be_added_anywhere_but_first() -> void:
	_add_plan("p1")
	assert_false(_add_uni(1).ok)
	assert_true(_add_uni(0).ok)


func test_the_unifilaire_cannot_be_removed_or_moved() -> void:
	_add_uni()
	_add_plan("p1")
	_add_plan("p2")
	assert_false(s.run_one("sheet.remove", {"id": "uni"}).ok)
	assert_false(s.run_one("sheet.move", {"id": "uni", "index": 2}).ok)
	assert_eq(doc.sheet_order, ["uni", "p1", "p2"])


func test_plans_cannot_go_before_the_unifilaire() -> void:
	_add_uni()
	assert_false(_add_plan("p1", 0).ok, "index 0 belongs to the unifilaire")
	assert_true(_add_plan("p1", 1).ok)
	assert_true(_add_plan("p2").ok, "appended after the others")
	assert_false(s.run_one("sheet.move", {"id": "p2", "index": 0}).ok)
	assert_eq(doc.sheet_order, ["uni", "p1", "p2"])


func test_plans_can_be_reordered_in_one_undo_step() -> void:
	_add_uni()
	_add_plan("p1")
	_add_plan("p2")
	_add_plan("p3")
	assert_true(s.run_one("sheet.move", {"id": "p3", "index": 1}).ok, s.last_error)
	assert_eq(doc.sheet_order, ["uni", "p3", "p1", "p2"])
	s.undo()
	assert_eq(doc.sheet_order, ["uni", "p1", "p2", "p3"])


func test_a_plan_is_still_removable_and_the_unifilaire_can_be_renamed() -> void:
	_add_uni()
	_add_plan("p1")
	assert_true(s.run_one("sheet.remove", {"id": "p1"}).ok)
	assert_true(s.run_one("sheet.update", {"id": "uni", "props": {"name": "Schéma"}}).ok)
	assert_eq(doc.unifilaire_sheet().display_name(), "Schéma")


func test_the_unifilaire_holds_no_entities() -> void:
	_add_uni()
	var result: CommandResult = s.run_one("entity.add", {"sheet": "uni", "items": [{"id": "w", "type": "wall", "props": {"points": [[0, 0], [10, 0]]}}]})
	assert_false(result.ok)


func test_the_default_unifilaire_is_a_page_in_millimetres() -> void:
	var props: Dictionary = Document.unifilaire_props()
	assert_eq(props["scale_den"], 1)
	assert_eq([props["paper_w_mm"], props["paper_h_mm"]], [420, 297])


# --- integrity and files --------------------------------------------------------------------------


func test_a_file_with_the_unifilaire_not_first_is_refused() -> void:
	_add_plan("p1")
	_add_uni()
	var data: Dictionary = doc.to_dict()
	var sheets: Array = data["sheets"]
	sheets.reverse()
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(data)
	assert_null(loaded.document)
	assert_string_contains(loaded.error, "unifilaire")


func test_the_current_format_is_3() -> void:
	assert_eq(Document.CURRENT_FORMAT_VERSION, 3)
	assert_eq(doc.to_dict()["format_version"], 3)


func test_format_2_files_get_the_unifilaire_first() -> void:
	_add_plan("p1")
	var data: Dictionary = doc.to_dict()
	data["format_version"] = 2
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(data)
	assert_not_null(loaded.document, loaded.error)
	var order: Array[String] = loaded.document.sheet_order
	assert_eq(order.size(), 2)
	assert_eq(loaded.document.get_sheet(order[0]).kind, "unifilaire")
	assert_eq(order[1], "p1")


func test_an_empty_format_2_project_gets_one_too() -> void:
	var data: Dictionary = doc.to_dict()
	data["format_version"] = 2
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(data)
	assert_eq(loaded.document.sheet_order.size(), 1)


func test_migration_leaves_an_existing_unifilaire_alone() -> void:
	_add_uni()
	_add_plan("p1")
	var data: Dictionary = doc.to_dict()
	data["format_version"] = 2
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(data)
	assert_eq(loaded.document.sheet_order, ["uni", "p1"])


func test_the_old_v1_fixture_still_opens_with_a_unifilaire() -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file("res://tests/fixtures/project_v1.giroflee")
	assert_not_null(loaded.document, loaded.error)
	assert_not_null(loaded.document.unifilaire_sheet())
	assert_eq(loaded.document.get_sheet(loaded.document.sheet_order[0]).kind, "unifilaire")
