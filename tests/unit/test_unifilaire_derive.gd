extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Deriving the unifilaire from the plans and the board (SRD 8.1, FR-UNI-3 to FR-UNI-6).

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1", "Rez")
	TestKit.add_sheet(s, "s2", "Étage")
	doc = s.document()


func _sym(sheet: String, id: String, type: String, circuit: String, index: int, extra: Dictionary = {}) -> void:
	var props: Dictionary = {"symbol_type": type, "pos": [1000, 1000], "circuit": circuit, "index": index}
	props.merge(extra, true)
	assert_true(TestKit.add_entity(s, sheet, id, "symbol", props).ok, s.last_error)


func _put(section: String, key: String, value: Variant) -> void:
	assert_true(s.run_one("doc.set", {"section": section, "key": key, "value": value}).ok, s.last_error)


func _derive() -> UniModel:
	return UnifilaireBuilder.derive(doc)


# --- points and rows ------------------------------------------------------------------------------


func test_an_empty_project_has_no_column_and_the_minimum_ruler() -> void:
	var model: UniModel = _derive()
	assert_eq(model.columns.size(), 0)
	assert_eq(model.bus.size(), 0)
	assert_eq(model.rows, 8, "the pack's ruler_min_rows")


func test_points_group_symbols_of_the_same_circuit_and_index_across_etages() -> void:
	_sym("s1", "sw", "switch", "A", 1)
	_sym("s2", "la", "lamp", "A", 1)
	_sym("s1", "so", "socket", "A", 2)
	var column: UniModel.Column = _derive().column_for("A")
	assert_eq(column.points.size(), 2)
	var point1: UniModel.Point = column.points[1]
	assert_eq(point1.symbol_ids, ["la", "sw"])
	assert_true(point1.has_control and point1.has_consumer)


func test_controls_come_before_consumers_in_a_chain() -> void:
	_sym("s1", "z_lamp", "lamp", "A", 1)
	_sym("s1", "a_sw", "switch", "A", 1)
	_sym("s2", "m_sw2", "switch_two_way", "A", 1)
	var point: UniModel.Point = _derive().column_for("A").points[1]
	var types: Array[String] = []
	for item: UniModel.Item in point.items:
		types.append(item.type)
	assert_eq(types, ["switch", "switch_two_way", "lamp"])


func test_consecutive_symbols_of_one_type_collapse_and_add_their_counts() -> void:
	_sym("s1", "l1", "lamp", "A", 1)
	_sym("s1", "l2", "lamp", "A", 1)
	_sym("s1", "k", "socket", "A", 2, {"count": 3})
	var column: UniModel.Column = _derive().column_for("A")
	var lamps: UniModel.Point = column.points[1]
	assert_eq(lamps.items.size(), 1)
	assert_eq(lamps.items[0].count, 2)
	assert_eq(lamps.items[0].ids, ["l1", "l2"])
	var socket: UniModel.Point = column.points[2]
	assert_eq(socket.items[0].count, 3, "a triple socket is one item with xN")


func test_a_switch_without_a_consumer_is_open() -> void:
	_sym("s1", "sw", "switch", "A", 1)
	_sym("s1", "la", "lamp", "A", 2)
	var column: UniModel.Column = _derive().column_for("A")
	var lonely: UniModel.Point = column.points[1]
	var fine: UniModel.Point = column.points[2]
	assert_true(lonely.is_open())
	assert_false(fine.is_open())


func test_the_ruler_follows_the_highest_index_and_is_never_capped() -> void:
	_sym("s1", "a", "lamp", "A", 3)
	assert_eq(_derive().rows, 8)
	_sym("s1", "b", "lamp", "B", 12)
	assert_eq(_derive().rows, 12)
	_sym("s1", "c", "lamp", "C", 31)
	assert_eq(_derive().rows, 31)


func test_symbols_without_an_index_are_left_out_with_a_warning() -> void:
	_sym("s1", "a", "lamp", "A", 0)
	var model: UniModel = _derive()
	assert_eq(model.columns.size(), 0)
	assert_eq(model.warnings.size(), 1)


func test_markers_without_circuit_never_appear() -> void:
	TestKit.add_entity(s, "s1", "p", "symbol", {"symbol_type": "panel", "pos": [0, 0]})
	assert_eq(_derive().columns.size(), 0)


# --- order, bus, spares ----------------------------------------------------------------------------


func test_circuits_in_use_but_not_in_the_bus_follow_in_letter_order() -> void:
	_sym("s1", "c", "lamp", "C", 1)
	_sym("s1", "a", "lamp", "A", 1)
	var model: UniModel = _derive()
	var letters: Array[String] = []
	for column: UniModel.Column in model.columns:
		letters.append(column.letter)
	assert_eq(letters, ["A", "C"])
	assert_false(model.columns[0].in_bus)


func test_the_bus_decides_the_column_order_and_keeps_its_devices() -> void:
	_sym("s1", "a", "lamp", "A", 1)
	_sym("s1", "b", "lamp", "B", 1)
	_sym("s1", "c", "lamp", "C", 1)
	_put("board", "bus", [
		{"type": "circuit", "letter": "C"},
		{"type": "device", "id": "d1", "catalog": "diff_40a_30ma_a"},
		{"type": "circuit", "letter": "A"},
	])
	var model: UniModel = _derive()
	var letters: Array[String] = []
	for column: UniModel.Column in model.columns:
		letters.append(column.letter)
	assert_eq(letters, ["C", "A", "B"], "B was not in the bus: appended")
	assert_eq(model.bus.size(), 4)
	assert_false(model.bus[0].is_device)
	assert_true(model.bus[1].is_device)
	assert_eq(model.bus[1].catalog, "diff_40a_30ma_a")
	assert_eq(model.columns[0].in_bus, true)
	assert_eq(model.columns[2].in_bus, false)


func test_a_circuit_in_the_bus_without_symbols_is_a_spare() -> void:
	_put("board", "bus", [{"type": "circuit", "letter": "F"}])
	var model: UniModel = _derive()
	assert_eq(model.columns.size(), 1)
	assert_true(model.columns[0].spare)
	assert_eq(model.columns[0].points.size(), 0)


func test_the_head_chain_is_passed_through() -> void:
	_put("board", "head", [{"id": "h1", "catalog": "meter_kwh_27a"}, {"id": "h2", "catalog": "breaker_c40_3ka"}])
	var head: Array[Dictionary] = _derive().head
	assert_eq(head.size(), 2)
	assert_eq(head[0]["catalog"], "meter_kwh_27a")


# --- protection and titles -------------------------------------------------------------------------


func test_a_circuit_gets_the_pack_defaults_flagged_until_chosen() -> void:
	_sym("s1", "a", "lamp", "A", 1)
	var column: UniModel.Column = _derive().column_for("A")
	assert_eq(column.breaker, "breaker_c16_3ka")
	assert_eq(column.cable, "cable_xgb_3g2_5_cca")
	assert_true(column.breaker_defaulted and column.cable_defaulted)
	_put("circuits", "A", {"breaker": "breaker_c40_3ka"})
	column = _derive().column_for("A")
	assert_eq(column.breaker, "breaker_c40_3ka")
	assert_false(column.breaker_defaulted)
	assert_true(column.cable_defaulted, "only the breaker was chosen")


func test_a_typed_title_wins_over_the_proposal() -> void:
	_sym("s1", "a", "lamp", "A", 1)
	TestKit.add_entity(s, "s1", "room", "text", {"pos": [1100, 1000], "text": "Salon", "role": "room"})
	var proposed: UniModel.Column = _derive().column_for("A")
	assert_eq(proposed.title, "Salon")
	assert_true(proposed.title_proposed)
	_put("circuits", "A", {"title": "Séjour"})
	var typed: UniModel.Column = _derive().column_for("A")
	assert_eq(typed.title, "Séjour")
	assert_false(typed.title_proposed)


func test_the_proposal_takes_the_two_most_frequent_nearest_rooms() -> void:
	TestKit.add_entity(s, "s1", "r1", "text", {"pos": [0, 0], "text": "Salon", "role": "room"})
	TestKit.add_entity(s, "s1", "r2", "text", {"pos": [10000, 0], "text": "Cuisine", "role": "room"})
	TestKit.add_entity(s, "s1", "r3", "text", {"pos": [20000, 0], "text": "Hall", "role": "room"})
	_sym("s1", "l1", "lamp", "A", 1, {"pos": [100, 0]})
	_sym("s1", "l2", "lamp", "A", 2, {"pos": [200, 0]})
	_sym("s1", "l3", "lamp", "A", 3, {"pos": [10100, 0]})
	_sym("s1", "l4", "lamp", "A", 4, {"pos": [20100, 0]})
	assert_eq(UnifilaireBuilder.proposed_title(doc, "A"), "Salon / Cuisine", "Salon twice, then the first of the ties")


func test_free_texts_are_not_room_labels() -> void:
	TestKit.add_entity(s, "s1", "t", "text", {"pos": [0, 0], "text": "Jardin", "role": "free"})
	_sym("s1", "a", "lamp", "A", 1)
	assert_eq(UnifilaireBuilder.proposed_title(doc, "A"), "")


# --- determinism -----------------------------------------------------------------------------------


func test_deriving_twice_gives_the_same_model() -> void:
	_sym("s1", "a", "lamp", "A", 1)
	_sym("s2", "b", "switch", "B", 1)
	_sym("s2", "c", "socket", "A", 2, {"count": 2})
	_put("board", "bus", [{"type": "circuit", "letter": "B"}])
	assert_eq(_derive().to_dict(), _derive().to_dict())
