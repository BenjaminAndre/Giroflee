extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	TestKit.add_sheet(s, "s2")


func _doc() -> Document:
	return s.document()


func test_add_each_entity_type_with_defaults() -> void:
	var items: Array = [
		{"id": "w", "type": "wall", "props": {"points": [[0, 0], [3000, 0]]}},
		{"id": "d", "type": "opening", "props": {"kind": "door", "pos": [1000, 0], "width_mm": 900}},
		{"id": "f", "type": "opening", "props": {"kind": "window", "pos": [2000, 0], "width_mm": 1200}},
		{"id": "st", "type": "stair", "props": {"pos": [0, 0], "width_mm": 900, "steps": 12, "tread_mm": 250}},
		{"id": "g", "type": "grey_block", "props": {"pos": [0, 0], "size": [500, 500]}},
		{"id": "t", "type": "text", "props": {"pos": [0, 0], "text": "Cuisine", "role": "room"}},
		{"id": "sy", "type": "symbol", "props": {"symbol_type": "socket", "pos": [0, 0]}},
	]
	var result: CommandResult = s.run_one("entity.add", {"sheet": "s1", "items": items})
	assert_true(result.ok, result.error)
	assert_eq(result.patch.ops.size(), 7)
	for item: Variant in items:
		var entry: Dictionary = item
		var id: String = entry["id"]
		assert_true(_doc().has_entity(id), id)
		assert_eq(_doc().sheet_id_of_entity(id), "s1")
	var symbol: Dictionary = TestKit.entity_props(_doc(), "sy")
	assert_eq(symbol["count"], 1)
	assert_eq(symbol["circuit"], "")
	assert_eq(symbol["index"], 0, "0 means no index assigned yet")
	var door: Dictionary = TestKit.entity_props(_doc(), "d")
	assert_eq(door["hinge"], "left")
	assert_eq(_doc().check_integrity(), "")


func test_add_is_all_or_nothing() -> void:
	var items: Array = [
		{"id": "ok1", "type": "grey_block", "props": {"pos": [0, 0], "size": [10, 10]}},
		{"id": "bad", "type": "grey_block", "props": {"pos": [0, 0], "size": [0, 10]}},
	]
	var result: CommandResult = s.run_one("entity.add", {"sheet": "s1", "items": items})
	assert_false(result.ok)
	assert_false(_doc().has_entity("ok1"), "first item must not survive a failing second item")


func test_add_rejects_bad_input() -> void:
	TestKit.add_symbol(s, "s1", "x", [0, 0])
	assert_false(TestKit.add_symbol(s, "s2", "x", [0, 0]).ok, "ids are unique across sheets")
	assert_false(TestKit.add_entity(s, "s1", "", "wall", {"points": [[0, 0], [1, 0]]}).ok, "empty id")
	assert_false(TestKit.add_entity(s, "s1", "q", "teleporter", {}).ok, "unknown type")
	assert_false(TestKit.add_entity(s, "s1", "q", "wall", {}).ok, "missing required points")
	assert_false(TestKit.add_entity(s, "s1", "q", "wall", {"points": [[0, 0], [1, 0]], "colour": "red"}).ok, "unknown prop")
	assert_false(TestKit.add_entity(s, "s1", "q", "symbol", {"symbol_type": "lamp", "pos": [0.5, 0]}).ok, "fractional millimetres")
	assert_false(TestKit.add_entity(s, "nope", "q", "wall", {"points": [[0, 0], [1, 0]]}).ok, "unknown sheet")
	var dup: Array = [
		{"id": "same", "type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1]}},
		{"id": "same", "type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1]}},
	]
	assert_false(s.run_one("entity.add", {"sheet": "s1", "items": dup}).ok, "duplicate inside one batch")


func test_update_merges_props_and_validates() -> void:
	TestKit.add_symbol(s, "s1", "sym", [100, 100], "A", 1, "socket")
	var result: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "sym", "props": {"count": 3, "circuit": "B", "index": 2}}]})
	assert_true(result.ok, result.error)
	var props: Dictionary = TestKit.entity_props(_doc(), "sym")
	assert_eq(props["count"], 3)
	assert_eq(props["circuit"], "B")
	assert_eq(props["pos"], [100, 100], "untouched props kept")
	assert_false(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "sym", "props": {"count": 0}}]}).ok, "cross-property check")
	assert_false(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "sym", "props": {"circuit": "b"}}]}).ok)
	assert_false(s.run_one("entity.update", {"sheet": "s2", "items": [{"id": "sym", "props": {"count": 2}}]}).ok, "entity is on s1, not s2")
	assert_eq(TestKit.entity_props(_doc(), "sym")["count"], 3, "failed updates changed nothing")


func test_update_cannot_change_entity_type_props() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [10, 0]])
	assert_false(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "w", "props": {"symbol_type": "lamp"}}]}).ok)


func test_remove_entities() -> void:
	TestKit.add_wall(s, "s1", "w1", [[0, 0], [10, 0]])
	TestKit.add_wall(s, "s1", "w2", [[0, 0], [0, 10]])
	assert_true(s.run_one("entity.remove", {"sheet": "s1", "ids": ["w1", "w2"]}).ok)
	assert_false(_doc().has_entity("w1"))
	assert_false(_doc().has_entity("w2"))
	assert_false(s.run_one("entity.remove", {"sheet": "s1", "ids": ["w1"]}).ok, "already gone")
	assert_false(s.run_one("entity.remove", {"sheet": "s1", "ids": "w1"}).ok, "ids must be an array")
	assert_eq(_doc().check_integrity(), "")


func test_remove_rejects_duplicates_and_wrong_sheet() -> void:
	TestKit.add_wall(s, "s1", "w1", [[0, 0], [10, 0]])
	assert_false(s.run_one("entity.remove", {"sheet": "s1", "ids": ["w1", "w1"]}).ok)
	assert_false(s.run_one("entity.remove", {"sheet": "s2", "ids": ["w1"]}).ok)
	assert_true(_doc().has_entity("w1"))


func test_move_shifts_every_point_and_position() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [1000, 0], [1000, 500]])
	TestKit.add_symbol(s, "s1", "sym", [10, 20])
	var result: CommandResult = s.run_one("entity.move", {"sheet": "s1", "ids": ["w", "sym"], "delta": [100, -50]})
	assert_true(result.ok, result.error)
	assert_eq(TestKit.entity_props(_doc(), "w")["points"], [[100, -50], [1100, -50], [1100, 450]])
	assert_eq(TestKit.entity_props(_doc(), "sym")["pos"], [110, -30])


func test_move_uses_math_axes_and_integers() -> void:
	TestKit.add_symbol(s, "s1", "sym", [0, 0])
	assert_false(s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"], "delta": [1.5, 0]}).ok, "fractional delta refused")
	assert_true(s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"], "delta": [0, 250]}).ok)
	assert_eq(TestKit.entity_props(_doc(), "sym")["pos"], [0, 250], "positive y is up; no flip inside Core")


func test_move_by_zero_is_an_empty_patch() -> void:
	TestKit.add_symbol(s, "s1", "sym", [5, 5])
	var result: CommandResult = s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"], "delta": [0, 0]})
	assert_true(result.ok)
	assert_eq(result.patch.ops.size(), 0)


func test_move_rejects_missing_ids_and_bad_delta() -> void:
	TestKit.add_symbol(s, "s1", "sym", [0, 0])
	assert_false(s.run_one("entity.move", {"sheet": "s1", "ids": ["ghost"], "delta": [1, 1]}).ok)
	assert_false(s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"], "delta": [1]}).ok)
	assert_false(s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"]}).ok)
