extends GutTest
@warning_ignore_start("unsafe_call_argument")

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _wall(points: Array, id: String = "") -> String:
	return kit.add("wall", {"points": points}, id)


func _pos(id: String) -> Array:
	return kit.doc().find_entity(id).props["pos"]


func test_click_selects_and_clicking_empty_space_clears() -> void:
	var w: String = _wall([[2000, 2000], [8000, 2000]])
	kit.click(Vector2(5000, 2000))
	assert_eq(kit.model.selection, [w])
	kit.click(Vector2(5000, 9000))
	assert_eq(kit.model.selection, [])


func test_shift_click_toggles_membership() -> void:
	var a: String = _wall([[2000, 2000], [8000, 2000]])
	var b: String = _wall([[2000, 6000], [8000, 6000]])
	kit.click(Vector2(5000, 2000))
	kit.click(Vector2(5000, 6000), true)
	assert_eq(kit.model.selection, [a, b])
	kit.click(Vector2(5000, 2000), true)
	assert_eq(kit.model.selection, [b])


func test_box_selection_selects_what_it_touches() -> void:
	var a: String = _wall([[2000, 2000], [4000, 2000]])
	var b: String = kit.add("grey_block", {"pos": [3000, 3000], "size": [500, 500]})
	_wall([[15000, 12000], [16000, 12000]])
	kit.drag(Vector2(1500, 1500), Vector2(5000, 4500))
	assert_eq(kit.model.selection.size(), 2)
	assert_true(kit.model.selection.has(a) and kit.model.selection.has(b))


func test_shift_box_adds_to_the_selection() -> void:
	var a: String = _wall([[2000, 2000], [4000, 2000]])
	var far: String = _wall([[15000, 12000], [16000, 12000]])
	kit.click(Vector2(3000, 2000))
	kit.drag(Vector2(14500, 11500), Vector2(16500, 12500), true)
	assert_true(kit.model.selection.has(a) and kit.model.selection.has(far))


func test_dragging_moves_the_selection_in_one_undo_step() -> void:
	var w: String = _wall([[2000, 2000], [6000, 2000]])
	var door: String = kit.add("opening", {"kind": "door", "pos": [3500, 2000], "width_mm": 900, "host_wall": w, "host_offset_mm": 1500})
	kit.session.history.clear()
	kit.drag(Vector2(4000, 2000), Vector2(4000, 4000))
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 4000], [6000, 4000]])
	assert_eq(_pos(door), [3500, 4000], "the hosted door followed the wall")
	assert_eq(kit.session.history.undo_depth(), 1)
	kit.key(KEY_Z, false, true)
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 2000], [6000, 2000]])
	assert_eq(_pos(door), [3500, 2000])


func test_drag_preview_uses_overrides_not_commands() -> void:
	var w: String = _wall([[2000, 2000], [6000, 2000]])
	kit.session.history.clear()
	kit.move(Vector2(4000, 2000))
	kit.press(Vector2(4000, 2000))
	kit.move(Vector2(4000, 3000))
	var overrides: Dictionary = kit.model.tool.overrides(kit.model)
	assert_true(overrides.has(w))
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 2000], [6000, 2000]], "nothing committed yet")
	assert_eq(kit.session.history.undo_depth(), 0)
	kit.release(Vector2(4000, 3000))
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 3000], [6000, 3000]])


func test_move_snaps_to_the_grid_so_deltas_are_whole_steps() -> void:
	var b: String = kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 1000]})
	kit.drag(Vector2(3500, 3500), Vector2(4630, 3480))
	assert_eq(_pos(b), [4100, 3000], "delta is the difference of two snapped points")


func test_pressing_a_selected_entity_keeps_the_group_until_release() -> void:
	var a: String = _wall([[2000, 2000], [4000, 2000]])
	var b: String = _wall([[2000, 6000], [4000, 6000]])
	kit.model.set_selection([a, b])
	kit.click(Vector2(3000, 2000))
	assert_eq(kit.model.selection, [a], "a plain click collapses to the clicked entity")
	kit.model.set_selection([a, b])
	kit.drag(Vector2(3000, 2000), Vector2(3000, 3000))
	assert_eq(kit.model.selection.size(), 2, "dragging keeps the whole group")
	assert_eq(kit.doc().find_entity(b).props["points"][0], [2000, 7000])


func test_escape_cancels_a_drag() -> void:
	var w: String = _wall([[2000, 2000], [6000, 2000]])
	kit.move(Vector2(4000, 2000))
	kit.press(Vector2(4000, 2000))
	kit.move(Vector2(4000, 5000))
	kit.key(KEY_ESCAPE)
	kit.release(Vector2(4000, 5000))
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 2000], [6000, 2000]])


func test_wall_vertex_handle_reshapes_the_wall() -> void:
	var w: String = _wall([[2000, 2000], [6000, 2000], [6000, 5000]])
	kit.model.set_selection([w])
	assert_eq(SelectTool.handles_for(kit.model).size(), 3)
	kit.drag(Vector2(6000, 2000), Vector2(7000, 2000))
	assert_eq(kit.doc().find_entity(w).props["points"], [[2000, 2000], [7000, 2000], [6000, 5000]])


func test_closed_wall_corner_handle_keeps_the_loop_closed() -> void:
	var w: String = _wall([[2000, 2000], [6000, 2000], [6000, 5000], [2000, 5000], [2000, 2000]])
	kit.model.set_selection([w])
	kit.drag(Vector2(2000, 2000), Vector2(1000, 1000))
	var points: Array = kit.doc().find_entity(w).props["points"]
	assert_eq(points[0], [1000, 1000])
	assert_eq(points[4], [1000, 1000], "first and last still coincide")


func test_grey_block_corner_handle_resizes_it() -> void:
	var b: String = kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 1000]})
	kit.model.set_selection([b])
	kit.drag(Vector2(4000, 4000), Vector2(5000, 4500))
	assert_eq(kit.doc().find_entity(b).props["pos"], [3000, 3000], "opposite corner stays")
	assert_eq(kit.doc().find_entity(b).props["size"], [2000, 1500])
	kit.drag(Vector2(3000, 3000), Vector2(2000, 2000))
	assert_eq(kit.doc().find_entity(b).props["pos"], [2000, 2000])
	assert_eq(kit.doc().find_entity(b).props["size"], [3000, 2500])


func test_block_handles_are_hidden_when_it_is_rotated() -> void:
	var b: String = kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 1000], "rotation": 90})
	kit.model.set_selection([b])
	assert_eq(SelectTool.handles_for(kit.model).size(), 0)


func test_double_click_on_a_text_asks_for_the_inline_editor() -> void:
	var t: String = kit.add("text", {"pos": [3000, 3000], "text": "Salon"})
	watch_signals(kit.model)
	kit.click(Vector2(3100, 3050), false, true)
	assert_signal_emitted(kit.model, "text_requested")
	assert_eq(get_signal_parameters(kit.model, "text_requested")[1], t)
	assert_eq(get_signal_parameters(kit.model, "text_requested")[2], "Salon")


func test_selection_is_dropped_when_undo_removes_the_entity() -> void:
	var w: String = _wall([[2000, 2000], [4000, 2000]])
	kit.model.set_selection([w])
	kit.session.undo()
	assert_eq(kit.model.selection, [])
