extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD FR-TAB: the unifilaire as an accent-coloured button at the far left, étage tabs that can be
## reordered, new étages inserted after the active one.

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)
	h.model().new_sheet()
	h.model().new_sheet()
	await get_tree().process_frame


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _plan_names() -> Array[String]:
	var out: Array[String] = []
	for sheet_id: String in h.model().doc().plan_ids():
		out.append(h.model().doc().get_sheet(sheet_id).display_name())
	return out


func _tab_titles() -> Array[String]:
	var out: Array[String] = []
	for i: int in h.window.tabs.tab_count:
		out.append(h.window.tabs.get_tab_title(i))
	return out


func test_the_unifilaire_is_a_first_class_button_left_of_the_étage_tabs() -> void:
	var button: Button = h.window.uni_button
	assert_true(button.visible)
	assert_eq(button.theme_type_variation, "UnifilaireButton", "its own accent look")
	assert_eq(button.get_parent(), h.window.tabs.get_parent())
	assert_lt(button.get_index(), h.window.tabs.get_index(), "always on the left")
	assert_eq(button.text, "Unifilaire")
	assert_eq(h.window.tabs.tab_count, 3, "the tabs are the étages only")
	assert_false(_tab_titles().has("Unifilaire"))


func test_the_accent_look_differs_from_the_ordinary_tabs() -> void:
	var theme: Theme = h.window.theme
	var normal: StyleBoxFlat = theme.get_stylebox("normal", "UnifilaireButton")
	var pressed: StyleBoxFlat = theme.get_stylebox("pressed", "UnifilaireButton")
	assert_eq(pressed.bg_color, AppTheme.BLUE, "filled with the accent when active")
	assert_ne(normal.bg_color, pressed.bg_color)
	var tab: StyleBoxFlat = theme.get_stylebox("tab_selected", "TabBar")
	assert_ne(pressed.bg_color, tab.bg_color)


func test_pressing_the_button_shows_the_unifilaire_and_clears_the_tab_selection() -> void:
	h.window.uni_button.pressed.emit()
	assert_eq(h.model().sheet().kind, "unifilaire")
	assert_true(h.window.uni_button.button_pressed)
	assert_eq(h.window.tabs.current_tab, -1, "no étage tab looks active")
	h.window.tabs.current_tab = 1
	assert_eq(h.model().sheet().kind, "plan", "clicking a tab goes back to an étage")
	assert_false(h.window.uni_button.button_pressed)


func test_ctrl_tab_cycles_through_the_unifilaire_too() -> void:
	h.model().set_active_sheet(h.model().doc().plan_ids()[2])
	h.key("Tab", ["ctrl"])
	await h.play(self)
	assert_eq(h.model().sheet().kind, "unifilaire", "after the last étage comes the unifilaire")
	assert_true(h.window.uni_button.button_pressed)
	h.key("Tab", ["ctrl"])
	await h.play(self)
	assert_eq(h.model().active_sheet_id, h.model().doc().plan_ids()[0])


func test_dragging_a_tab_reorders_the_étages_and_saves_the_order() -> void:
	var before: Array[String] = _plan_names()
	h.window.tabs.current_tab = 0
	h.window.tabs.move_tab(0, 2)
	h.window.tabs.active_tab_rearranged.emit(2)
	var after: Array[String] = _plan_names()
	assert_eq(after, [before[1], before[2], before[0]])
	assert_eq(_tab_titles(), after, "the bar shows the document's order")
	assert_eq(h.model().doc().sheet_order[0], h.model().doc().unifilaire_sheet().id, "the unifilaire stays first")
	assert_eq(h.model().sheet().display_name(), before[0], "the moved étage stays the active one")
	h.model().undo()
	assert_eq(_plan_names(), before, "one undo step")


func test_the_palette_moves_the_active_étage_left_and_right() -> void:
	h.model().set_active_sheet(h.model().doc().plan_ids()[1])
	var names: Array[String] = _plan_names()
	h.model().shift_sheet(-1)
	assert_eq(_plan_names(), [names[1], names[0], names[2]])
	h.model().shift_sheet(-1)
	assert_eq(_plan_names(), [names[1], names[0], names[2]], "already first among the étages")
	h.model().shift_sheet(1)
	h.model().shift_sheet(1)
	assert_eq(_plan_names(), [names[0], names[2], names[1]])
	h.model().shift_sheet(1)
	assert_eq(_plan_names(), [names[0], names[2], names[1]], "already last")


func test_nothing_can_be_placed_before_the_unifilaire() -> void:
	var uni: String = h.model().doc().unifilaire_sheet().id
	var result: CommandResult = h.model().move_sheet(h.model().doc().plan_ids()[1], 0)
	assert_true(result.ok, "the index is raised to the first étage place")
	assert_eq(h.model().doc().sheet_order[0], uni)


func test_new_and_duplicated_étages_go_right_after_the_active_one() -> void:
	h.model().set_active_sheet(h.model().doc().plan_ids()[0])
	h.model().new_sheet()
	assert_eq(h.model().doc().plan_ids().find(h.model().active_sheet_id), 1)
	h.model().show_unifilaire()
	h.model().new_sheet()
	assert_eq(h.model().doc().plan_ids().find(h.model().active_sheet_id), 0, "after the unifilaire, before the other étages")


func test_the_unifilaire_has_no_drawing_tools_and_cannot_be_deleted_or_duplicated() -> void:
	h.model().show_unifilaire()
	var seen: Array[String] = []
	h.model().notice.connect(func(message: String) -> void: seen.append(message))
	h.key("W")
	h.key("L")
	await h.play(self)
	assert_eq(h.model().tool_name, "select")
	assert_eq(seen.size(), 2, "a notice instead of switching tool")
	var count: int = h.model().doc().sheet_order.size()
	h.model().delete_sheet()
	h.model().duplicate_sheet(false)
	assert_eq(h.model().doc().sheet_order.size(), count)
	assert_eq(seen.size(), 4)


func test_the_unifilaire_can_be_renamed_in_place() -> void:
	h.model().show_unifilaire()
	h.key("F2")
	await h.play(self)
	assert_true(h.window._inline.visible)
	h.window._inline.text = "Schéma"
	h.window._inline.text_submitted.emit("Schéma")
	assert_eq(h.window.uni_button.text, "Schéma")
