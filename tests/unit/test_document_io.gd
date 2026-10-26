extends GutTest
@warning_ignore_start("unsafe_call_argument")

const TMP_PATH: String = "user://test_document_io.giroflee"


func after_each() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


func _populated() -> Session:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "s1", "Rez")
	TestKit.add_sheet(s, "s2", "Étage")
	TestKit.add_wall(s, "s1", "w1", [[0, 0], [4000, 0], [4000, 3000]])
	TestKit.add_symbol(s, "s1", "sym1", [500, 500], "A", 1, "socket")
	TestKit.add_entity(s, "s2", "b1", "grey_block", {"pos": [0, 0], "size": [800, 600]})
	s.run_one("doc.set", {"section": "cartouche", "key": "owner", "value": "Jeanne Martin"})
	s.run_one("doc.set", {"section": "config", "key": "font_size_pt", "value": 12})
	return s


func _raw(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	var raw: Dictionary = parsed
	return raw


func test_empty_project_round_trips() -> void:
	var doc: Document = Document.new_project()
	var loaded: DocumentIO.LoadResult = DocumentIO.from_json(DocumentIO.to_json(doc))
	assert_eq(loaded.error, "")
	assert_eq(TestKit.json(loaded.document), TestKit.json(doc))


func test_populated_project_round_trips_byte_for_byte() -> void:
	var doc: Document = _populated().document()
	var text: String = TestKit.json(doc)
	var loaded: DocumentIO.LoadResult = DocumentIO.from_json(text)
	assert_eq(loaded.error, "")
	assert_eq(TestKit.json(loaded.document), text)
	assert_eq(loaded.document.check_integrity(), "")


func test_file_round_trip() -> void:
	var doc: Document = _populated().document()
	assert_eq(DocumentIO.save_file(doc, TMP_PATH), "")
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file(TMP_PATH)
	assert_eq(loaded.error, "")
	assert_eq(TestKit.json(loaded.document), TestKit.json(doc))


func test_output_is_stable_and_sorted() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "s1")
	# inserted out of id order on purpose
	for id: String in ["zz", "aa", "mm"]:
		TestKit.add_symbol(s, "s1", id, [0, 0])
	var text: String = TestKit.json(s.document())
	assert_eq(TestKit.json(s.document()), text, "two saves are identical")
	var a: int = text.find("\"id\": \"aa\"")
	var m: int = text.find("\"id\": \"mm\"")
	var z: int = text.find("\"id\": \"zz\"")
	assert_true(a < m and m < z, "entities are written sorted by id")
	assert_true(text.ends_with("}\n"), "ends with a newline")


func test_sheet_order_is_preserved_not_sorted() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "z-last-id", "Premier")
	TestKit.add_sheet(s, "a-first-id", "Second")
	var loaded: DocumentIO.LoadResult = DocumentIO.from_json(TestKit.json(s.document()))
	assert_eq(loaded.document.sheet_order, ["z-last-id", "a-first-id"])


func test_integral_floats_from_json_become_ints_and_save_without_decimals() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var text: String = JSON.stringify(raw)
	# JSON parsing turns every number into a float; loading must restore ints.
	var loaded: DocumentIO.LoadResult = DocumentIO.from_json(text)
	assert_eq(loaded.error, "")
	var props: Dictionary = TestKit.entity_props(loaded.document, "w1")
	var points: Array = props["points"]
	var first: Array = points[1]
	assert_true(first[0] is int, "coordinates are ints")
	assert_string_contains(TestKit.json(loaded.document), "4000,")


func test_defaults_are_filled_for_missing_optional_props() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var sheets: Array = raw["sheets"]
	var first: Dictionary = sheets[0]
	var entities: Array = first["entities"]
	var wall: Dictionary = entities[0]
	var props: Dictionary = wall["props"]
	props.erase("weight_mm")
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(raw)
	assert_eq(loaded.error, "")
	assert_eq(TestKit.entity_props(loaded.document, "w1")["weight_mm"], 1.4)


func _fails_with(raw: Dictionary, fragment: String) -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(raw)
	assert_null(loaded.document, "should not load")
	assert_string_contains(loaded.error, fragment)


func test_rejects_non_project_json() -> void:
	assert_string_contains(DocumentIO.from_json("[1, 2]").error, "JSON object")
	assert_string_contains(DocumentIO.from_json("not json at all").error, "JSON object")


func test_rejects_newer_format() -> void:
	var raw: Dictionary = _raw(TestKit.json(Document.new_project()))
	raw["format_version"] = 99
	_fails_with(raw, "newer version")


func test_rejects_unknown_top_level_key() -> void:
	var raw: Dictionary = _raw(TestKit.json(Document.new_project()))
	raw["surprise"] = 1
	_fails_with(raw, "surprise")


func test_rejects_unknown_entity_type_and_property() -> void:
	var good: Dictionary = _raw(TestKit.json(_populated().document()))
	var raw: Dictionary = good.duplicate(true)
	var sheets: Array = raw["sheets"]
	var sheet: Dictionary = sheets[0]
	var entities: Array = sheet["entities"]
	var entity: Dictionary = entities[0]
	entity["type"] = "teleporter"
	_fails_with(raw, "teleporter")

	raw = good.duplicate(true)
	sheets = raw["sheets"]
	sheet = sheets[0]
	entities = sheet["entities"]
	entity = entities[0]
	var props: Dictionary = entity["props"]
	props["colour"] = "red"
	_fails_with(raw, "colour")


func test_rejects_duplicate_entity_ids_across_sheets() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var sheets: Array = raw["sheets"]
	var second: Dictionary = sheets[1]
	var entities: Array = second["entities"]
	var block: Dictionary = entities[0]
	block["id"] = "w1"
	_fails_with(raw, "duplicate entity id")


func test_rejects_entities_on_a_unifilaire_sheet() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var sheets: Array = raw["sheets"]
	var first: Dictionary = sheets[0]
	first["kind"] = "unifilaire"
	_fails_with(raw, "not a plan sheet")


func test_rejects_bad_ghost_reference() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var sheets: Array = raw["sheets"]
	var first: Dictionary = sheets[0]
	var props: Dictionary = first["props"]
	props["ghost_sheets"] = ["nope"]
	_fails_with(raw, "ghost")


func test_rejects_invalid_values() -> void:
	var raw: Dictionary = _raw(TestKit.json(_populated().document()))
	var sheets: Array = raw["sheets"]
	var first: Dictionary = sheets[0]
	var entities: Array = first["entities"]
	var wall: Dictionary = entities[1]
	var props: Dictionary = wall["props"]
	props["points"] = [[0, 0]]
	_fails_with(raw, "at least 2 points")


func test_rejects_unknown_config_key() -> void:
	var raw: Dictionary = _raw(TestKit.json(Document.new_project()))
	var config: Dictionary = raw["config"]
	config["theme"] = "dark"
	_fails_with(raw, "theme")


func test_missing_file_is_a_clean_error() -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file("user://does-not-exist.giroflee")
	assert_null(loaded.document)
	assert_string_contains(loaded.error, "cannot read")
