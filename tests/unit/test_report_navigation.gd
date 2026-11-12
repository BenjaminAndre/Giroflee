extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Moving through the report from the editor: Tab, Enter, jumping to the subject (SRD FR-RPT-3, FR-RPT-9).

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()
	kit.add("symbol", {"symbol_type": "switch", "pos": [4000, 4000], "circuit": "A", "index": 1}, "sw")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [6000, 6000], "circuit": "", "index": 0}, "loose")


func _first(rule: String) -> Issue:
	for issue: Issue in kit.model.issues():
		if issue.rule == rule:
			return issue
	return null


func test_the_issues_are_cached_until_the_document_changes() -> void:
	var first: Array[Issue] = kit.model.issues()
	assert_same(kit.model.issues(), first)
	kit.add("symbol", {"symbol_type": "lamp", "pos": [8000, 8000], "circuit": "B", "index": 1}, "more")
	assert_not_same(kit.model.issues(), first)


func test_going_to_an_issue_selects_its_symbols_and_centres_the_view() -> void:
	var issue: Issue = _first("control_without_consumer")
	kit.model.goto_issue(issue)
	assert_eq(kit.model.selection, ["sw"])
	assert_eq(kit.model.selected_issue_key, issue.key)
	assert_almost_eq(kit.model.view().center.x, 4000.0, 600.0)


func test_going_to_an_issue_on_another_etage_switches_tab() -> void:
	var other: String = kit.model.new_id()
	kit.session.run_one("sheet.add", {"id": other, "kind": "plan", "props": {"name": "Étage"}})
	kit.session.run_one("entity.add", {"sheet": other, "items": [{"id": "up", "type": "symbol", "props": {"symbol_type": "switch", "pos": [1000, 1000], "circuit": "C", "index": 1}}]})
	for issue: Issue in kit.model.issues():
		if issue.entity_ids == ["up"]:
			kit.model.goto_issue(issue)
	assert_eq(kit.model.active_sheet_id, other)
	assert_eq(kit.model.selection, ["up"])


func test_a_circuit_issue_goes_to_the_unifilaire_column_and_a_head_issue_to_the_unifilaire() -> void:
	kit.model.goto_issue(_first("circuit_defaults"))
	assert_eq(kit.model.sheet().kind, "unifilaire")
	assert_eq(kit.model.uni_selection["kind"], "column")
	kit.model.goto_issue(_first("head_chain"))
	assert_eq(kit.model.sheet().kind, "unifilaire")
	assert_eq(kit.model.uni_selection, {})


func test_next_walks_the_open_issues_and_wraps() -> void:
	var open_count: int = kit.model.issues().size()
	var seen: Array[String] = []
	for i: int in open_count:
		kit.model.go_next_issue()
		seen.append(kit.model.selected_issue_key)
	assert_eq(seen.size(), open_count)
	assert_eq(seen[0], kit.model.issues()[0].key, "starts with the first, an error")
	kit.model.go_next_issue()
	assert_eq(kit.model.selected_issue_key, seen[0], "wrapped round")


func test_enter_acknowledges_and_moves_to_the_next_open_issue() -> void:
	kit.model.go_next_issue()
	var first: String = kit.model.selected_issue_key
	kit.model.acknowledge_selected_issue()
	assert_true(kit.doc().acknowledgements.has(first))
	assert_ne(kit.model.selected_issue_key, first)
	assert_true(kit.model.issue_for_key(first).acknowledged)
	kit.model.undo()
	assert_false(kit.doc().acknowledgements.has(first), "one undo step")


func test_acknowledged_issues_are_skipped_by_next_and_can_be_reopened() -> void:
	for issue: Issue in kit.model.issues():
		kit.session.run_one("doc.set", {"section": "acknowledgements", "key": issue.key, "value": true})
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	kit.model.go_next_issue()
	assert_eq(seen.size(), 1, "everything is acknowledged")
	var key: String = kit.model.issues()[0].key
	kit.model.unacknowledge_issue(key)
	kit.model.go_next_issue()
	assert_eq(kit.model.selected_issue_key, key)


func test_the_palette_has_the_report_commands_without_a_key() -> void:
	for id: String in ["report.next", "report.show"]:
		var found: bool = false
		for entry: EditorCommands.Entry in EditorCommands.build(kit.model):
			if entry.id == id:
				found = true
				assert_eq(entry.shortcut, "", "no key was approved for it (WA-1)")
		assert_true(found, id)


func test_showing_and_hiding_the_report_is_view_state() -> void:
	var revision: int = kit.model.revision
	kit.model.set_report_visible(false)
	assert_false(kit.model.report_visible)
	assert_eq(kit.model.revision, revision)
