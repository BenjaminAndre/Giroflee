extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD section 11: a pack is a folder; symbols are SVG files mapped to core types by symbols.json.

const TMP: String = "user://test_packs"


func after_each() -> void:
	_remove_dir(TMP)


func _remove_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_remove_dir("%s/%s" % [path, sub])
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


const GOOD_SVG: String = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-5 -5 10 10"><circle cx="0" cy="0" r="2" fill="none" stroke="currentColor" stroke-width="0.3"/></svg>'


func _pack(id: String, includes: Array, types: Dictionary, order: Array) -> void:
	_write("%s/%s/pack.json" % [TMP, id], JSON.stringify({"format_version": 1, "id": id, "name": id, "includes": includes}))
	_write("%s/%s/symbols.json" % [TMP, id], JSON.stringify({"format_version": 1, "order": order, "types": types}))


# --- the Belgian pack -------------------------------------------------------------------------


func test_the_belgian_pack_lists_the_v01_symbols_in_order() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	assert_eq(lib.problems, [], "no problem loading the shipped pack")
	assert_eq(lib.order, PackedStringArray(["lamp", "switch", "switch_two_way", "socket", "panel", "meter"]))
	assert_eq(lib.def("lamp").title, "Lampe")
	assert_eq(lib.def("switch_two_way").title, "Interrupteur va-et-vient")
	assert_eq(lib.def("socket").title, "Prise")


func test_every_shipped_symbol_has_valid_artwork() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	for type: String in lib.order:
		var def: SymbolLibrary.Def = lib.def(type)
		assert_not_null(def.plan, type)
		assert_true(def.plan.ok(), "%s: %s" % [type, def.plan.error])
		assert_true(def.plan.shapes.size() >= 1)
		assert_true(def.unifilaire.ok(), "%s unifilaire: %s" % [type, def.unifilaire.error])
		assert_ne(def.plan.view_box, Rect2(), "%s has a viewBox" % type)


func test_symbol_behaviour_comes_from_the_pack_data() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	assert_eq(lib.def("socket").attach, "wall", "sockets face the walls (SRD FR-SYM-4)")
	assert_eq(lib.def("lamp").attach, "free")
	for type: String in ["lamp", "switch", "switch_two_way", "socket"]:
		assert_true(lib.def(type).counts_as_point, type)
		assert_true(lib.def(type).uses_circuit, type)
	for type: String in ["panel", "meter"]:
		assert_false(lib.def(type).counts_as_point, "%s is not an electrical point" % type)
		assert_false(lib.def(type).uses_circuit)
		assert_true(lib.def(type).marker)
	assert_eq(lib.def("panel").caption, "TGBT")
	assert_eq(lib.def("meter").caption, "kWh")


func test_the_unifilaire_artwork_differs_for_sockets_and_falls_back_to_the_plan_otherwise() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	assert_ne(lib.def("socket").unifilaire.shapes.size(), 0)
	assert_ne(lib.def("socket").unifilaire.bounds(), lib.def("socket").plan.bounds(), "a socket looks different in the unifilaire")
	assert_same(lib.def("panel").unifilaire, lib.def("panel").plan, "no unifilaire file: the plan art is used (FR-CSYM-4)")


func test_artwork_stays_in_page_millimetres_and_is_small() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("belgium")
	for type: String in ["lamp", "switch", "switch_two_way", "socket"]:
		var b: Rect2 = lib.def(type).plan.bounds()
		assert_true(b.size.x < 8.0 and b.size.y < 8.0, "%s is a few page millimetres across (%s)" % [type, str(b.size)])
		assert_true(b.size.x > 1.0 or b.size.y > 1.0)


func test_a_socket_extends_toward_plus_y_so_rotation_zero_faces_down() -> void:
	var b: Rect2 = SymbolLibrary.for_pack("belgium").def("socket").plan.bounds()
	assert_true(b.end.y > 2.0, "the bowl is below the anchor (SVG y down)")
	assert_true(b.position.y > -3.0 and b.position.y < 0.0, "only the short earth tick is on the wall side")


func test_libraries_are_cached() -> void:
	assert_same(SymbolLibrary.for_pack("belgium"), SymbolLibrary.for_pack("belgium"))


func test_an_unknown_pack_is_an_empty_library_with_a_problem() -> void:
	var lib: SymbolLibrary = SymbolLibrary.for_pack("atlantis")
	assert_eq(lib.order.size(), 0)
	assert_true(lib.problems.size() >= 1)
	assert_null(lib.def("lamp"))
	assert_false(lib.has_type("lamp"))


# --- custom packs ----------------------------------------------------------------------------


func test_a_pack_with_valid_symbols_loads() -> void:
	_write(TMP + "/mine/symbols/dot.svg", GOOD_SVG)
	_pack("mine", [], {"dot": {"title": "Point", "plan": "symbols/dot.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true}}, ["dot"])
	var lib: SymbolLibrary = SymbolLibrary.load_dir(TMP, "mine")
	assert_eq(lib.problems, [])
	assert_eq(lib.order, PackedStringArray(["dot"]))
	assert_true(lib.def("dot").plan.ok())


func test_includes_are_loaded_first_and_the_pack_can_override() -> void:
	_write(TMP + "/base/symbols/a.svg", GOOD_SVG)
	_write(TMP + "/base/symbols/b.svg", GOOD_SVG)
	_pack("base", [], {
		"a": {"title": "A de base", "plan": "symbols/a.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true},
		"b": {"title": "B de base", "plan": "symbols/b.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true},
	}, ["a", "b"])
	_write(TMP + "/top/symbols/b.svg", GOOD_SVG)
	_pack("top", ["base"], {"b": {"title": "B surchargé", "plan": "symbols/b.svg", "attach": "wall", "counts_as_point": false, "uses_circuit": false}}, ["b"])
	var lib: SymbolLibrary = SymbolLibrary.load_dir(TMP, "top")
	assert_eq(lib.problems, [])
	assert_eq(lib.order, PackedStringArray(["a", "b"]), "included symbols first, no duplicates")
	assert_eq(lib.def("a").title, "A de base")
	assert_eq(lib.def("b").title, "B surchargé", "the pack overrides its include (PACK-4)")
	assert_eq(lib.def("b").attach, "wall")


func test_problems_are_reported_and_the_bad_symbol_is_skipped() -> void:
	_write(TMP + "/p/symbols/ok.svg", GOOD_SVG)
	_write(TMP + "/p/symbols/bad.svg", '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><text>no</text></svg>')
	_pack("p", [], {
		"ok": {"title": "OK", "plan": "symbols/ok.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true},
		"bad": {"title": "Mauvais", "plan": "symbols/bad.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true},
		"missing": {"title": "Absent", "plan": "symbols/nope.svg", "attach": "free", "counts_as_point": true, "uses_circuit": true},
		"worse": {"title": "Pire", "plan": "symbols/ok.svg", "attach": "ceiling", "counts_as_point": true, "uses_circuit": true},
	}, ["ok", "bad", "missing", "worse"])
	var lib: SymbolLibrary = SymbolLibrary.load_dir(TMP, "p")
	assert_eq(lib.order, PackedStringArray(["ok"]), "only the valid symbol is offered")
	assert_eq(lib.problems.size(), 3)
	var text: String = "\n".join(PackedStringArray(lib.problems))
	assert_string_contains(text, "bad.svg")
	assert_string_contains(text, "text")
	assert_string_contains(text, "nope.svg")
	assert_string_contains(text, "attach")


func test_broken_json_and_missing_fields_are_problems_not_crashes() -> void:
	_write(TMP + "/q/pack.json", "{not json")
	var a: SymbolLibrary = SymbolLibrary.load_dir(TMP, "q")
	assert_true(a.problems.size() >= 1)
	_pack("r", [], {"x": {"plan": "symbols/x.svg"}}, ["x"])
	var b: SymbolLibrary = SymbolLibrary.load_dir(TMP, "r")
	assert_eq(b.order.size(), 0)
	assert_true(b.problems.size() >= 1)


func test_an_include_loop_does_not_hang() -> void:
	_pack("loop_a", ["loop_b"], {}, [])
	_pack("loop_b", ["loop_a"], {}, [])
	var lib: SymbolLibrary = SymbolLibrary.load_dir(TMP, "loop_a")
	assert_true(lib.problems.size() >= 1)
	assert_string_contains("\n".join(PackedStringArray(lib.problems)), "loop")
