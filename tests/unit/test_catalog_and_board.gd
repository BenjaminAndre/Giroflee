extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The pack catalogue (SRD 11.5), symbol roles and what doc.set accepts for board, circuits and
## cartouche (FR-UNI-3).

var s: Session


func before_each() -> void:
	s = TestKit.session()


func _put(section: String, key: String, value: Variant) -> CommandResult:
	return s.run_one("doc.set", {"section": section, "key": key, "value": value})


# --- catalogue ------------------------------------------------------------------------------------


func test_the_belgian_catalogue_has_what_the_author_uses() -> void:
	var catalog: Catalog = Catalog.for_pack("belgium")
	assert_eq(catalog.problems, [])
	assert_eq(catalog.items_of("breaker").size(), 2)
	assert_eq(catalog.items_of("differential").size(), 2)
	assert_eq(catalog.items_of("cable").size(), 3)
	assert_eq(catalog.items_of("meter").size(), 1)
	assert_eq(catalog.item("breaker_c16_3ka").label, "C16 A")
	assert_eq(catalog.item("breaker_c16_3ka").detail, "3 kA")
	assert_eq(catalog.default_for("breaker"), "breaker_c16_3ka")
	assert_eq(catalog.default_for("cable"), "cable_xgb_3g2_5_cca")
	assert_eq(catalog.min_rows, 8)
	assert_eq(catalog.usual_head.size(), 5)
	assert_eq(catalog.item(catalog.usual_head[0]).kind, "meter")
	assert_eq(catalog.item(catalog.usual_head[4]).kind, "breaker")


func test_a_missing_catalogue_is_reported_not_fatal() -> void:
	var catalog: Catalog = Catalog.load_dir("res://packs", "nowhere")
	assert_gt(catalog.problems.size(), 0)
	assert_null(catalog.item("x"))
	assert_eq(catalog.items_of("breaker"), [])


func test_symbol_types_have_a_control_or_consumer_role() -> void:
	var library: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	assert_eq(library.def("switch").role, "control")
	assert_eq(library.def("switch_two_way").role, "control")
	assert_eq(library.def("lamp").role, "consumer")
	assert_eq(library.def("socket").role, "consumer")


# --- board -----------------------------------------------------------------------------------------


func test_the_head_chain_and_the_bus_accept_catalogue_items() -> void:
	var head: Array = [{"id": "h1", "catalog": "meter_kwh_27a"}, {"id": "h2", "catalog": "diff_40a_300ma_a_ar"}]
	assert_true(_put("board", "head", head).ok, s.last_error)
	var bus: Array = [{"type": "circuit", "letter": "A"}, {"type": "device", "id": "d1", "catalog": "diff_40a_30ma_a"}, {"type": "circuit", "letter": "B"}]
	assert_true(_put("board", "bus", bus).ok, s.last_error)


func test_a_bad_board_is_refused() -> void:
	assert_false(_put("board", "other", []).ok)
	assert_false(_put("board", "head", 3).ok)
	assert_false(_put("board", "head", [{"id": "h", "catalog": "nope"}]).ok)
	assert_false(_put("board", "head", [{"id": "h", "catalog": "meter_kwh_27a"}, {"id": "h", "catalog": "meter_kwh_27a"}]).ok, "duplicate ids")
	assert_false(_put("board", "bus", [{"type": "circuit", "letter": "a"}]).ok)
	assert_false(_put("board", "bus", [{"type": "circuit", "letter": "A"}, {"type": "circuit", "letter": "A"}]).ok)
	assert_false(_put("board", "bus", [{"type": "device", "id": "m", "catalog": "meter_kwh_27a"}]).ok, "a meter cannot sit on the bus")


func test_circuits_hold_a_title_a_breaker_and_a_cable() -> void:
	assert_true(_put("circuits", "A", {"title": "Salon / Cuisine", "breaker": "breaker_c16_3ka", "cable": "cable_xgb_3g2_5_cca"}).ok, s.last_error)
	assert_true(_put("circuits", "B", {"title": "Cave"}).ok, "the rest stays at the pack default")


func test_bad_circuits_are_refused() -> void:
	assert_false(_put("circuits", "1", {}).ok)
	assert_false(_put("circuits", "A", "text").ok)
	assert_false(_put("circuits", "A", {"colour": "red"}).ok)
	assert_false(_put("circuits", "A", {"title": 3}).ok)
	assert_false(_put("circuits", "A", {"breaker": "cable_vob_3x6"}).ok, "a cable is not a breaker")


func test_cartouche_fields_are_text() -> void:
	assert_true(_put("cartouche", "address", "Rue de l'Exemple 1").ok)
	assert_false(_put("cartouche", "address", 3).ok)


func test_setting_board_values_is_undoable() -> void:
	_put("board", "head", [{"id": "h1", "catalog": "meter_kwh_27a"}])
	s.undo()
	assert_false(s.document().board.has("head"))
