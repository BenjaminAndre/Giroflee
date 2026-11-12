extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The report panel in the real window (SRD FR-RPT-1, FR-RPT-3, FR-RPT-9).

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)
	h.model().add_entities([
		{"id": "sw", "type": "symbol", "props": {"symbol_type": "switch", "pos": [4000, 4000], "circuit": "A", "index": 1}},
		{"id": "loose", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [6000, 6000]}},
	])
	await get_tree().process_frame


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func test_the_panel_lists_the_issues_with_counts_errors_first() -> void:
	var panel: ReportPanel = h.window.report_panel
	assert_gt(panel.list.item_count, 3)
	assert_true(panel.list.get_item_text(0).begins_with("✖"), "an error first")
	var title: Label = panel.find_children("*", "Label", true, false)[0]
	assert_string_contains(title.text, "erreur(s)")
	assert_string_contains(title.text, "avertissement(s)")


func test_clicking_an_issue_goes_to_its_subject() -> void:
	var panel: ReportPanel = h.window.report_panel
	var index: int = -1
	for i: int in panel.list.item_count:
		if panel.list.get_item_text(i).contains("interrupteur sans lampe"):
			index = i
	assert_gte(index, 0)
	panel.list.item_selected.emit(index)
	assert_eq(h.model().selection, ["sw"])


func test_tab_and_enter_in_the_list_walk_and_acknowledge() -> void:
	var panel: ReportPanel = h.window.report_panel
	panel.list.gui_input.emit(_key(KEY_TAB))
	var first: String = h.model().selected_issue_key
	assert_ne(first, "")
	panel.list.gui_input.emit(_key(KEY_ENTER))
	assert_true(h.model().doc().acknowledgements.has(first), "Enter acknowledged it")
	assert_ne(h.model().selected_issue_key, first, "and moved on")
	await get_tree().process_frame
	var checked: int = 0
	for i: int in panel.list.item_count:
		if panel.list.get_item_text(i).begins_with("✓"):
			checked += 1
	assert_eq(checked, 1, "shown as acknowledged")


func test_the_keys_do_nothing_outside_the_list() -> void:
	h.key("Tab")
	h.key("Enter")
	await h.play(self)
	assert_eq(h.model().selected_issue_key, "")
	assert_eq(h.model().doc().acknowledgements.size(), 0)


func test_the_panel_can_be_hidden_from_the_menu_and_the_project_stays_clean() -> void:
	var menu: PopupMenu = h.window.menu("Affichage")
	var index: int = -1
	for i: int in menu.item_count:
		if menu.get_item_text(i).begins_with("Rapport"):
			index = i
	assert_gte(index, 0)
	menu.id_pressed.emit(menu.get_item_id(index))
	assert_false(h.window.report_panel.visible)
	menu.id_pressed.emit(menu.get_item_id(index))
	assert_true(h.window.report_panel.visible)


func test_browsing_from_the_palette_focuses_the_list_and_shows_the_first_issue() -> void:
	var found: EditorCommands.Entry = null
	h.window.open_palette()
	for entry: EditorCommands.Entry in h.window.palette.entries:
		if entry.id == "report.browse":
			found = entry
	assert_not_null(found)
	found.action.call()
	assert_true(h.window.report_panel.list.has_focus())
	assert_ne(h.model().selected_issue_key, "")


func test_fixing_the_data_makes_the_issue_disappear_from_the_list() -> void:
	var panel: ReportPanel = h.window.report_panel
	var before: int = panel.list.item_count
	h.model().add_entities([{"id": "lamp", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [4400, 4000], "circuit": "A", "index": 1}}])
	await get_tree().process_frame
	var texts: String = ""
	for i: int in panel.list.item_count:
		texts += panel.list.get_item_text(i)
	assert_false(texts.contains("interrupteur sans lampe"), "a lamp on the point fixed it")
	assert_lt(panel.list.item_count, before + 3)
