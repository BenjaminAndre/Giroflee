extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The report: what is missing or doubtful, with severities, keys and acknowledgements
## (SRD section 9, FR-RPT-2, FR-RPT-4, FR-RPT-6 to FR-RPT-8).

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	s.run_one("sheet.add", {"id": "uni", "kind": "unifilaire", "props": Document.unifilaire_props()})
	TestKit.add_sheet(s, "p1", "Rez")
	doc = s.document()


func after_each() -> void:
	Rules._cache.erase("belgium")


func _sym(id: String, type: String, circuit: String, index: int, extra: Dictionary = {}) -> void:
	var props: Dictionary = {"symbol_type": type, "pos": [1000, 1000], "circuit": circuit, "index": index}
	props.merge(extra, true)
	assert_true(TestKit.add_entity(s, "p1", id, "symbol", props).ok, s.last_error)


func _put(section: String, key: String, value: Variant) -> void:
	assert_true(s.run_one("doc.set", {"section": section, "key": key, "value": value}).ok, s.last_error)


func _of(rule: String) -> Array[Issue]:
	var out: Array[Issue] = []
	for issue: Issue in ReportBuilder.build(doc):
		if issue.rule == rule:
			out.append(issue)
	return out


func _complete_head() -> void:
	var head: Array = []
	for item_id: String in Catalog.for_pack("belgium").usual_head:
		head.append({"id": "h-%s" % item_id, "catalog": item_id})
	_put("board", "head", head)


# --- rules that need no values ------------------------------------------------------------------------


func test_a_clean_empty_project_only_misses_the_head_chain_and_the_cartouche() -> void:
	var rules: Array[String] = []
	for issue: Issue in ReportBuilder.build(doc):
		if issue.rule != "rule_unconfigured":
			rules.append(issue.rule)
	assert_eq(rules, ["head_chain", "cartouche_required", "cartouche_required", "cartouche_required"])


func test_symbols_without_a_circuit_or_an_index_are_errors_grouped_per_etage() -> void:
	_sym("a", "lamp", "", 0)
	_sym("b", "socket", "", 0)
	_sym("c", "lamp", "A", 0)
	var none: Array[Issue] = _of("symbol_without_circuit")
	assert_eq(none.size(), 1)
	assert_true(none[0].is_error())
	assert_eq(none[0].entity_ids, ["a", "b"])
	assert_eq(none[0].sheet_id, "p1")
	assert_eq(_of("symbol_without_index")[0].entity_ids, ["c"])


func test_markers_do_not_need_a_circuit() -> void:
	TestKit.add_entity(s, "p1", "tgbt", "symbol", {"symbol_type": "panel", "pos": [0, 0]})
	assert_eq(_of("symbol_without_circuit").size(), 0)


func test_a_switch_without_a_consumer_is_an_error_pointing_at_it() -> void:
	_sym("sw", "switch", "A", 1)
	var found: Array[Issue] = _of("control_without_consumer")
	assert_eq(found.size(), 1)
	assert_true(found[0].is_error())
	assert_eq(found[0].entity_ids, ["sw"])
	assert_eq(found[0].circuit, "A")
	_sym("la", "lamp", "A", 1)
	assert_eq(_of("control_without_consumer").size(), 0, "a lamp on the same point fixes it")


func test_a_lamp_without_a_switch_is_a_warning_but_a_socket_alone_is_fine() -> void:
	_sym("la", "lamp", "A", 1)
	_sym("so", "socket", "A", 2)
	var found: Array[Issue] = _of("consumer_without_control")
	assert_eq(found.size(), 1)
	assert_false(found[0].is_error())
	assert_eq(found[0].entity_ids, ["la"])


func test_the_head_chain_is_an_error_until_it_exists() -> void:
	assert_eq(_of("head_chain").size(), 1)
	_complete_head()
	assert_eq(_of("head_chain").size(), 0)


func test_required_cartouche_fields_are_errors_while_empty() -> void:
	assert_eq(_of("cartouche_required").size(), 3, "address, owner, installer")
	_put("cartouche", "address", "Rue de l'Exemple 1")
	_put("cartouche", "owner", "Jeanne")
	_put("cartouche", "installer", "  ")
	var left: Array[Issue] = _of("cartouche_required")
	assert_eq(left.size(), 1, "blank counts as empty")
	assert_string_contains(left[0].message, "Installateur")


func test_defaulted_protection_is_a_warning_until_chosen() -> void:
	_sym("a", "lamp", "A", 1)
	assert_eq(_of("circuit_defaults").size(), 1)
	_put("circuits", "A", {"breaker": "breaker_c16_3ka", "cable": "cable_xgb_3g2_5_cca"})
	assert_eq(_of("circuit_defaults").size(), 0)


func test_objects_outside_the_page_are_listed_per_etage() -> void:
	TestKit.add_entity(s, "p1", "far", "grey_block", {"pos": [999999, 999999], "size": [500, 500]})
	_sym("in", "lamp", "A", 1)
	var found: Array[Issue] = _of("outside_page")
	assert_eq(found.size(), 1)
	assert_eq(found[0].entity_ids, ["far"])


func test_unifilaire_layout_warnings_become_issues() -> void:
	for i: int in 26:
		_sym("s%d" % i, "lamp", char(65 + i), 1)
	assert_gt(_of("unifilaire_layout").size(), 0)


# --- rules that need values ---------------------------------------------------------------------------


func test_unconfigured_rules_are_listed_not_applied() -> void:
	var names: Array[String] = []
	for issue: Issue in _of("rule_unconfigured"):
		names.append(issue.message)
	for wanted: String in ["max_points_per_circuit", "breaker_cable_pairs", "differential_required", "bathroom"]:
		var found: bool = false
		for text: String in names:
			found = found or text.contains(wanted)
		assert_true(found, "%s is reported as not configured" % wanted)


func test_a_rules_file_switches_the_rules_on() -> void:
	var rules: Rules = Rules.new()
	rules.data = {"max_points_per_circuit": {"value": 8}}
	assert_eq(rules.max_points(), 8)
	rules.data = {"max_points_per_circuit": {"value": null}}
	assert_eq(rules.max_points(), -1)


func test_differential_rules_read_configured_and_unconfigured_entries() -> void:
	var rules: Rules = Rules.new()
	rules.data = {"differential_required": {"rules": [
		{"when": {"symbol_type": "socket"}, "max_residual_current_ma": 30},
		{"when": {"room_keywords_match": "bathroom"}, "max_residual_current_ma": null},
	]}}
	var parsed: Dictionary = rules.differential_rules()
	assert_eq(parsed["unconfigured"], 1)
	var configured: Array = parsed["configured"]
	assert_eq(configured.size(), 1)


func test_the_pack_without_rules_json_loads_the_template() -> void:
	var rules: Rules = Rules.for_pack("belgium")
	assert_false(rules.from_file)
	assert_eq(rules.max_points(), -1)
	assert_eq(rules.required_cartouche_fields(), ["address", "owner", "installer"])


# --- keys, order, acknowledgements --------------------------------------------------------------------


func test_errors_come_before_warnings_and_the_order_is_stable() -> void:
	_sym("sw", "switch", "A", 1)
	_sym("la", "lamp", "B", 1)
	var seen_warning: bool = false
	for issue: Issue in ReportBuilder.build(doc):
		if not issue.is_error():
			seen_warning = true
		else:
			assert_false(seen_warning, "an error after a warning")
	var first: Array[String] = []
	var second: Array[String] = []
	for issue: Issue in ReportBuilder.build(doc):
		first.append(issue.key)
	for issue: Issue in ReportBuilder.build(doc):
		second.append(issue.key)
	assert_eq(first, second)


func test_an_issue_key_changes_with_the_data_it_is_about() -> void:
	_sym("sw", "switch", "A", 1)
	var before: String = _of("control_without_consumer")[0].key
	_sym("sw2", "switch", "A", 1)
	var after: String = _of("control_without_consumer")[0].key
	assert_ne(before, after, "another symbol joined the point")
	assert_eq(before.split(":")[0], "control_without_consumer")


func test_acknowledging_marks_the_issue_until_its_data_changes() -> void:
	_sym("sw", "switch", "A", 1)
	var errors_before: int = ReportBuilder.open_errors(doc)
	var key: String = _of("control_without_consumer")[0].key
	_put("acknowledgements", key, true)
	assert_true(_of("control_without_consumer")[0].acknowledged)
	assert_eq(ReportBuilder.open_errors(doc), errors_before - 1)
	_sym("sw2", "switch", "A", 1)
	assert_false(_of("control_without_consumer")[0].acknowledged, "the data changed: it is back")


func test_acknowledgements_are_undoable_and_saved_with_the_project() -> void:
	_put("acknowledgements", "x:1", true)
	var text: String = DocumentIO.to_json(doc)
	assert_string_contains(text, "\"acknowledgements\"")
	var loaded: DocumentIO.LoadResult = DocumentIO.from_json(text)
	assert_eq(loaded.document.acknowledgements, {"x:1": true})
	s.undo()
	assert_false(doc.acknowledgements.has("x:1"))
	assert_false(s.run_one("doc.set", {"section": "acknowledgements", "key": "x", "value": false}).ok, "only true is stored")


func test_format_3_files_open_with_no_acknowledgements() -> void:
	var data: Dictionary = doc.to_dict()
	data.erase("acknowledgements")
	data["format_version"] = 3
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(data)
	assert_not_null(loaded.document, loaded.error)
	assert_eq(loaded.document.acknowledgements, {})


# --- rules with values -----------------------------------------------------------------------------------


func test_breaker_cable_and_differential_checks_with_values() -> void:
	var rules: Rules = Rules.new()
	rules.data = {
		"max_points_per_circuit": {"value": 2},
		"breaker_cable_pairs": {"allowed": [{"breaker_a": 16, "section_mm2": 1.5}]},
		"differential_required": {"rules": [{"when": {"symbol_type": "socket"}, "max_residual_current_ma": 30}]},
		"bathroom": {"check_radius_mm": 1500, "room_keywords": ["salle de bain"], "message_fr": "Vérifier les volumes."},
	}
	Rules._cache["belgium"] = rules
	_sym("a", "lamp", "A", 1)
	_sym("b", "lamp", "A", 2)
	_sym("c", "lamp", "A", 3)
	_sym("so", "socket", "B", 1)
	TestKit.add_entity(s, "p1", "bain", "text", {"pos": [1200, 1000], "text": "Salle de bain", "role": "room"})
	assert_eq(_of("max_points").size(), 1, "circuit A has three points")
	assert_eq(_of("breaker_cable").size(), 2, "C16 with 2.5 mm2 is not in the allowed list")
	var diff: Array[Issue] = _of("differential_required")
	assert_eq(diff.size(), 1)
	assert_eq(diff[0].circuit, "B")
	assert_eq(_of("bathroom").size(), 1)
	assert_eq(_of("rule_unconfigured").size(), 0)
	# a 30 mA differential on the bus in front of circuit B satisfies the socket rule
	_put("board", "bus", [{"type": "device", "id": "d", "catalog": "diff_40a_30ma_a"}, {"type": "circuit", "letter": "B"}])
	assert_eq(_of("differential_required").size(), 0)
