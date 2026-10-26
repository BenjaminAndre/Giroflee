extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session


func before_each() -> void:
	s = TestKit.session()


func _doc() -> Document:
	return s.document()


func test_add_sheet_with_defaults_appends_in_order() -> void:
	assert_true(TestKit.add_sheet(s, "a", "Cave").ok)
	assert_true(TestKit.add_sheet(s, "b", "Rez").ok)
	assert_eq(_doc().sheet_order, ["a", "b"])
	var sheet: Sheet = _doc().get_sheet("a")
	assert_eq(sheet.kind, "plan")
	assert_eq(sheet.display_name(), "Cave")
	assert_eq(sheet.props["paper_w_mm"], 420, "A3 landscape by default")
	assert_eq(sheet.props["ghost_sheets"], [], "no étage ghosted until chosen")


func test_add_sheet_at_index() -> void:
	TestKit.add_sheet(s, "a")
	TestKit.add_sheet(s, "b")
	var result: CommandResult = s.run_one("sheet.add", {"id": "c", "kind": "plan", "props": {"name": "X"}, "index": 1})
	assert_true(result.ok)
	assert_eq(_doc().sheet_order, ["a", "c", "b"])


func test_add_sheet_rejects_bad_input() -> void:
	TestKit.add_sheet(s, "a")
	assert_false(s.run_one("sheet.add", {"id": "a", "kind": "plan", "props": {"name": "dup"}}).ok, "duplicate id")
	assert_false(s.run_one("sheet.add", {"id": "", "kind": "plan", "props": {"name": "x"}}).ok, "empty id")
	assert_false(s.run_one("sheet.add", {"id": "k", "kind": "sketch", "props": {"name": "x"}}).ok, "unknown kind")
	assert_false(s.run_one("sheet.add", {"id": "n", "kind": "plan", "props": {}}).ok, "name required")
	assert_false(s.run_one("sheet.add", {"id": "p", "kind": "plan", "props": {"name": "x", "paper_w_mm": 0}}).ok, "paper must be positive")
	assert_false(s.run_one("sheet.add", {"id": "i", "kind": "plan", "props": {"name": "x"}, "index": 9}).ok, "index range")
	assert_false(s.run_one("sheet.add", {"id": "g", "kind": "plan", "props": {"name": "x", "ghost_sheets": ["zz"]}}).ok, "ghost must exist")
	assert_eq(_doc().sheet_order, ["a"], "failed commands changed nothing")


func test_update_sheet_renames_and_configures() -> void:
	TestKit.add_sheet(s, "a", "Rez")
	var result: CommandResult = s.run_one("sheet.update", {"id": "a", "props": {"name": "Rez-de-chaussée", "scale_den": 100}})
	assert_true(result.ok, result.error)
	var sheet: Sheet = _doc().get_sheet("a")
	assert_eq(sheet.display_name(), "Rez-de-chaussée")
	assert_eq(sheet.props["scale_den"], 100)
	assert_eq(sheet.props["paper_w_mm"], 420, "other props untouched")


func test_update_with_same_values_is_an_empty_patch_and_not_recorded() -> void:
	TestKit.add_sheet(s, "a", "Rez")
	var depth: int = s.history.undo_depth()
	var result: CommandResult = s.run_one("sheet.update", {"id": "a", "props": {"name": "Rez"}})
	assert_true(result.ok)
	assert_eq(result.patch.ops.size(), 0)
	assert_eq(s.history.undo_depth(), depth, "no-op not recorded in history")


func test_ghost_references_are_validated() -> void:
	TestKit.add_sheet(s, "a")
	TestKit.add_sheet(s, "b")
	assert_true(s.run_one("sheet.update", {"id": "a", "props": {"ghost_sheets": ["b"]}}).ok)
	assert_false(s.run_one("sheet.update", {"id": "a", "props": {"ghost_sheets": ["a"]}}).ok, "cannot ghost itself")
	assert_false(s.run_one("sheet.update", {"id": "a", "props": {"ghost_sheets": ["nope"]}}).ok)


func test_update_rejects_unknown_sheet_and_property() -> void:
	TestKit.add_sheet(s, "a")
	assert_false(s.run_one("sheet.update", {"id": "zz", "props": {"name": "x"}}).ok)
	assert_false(s.run_one("sheet.update", {"id": "a", "props": {"colour": 1}}).ok)
	assert_false(s.run_one("sheet.update", {"id": "a", "props": {"kind": "unifilaire"}}).ok, "kind cannot be changed")


func test_remove_sheet_removes_entities_and_ghost_references() -> void:
	TestKit.add_sheet(s, "a")
	TestKit.add_sheet(s, "b")
	TestKit.add_wall(s, "b", "w1", [[0, 0], [100, 0]])
	TestKit.add_symbol(s, "b", "sym", [0, 0])
	s.run_one("sheet.update", {"id": "a", "props": {"ghost_sheets": ["b"]}})
	var result: CommandResult = s.run_one("sheet.remove", {"id": "b"})
	assert_true(result.ok, result.error)
	assert_eq(_doc().sheet_order, ["a"])
	assert_false(_doc().has_entity("w1"))
	assert_false(_doc().has_entity("sym"))
	assert_eq(_doc().get_sheet("a").props["ghost_sheets"], [])
	assert_eq(_doc().check_integrity(), "")


func test_remove_unknown_sheet_fails() -> void:
	assert_false(s.run_one("sheet.remove", {"id": "nope"}).ok)


func test_move_sheet_reorders_tabs() -> void:
	for id: String in ["a", "b", "c"]:
		TestKit.add_sheet(s, id)
	assert_true(s.run_one("sheet.move", {"id": "c", "index": 0}).ok)
	assert_eq(_doc().sheet_order, ["c", "a", "b"])
	assert_true(s.run_one("sheet.move", {"id": "c", "index": 2}).ok)
	assert_eq(_doc().sheet_order, ["a", "b", "c"])
	assert_false(s.run_one("sheet.move", {"id": "c", "index": 3}).ok)
	assert_false(s.run_one("sheet.move", {"id": "zz", "index": 0}).ok)


func test_unifilaire_sheet_can_be_added_but_holds_no_entities() -> void:
	assert_true(s.run_one("sheet.add", {"id": "u", "kind": "unifilaire", "props": {"name": "Unifilaire"}}).ok)
	var result: CommandResult = TestKit.add_wall(s, "u", "w", [[0, 0], [1, 0]])
	assert_false(result.ok)
	assert_string_contains(result.error, "not a plan sheet")
