extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Decisions of the author: boxes select what is fully inside (FR-EDIT-1), previews follow modifier keys
## and gestures live, Ctrl+S / Ctrl+Shift+S / Ctrl+O, the quickbar saved per user and project (FR-QB-3).

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()
	UserPrefs.path = "user://prefs_live_test.json"


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))


# --- box selection ---------------------------------------------------------------------------------------


func test_a_box_selects_only_what_it_fully_contains() -> void:
	kit.add("wall", {"points": [[2000, 2000], [4000, 2000]]}, "inside")
	kit.add("wall", {"points": [[2000, 3000], [9000, 3000]]}, "sticks_out")
	kit.drag(Vector2(1500, 1500), Vector2(5000, 4500))
	assert_eq(kit.model.selection, ["inside"], "a wall that only crosses the box is left out")


# --- previews follow the modifier keys -----------------------------------------------------------------------


func _label_texts() -> Array[String]:
	var out: Array[String] = []
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.TEXT:
			out.append(op.text)
	return out


func test_the_alt_place_label_updates_when_alt_is_pressed_without_moving_the_mouse() -> void:
	kit.key(KEY_L)
	kit.click(Vector2(2000, 2000))
	kit.move(Vector2(5000, 2000))
	assert_true(_label_texts().has("A2"), "a new point")
	kit.key(KEY_ALT, false, false, true)
	assert_true(_label_texts().has("A1"), "Alt links it to the previous one, shown at once")
	kit.key_up(KEY_ALT)
	assert_true(_label_texts().has("A2"), "and back when Alt is released")


func test_a_modifier_key_before_any_pointer_movement_is_harmless() -> void:
	assert_false(kit.key(KEY_SHIFT, true))
	assert_false(kit.key(KEY_ALT, false, false, true))


func test_modifier_keys_are_not_swallowed() -> void:
	assert_false(kit.key(KEY_CTRL, false, true), "other shortcuts still see them")


# --- the transform box follows the gesture --------------------------------------------------------------------


func test_the_transform_box_is_redrawn_while_resizing() -> void:
	kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 600]}, "b")
	kit.model.set_selection(["b"])
	var original: Rect2 = SelectTool.box_for(kit.model).box
	var grab: Vector2 = SelectTool.box_for(kit.model).handle_pos("se")
	kit.move(grab)
	kit.press(grab)
	kit.move(grab + Vector2(600, -400))
	var live: Rect2 = SelectTool.box_for(kit.model).box
	assert_gt(live.size.x, original.size.x, "wider while dragging, before the button is released")
	assert_eq(kit.doc().find_entity("b").props["size"], [1000, 600], "the document is not touched yet")
	kit.release(grab + Vector2(600, -400))
	var after: Rect2 = SelectTool.box_for(kit.model).box
	assert_almost_eq(after.size.x, live.size.x, 1.0, "the box stays where the gesture left it")


func test_the_transform_box_follows_a_move_too() -> void:
	kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 600]}, "b")
	kit.model.set_selection(["b"])
	var original: Rect2 = SelectTool.box_for(kit.model).box
	kit.move(Vector2(3500, 3300))
	kit.press(Vector2(3500, 3300))
	kit.move(Vector2(5500, 3300))
	assert_gt(SelectTool.box_for(kit.model).box.position.x, original.position.x + 1000.0)
	kit.release(Vector2(5500, 3300))


# --- save and open keys ----------------------------------------------------------------------------------------


func test_ctrl_s_ctrl_shift_s_and_ctrl_o_ask_for_save_save_as_and_open() -> void:
	watch_signals(kit.input)
	assert_true(kit.key(KEY_S, false, true))
	assert_signal_emit_count(kit.input, "save_requested", 1)
	assert_true(kit.key(KEY_S, true, true))
	assert_signal_emit_count(kit.input, "save_as_requested", 1)
	assert_signal_emit_count(kit.input, "save_requested", 1, "Shift made it a save as")
	assert_true(kit.key(KEY_O, false, true))
	assert_signal_emit_count(kit.input, "open_requested", 1)


func test_plain_s_is_still_the_grey_block_tool() -> void:
	kit.key(KEY_S)
	assert_eq(kit.model.tool_name, "block")


func test_ctrl_e_is_left_free_for_the_export() -> void:
	assert_false(kit.key(KEY_E, false, true), "not bound before M6")


# --- the quickbar is saved per user and project --------------------------------------------------------------------


func test_a_quickbar_survives_json() -> void:
	kit.key(KEY_W)
	kit.key(KEY_1, false, true)
	kit.model.set_tool("lamp")
	kit.model.place_count = 3
	kit.model.store_quickbar(4)
	var text: String = JSON.stringify(kit.model.quickbar.to_data())
	var parsed: Variant = JSON.parse_string(text)
	var restored: Quickbar = Quickbar.new()
	restored.load_data(parsed)
	assert_eq(restored.preset(1)["tool"], "wall")
	assert_eq(restored.preset(4)["tool"], "lamp")
	assert_eq(restored.preset(4)["count"], 3)
	assert_eq(typeof(restored.preset(4)["count"]), TYPE_INT, "numbers are whole again after JSON")
	assert_false(restored.is_filled(2))


func test_damaged_quickbar_data_gives_empty_slots_not_errors() -> void:
	var quickbar: Quickbar = Quickbar.new()
	quickbar.load_data([{"tool": 5}, "x", {}, {"tool": "wall", "count": "many"}, null])
	assert_false(quickbar.is_filled(1))
	assert_false(quickbar.is_filled(2))
	assert_true(quickbar.is_filled(4))
	assert_eq(quickbar.preset(4)["count"], 1)
	quickbar.load_data("nonsense")
	assert_false(quickbar.is_filled(4))


func test_each_project_has_its_own_quickbar_in_the_user_prefs() -> void:
	var a: Quickbar = Quickbar.new()
	a.assign(1, {"tool": "wall", "rotation": 0.0, "flip_h": false, "flip_v": false, "manual": false, "count": 1, "defaults": {}, "wall_weight": 1.4})
	assert_eq(UserPrefs.set_quickbar("C:\\Plans\\Maison.giroflee", a.to_data()), "")
	assert_eq(UserPrefs.quickbar_for("c:/plans/maison.giroflee").size(), 9, "same file, any spelling")
	assert_eq(UserPrefs.quickbar_for("C:/Plans/Autre.giroflee"), [], "another project has none")
	UserPrefs.set_quickbar("C:/Plans/Autre.giroflee", Quickbar.new().to_data())
	var again: Quickbar = Quickbar.new()
	again.load_data(UserPrefs.quickbar_for("C:/Plans/Maison.giroflee"))
	assert_true(again.is_filled(1), "the first one was not overwritten")
	assert_true(UserPrefs.load_prefs()["toolbar_visible"], "other preferences are untouched")
