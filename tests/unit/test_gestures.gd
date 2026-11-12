extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Gestures decided with the author (Factorio-inspired): Ctrl+digit stores a quickbar slot, Shift +
## right/left click copies and pastes settings, Alt + drag anchors, Alt + right-click detaches, Ctrl
## selects (SRD FR-QB-3, FR-EDIT-7, FR-STACK-2, FR-EDIT-1).

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _props(id: String) -> Dictionary:
	return kit.sheet().entities[id].props


func _lamp(id: String, pos: Array, index: int = 1) -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": pos, "circuit": "A", "index": index}, id)


# --- quickbar: Ctrl + digit stores, digit uses --------------------------------------------------------


func test_ctrl_digit_stores_the_active_tool_and_the_digit_uses_it() -> void:
	kit.key(KEY_W)
	assert_true(kit.key(KEY_1, false, true))
	assert_true(kit.model.quickbar.is_filled(1))
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.tool_name, "select")
	kit.key(KEY_1)
	assert_eq(kit.model.tool_name, "wall")


func test_a_plain_digit_never_stores_and_an_empty_slot_only_says_so() -> void:
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	kit.key(KEY_W)
	kit.key(KEY_3)
	assert_false(kit.model.quickbar.is_filled(3))
	assert_eq(kit.model.tool_name, "wall", "the tool did not change")
	assert_eq(seen.size(), 1)


func test_ctrl_digit_overwrites_a_filled_slot() -> void:
	kit.key(KEY_W)
	kit.key(KEY_2, false, true)
	kit.key(KEY_P)
	kit.key(KEY_2, false, true)
	assert_eq(kit.model.quickbar.preset(2)["tool"], "socket")


func test_ctrl_digit_with_the_select_tool_stores_nothing() -> void:
	kit.key(KEY_4, false, true)
	assert_false(kit.model.quickbar.is_filled(4))


func test_ctrl_digit_reads_the_physical_key() -> void:
	kit.key(KEY_W)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_AMPERSAND
	event.physical_keycode = KEY_5
	event.pressed = true
	event.ctrl_pressed = true
	kit.input.handle(event)
	assert_true(kit.model.quickbar.is_filled(5))


# --- selection moves to Ctrl ---------------------------------------------------------------------------


func test_shift_click_no_longer_toggles_the_selection() -> void:
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]]}, "a")
	kit.add("wall", {"points": [[2000, 6000], [8000, 6000]]}, "b")
	kit.click(Vector2(5000, 2000))
	kit.click(Vector2(5000, 6000), true)
	assert_eq(kit.model.selection, ["a"], "Shift + click is for pasting settings")


# --- copy / paste settings ----------------------------------------------------------------------------


func test_shift_right_click_copies_and_shift_left_click_pastes_on_one_entity() -> void:
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]], "weight_mm": 2.5}, "src")
	kit.add("wall", {"points": [[2000, 6000], [8000, 6000]]}, "dst1")
	kit.add("wall", {"points": [[2000, 9000], [8000, 9000]]}, "dst2")
	assert_true(kit.rclick(Vector2(5000, 2000), true))
	assert_eq(kit.model.settings_clipboard["props"]["weight_mm"], 2.5)
	kit.click(Vector2(5000, 6000), true)
	assert_eq(_props("dst1")["weight_mm"], 2.5)
	assert_eq(_props("dst2")["weight_mm"], 1.4, "only the clicked entity")
	assert_eq(kit.model.selection, [], "pasting does not select")


func test_pasting_settings_on_another_type_or_with_nothing_copied_changes_nothing() -> void:
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]], "weight_mm": 2.5}, "w")
	_lamp("l", [5000, 6000])
	kit.click(Vector2(5000, 6000), true)
	assert_eq(seen.size(), 1, "nothing copied yet")
	kit.rclick(Vector2(5000, 2000), true)
	kit.click(Vector2(5000, 6000), true)
	assert_eq(_props("l")["count"], 1)
	assert_gte(seen.size(), 2, "told that nothing was changed")


func test_a_plain_right_click_does_nothing() -> void:
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]], "weight_mm": 2.5}, "w")
	assert_false(kit.rclick(Vector2(5000, 2000)))
	assert_true(kit.model.settings_clipboard.is_empty())


# --- anchoring by dragging ----------------------------------------------------------------------------


func test_alt_drag_a_symbol_onto_another_anchors_it_without_moving_anything() -> void:
	_lamp("parent", [3000, 3000], 1)
	_lamp("child", [6000, 3000], 2)
	kit.drag(Vector2(6000, 3000), Vector2(3000, 3000), false, false, true)
	assert_eq(_props("child")["anchor_parent"], "parent")
	assert_eq(_props("child")["anchor_offset"], [3000, 0])
	assert_eq(_props("child")["pos"], [6000, 3000], "it stayed where it was")
	assert_eq(kit.session.history.undo_depth(), 3, "one undo step for the anchoring (two adds before it)")
	kit.model.move_entities(["parent"], Vector2i(0, 1000))
	assert_eq(_props("child")["pos"], [6000, 4000], "now it follows")


func test_alt_dragging_a_selected_symbol_anchors_the_whole_selection() -> void:
	_lamp("parent", [3000, 3000], 1)
	_lamp("c1", [6000, 3000], 2)
	_lamp("c2", [6000, 5000], 3)
	kit.model.set_selection(["c1", "c2"])
	kit.drag(Vector2(6000, 3000), Vector2(3000, 3000), false, false, true)
	assert_eq(_props("c1")["anchor_parent"], "parent")
	assert_eq(_props("c2")["anchor_parent"], "parent")


func test_alt_drag_into_empty_space_or_onto_a_cycle_does_nothing() -> void:
	_lamp("a", [3000, 3000], 1)
	_lamp("b", [6000, 3000], 2)
	kit.drag(Vector2(6000, 3000), Vector2(9000, 9000), false, false, true)
	assert_eq(_props("b")["anchor_parent"], "")
	kit.model.set_selection(["b"])
	kit.model.anchor_selection_to("a")
	kit.drag(Vector2(3000, 3000), Vector2(6000, 3000), false, false, true)
	assert_eq(_props("a")["anchor_parent"], "", "a would depend on b which depends on a")


func test_the_anchor_drag_shows_a_line_while_it_runs() -> void:
	_lamp("a", [3000, 3000], 1)
	_lamp("b", [6000, 3000], 2)
	kit.move(Vector2(6000, 3000), false, false, true)
	kit.press(Vector2(6000, 3000), false, false, true)
	kit.move(Vector2(4500, 3000), false, false, true)
	assert_eq(kit.model.preview_list().ops.size(), 1)
	kit.release(Vector2(4500, 3000), false, false, true)
	assert_eq(kit.model.preview_list().ops.size(), 0)


func test_alt_right_click_detaches_the_symbol_under_the_cursor() -> void:
	_lamp("a", [3000, 3000], 1)
	_lamp("b", [6000, 3000], 2)
	kit.model.set_selection(["b"])
	kit.model.anchor_selection_to("a")
	kit.model.clear_selection()
	assert_true(kit.rclick(Vector2(6000, 3000), false, true))
	assert_eq(_props("b")["anchor_parent"], "")
	assert_eq(_props("b")["pos"], [6000, 3000])
