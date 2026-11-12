extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The quickbar belongs to the user and to the project (SRD FR-QB-3), through the real window.

const PROJECT: String = "user://quickbar_project_test.giroflee"
const OTHER: String = "user://quickbar_other_test.giroflee"

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_quickbar_test.json"
	h = await UiHarness.create(self)


func after_each() -> void:
	for path: String in [UserPrefs.path, PROJECT, OTHER]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ProjectFiles.clear_autosave(98)


func test_a_slot_stored_in_a_saved_project_is_back_when_it_is_reopened() -> void:
	h.window._write_to(PROJECT)
	h.model().set_tool("wall")
	h.model().store_quickbar(1)
	h.window.open_document(DocumentIO.load_file(PROJECT).document, PROJECT)
	assert_eq(h.model().quickbar.preset(1)["tool"], "wall")
	assert_not_null(h.window.quickbar_view.button_for(1).tooltip_text)


func test_another_project_has_its_own_quickbar() -> void:
	h.window._write_to(PROJECT)
	h.model().set_tool("lamp")
	h.model().store_quickbar(2)
	h.window.open_document(null, OTHER)
	assert_false(h.model().quickbar.is_filled(2))
	h.model().set_tool("socket")
	h.model().store_quickbar(2)
	h.window.open_document(DocumentIO.load_file(PROJECT).document, PROJECT)
	assert_eq(h.model().quickbar.preset(2)["tool"], "lamp", "not overwritten by the other project")


func test_slots_stored_before_the_first_save_follow_the_project() -> void:
	h.model().set_tool("door")
	h.model().store_quickbar(3)
	assert_eq(UserPrefs.quickbar_for(PROJECT), [], "nothing is written for an untitled project")
	h.window._write_to(PROJECT)
	h.window.open_document(DocumentIO.load_file(PROJECT).document, PROJECT)
	assert_eq(h.model().quickbar.preset(3)["tool"], "door")


func test_clearing_the_quickbar_is_saved_too() -> void:
	h.window._write_to(PROJECT)
	h.model().set_tool("wall")
	h.model().store_quickbar(1)
	h.model().clear_quickbar()
	h.window.open_document(DocumentIO.load_file(PROJECT).document, PROJECT)
	assert_false(h.model().quickbar.is_filled(1))


func test_the_file_keys_are_wired_to_the_window() -> void:
	# the file dialogs are native and cannot be driven in a test; the keys are tested on the input
	assert_true(h.window.input.save_requested.is_connected(h.window.save))
	assert_true(h.window.input.save_as_requested.is_connected(h.window.save_as))
	assert_true(h.window.input.open_requested.is_connected(h.window.open_project))
