extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Palette-level editing of symbols: quickbar (FR-QB), copy settings (FR-EDIT-7), select by filter
## (FR-EDIT-8), anchoring (FR-STACK-2).

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _entry(id: String) -> EditorCommands.Entry:
	for entry: EditorCommands.Entry in EditorCommands.build(kit.model):
		if entry.id == id:
			return entry
	assert_true(false, "no palette command %s" % id)
	return null


func _props(id: String) -> Dictionary:
	return kit.sheet().entities[id].props


func _lamp(id: String, pos: Array, circuit: String = "A", index: int = 1) -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": pos, "circuit": circuit, "index": index}, id)


# --- palette ------------------------------------------------------------------------------------


func test_the_palette_lists_the_symbol_commands_in_french() -> void:
	for id: String in ["tool.symbol.lamp", "tool.symbol.socket", "edit.pipette", "symbols.relabel", "symbols.compact",
			"anchor.set", "anchor.detach", "edit.copy_settings", "edit.paste_settings", "select.no_circuit", "select.custom_text", "quickbar.set.1", "quickbar.set.9"]:
		assert_not_null(_entry(id), id)
	assert_eq(_entry("tool.symbol.socket").shortcut, "P")
	assert_eq(_entry("tool.symbol.switch_two_way").shortcut, "Maj+I")
	assert_eq(_entry("symbols.compact").title, "Compacter la numérotation")
	assert_eq(_entry("anchor.set").title, "Ancrer à un symbole")


func test_circuit_selection_commands_appear_for_circuits_in_use() -> void:
	_lamp("a", [1000, 1000], "C")
	assert_not_null(_entry("select.circuit.C"))
	assert_eq(_entry("select.circuit.C").title, "Sélectionner tout le circuit C")


# --- quickbar -----------------------------------------------------------------------------------


func test_a_quickbar_slot_remembers_a_tool_with_its_settings() -> void:
	kit.key(KEY_P)
	kit.key(KEY_X)
	kit.key(KEY_3)
	kit.key(KEY_H)
	_entry("quickbar.set.2").action.call()
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.tool_name, "select")
	kit.model.place_count = 1
	kit.model.place_flip_h = false
	kit.key(KEY_2)
	assert_eq(kit.model.tool_name, "socket")
	assert_eq(kit.model.place_count, 3)
	assert_true(kit.model.place_flip_h)


func test_a_slot_remembers_door_width_and_wall_weight_but_not_the_circuit() -> void:
	kit.model.set_tool("door")
	kit.model.defaults["door_width"] = 800
	kit.model.store_quickbar(1)
	kit.model.set_config("wall_weight_mm", 2.0)
	kit.model.set_tool("wall")
	kit.model.store_quickbar(3)
	kit.model.set_config("wall_weight_mm", 1.4)
	kit.model.defaults["door_width"] = 900
	kit.model.active_circuit = "F"
	kit.key(KEY_1)
	assert_eq(kit.model.defaults["door_width"], 800)
	kit.key(KEY_3)
	assert_eq(kit.doc().config["wall_weight_mm"], 2.0)
	assert_eq(kit.model.active_circuit, "F", "the circuit is not part of a preset")


func test_an_empty_slot_says_so_and_the_select_tool_cannot_be_stored() -> void:
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	kit.key(KEY_4)
	assert_eq(seen.size(), 1)
	kit.model.store_quickbar(1)
	assert_false(kit.model.quickbar.is_filled(1))
	assert_eq(seen.size(), 2)


func test_digits_do_not_use_the_quickbar_while_a_prefix_is_waiting() -> void:
	kit.model.set_tool("lamp")
	kit.model.store_quickbar(2)
	kit.model.set_tool("select")
	kit.key(KEY_X)
	kit.key(KEY_2)
	assert_eq(kit.model.tool_name, "select", "X 2 sets a count, it does not open slot 2")
	assert_eq(kit.model.place_count, 2)


# --- copy settings ------------------------------------------------------------------------------


func test_copied_settings_apply_to_same_type_entities_only() -> void:
	kit.add("wall", {"points": [[0, 0], [1000, 0]], "weight_mm": 2.5}, "w1")
	kit.add("wall", {"points": [[0, 500], [1000, 500]]}, "w2")
	_lamp("l1", [3000, 3000])
	kit.model.set_selection(["w1"])
	kit.model.copy_settings()
	kit.model.set_selection(["w2", "l1"])
	kit.model.paste_settings()
	assert_eq(_props("w2")["weight_mm"], 2.5)
	assert_eq(_props("l1")["count"], 1, "the lamp is of another type: untouched")


func test_symbol_settings_leave_circuit_position_and_anchor_alone() -> void:
	kit.add("symbol", {"symbol_type": "socket", "pos": [1000, 1000], "circuit": "A", "index": 1, "count": 3, "flip_h": true, "rotation": 90.0}, "src")
	kit.add("symbol", {"symbol_type": "socket", "pos": [5000, 5000], "circuit": "B", "index": 7}, "dst")
	kit.model.set_selection(["src"])
	kit.model.copy_settings()
	kit.model.set_selection(["dst"])
	kit.model.paste_settings()
	var dst: Dictionary = _props("dst")
	assert_eq([dst["count"], dst["flip_h"], dst["rotation"]], [3, true, 90.0])
	assert_eq([dst["circuit"], dst["index"], dst["pos"]], ["B", 7, [5000, 5000]])


func test_copying_settings_needs_exactly_one_element() -> void:
	_lamp("a", [1000, 1000])
	_lamp("b", [2000, 1000], "A", 2)
	kit.model.set_selection(["a", "b"])
	kit.model.copy_settings()
	assert_true(kit.model.settings_clipboard.is_empty())


func test_pasting_settings_is_one_undo_step() -> void:
	kit.add("wall", {"points": [[0, 0], [1000, 0]], "weight_mm": 2.5}, "w1")
	kit.add("wall", {"points": [[0, 500], [1000, 500]]}, "w2")
	kit.add("wall", {"points": [[0, 900], [1000, 900]]}, "w3")
	kit.model.set_selection(["w1"])
	kit.model.copy_settings()
	kit.model.set_selection(["w2", "w3"])
	kit.model.paste_settings()
	kit.model.undo()
	assert_eq(_props("w2")["weight_mm"], 1.4)
	assert_eq(_props("w3")["weight_mm"], 1.4)


# --- select by filter ---------------------------------------------------------------------------


func test_select_by_circuit_and_by_type_and_without_circuit() -> void:
	_lamp("a1", [1000, 1000], "A")
	_lamp("b1", [2000, 1000], "B")
	kit.add("symbol", {"symbol_type": "socket", "pos": [3000, 1000], "circuit": "A", "index": 2}, "sock")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [4000, 1000]}, "bare")
	kit.add("symbol", {"symbol_type": "panel", "pos": [5000, 1000]}, "tgbt")
	_entry("select.circuit.A").action.call()
	assert_eq(kit.model.selection, ["a1", "sock"] if "a1" < "sock" else ["sock", "a1"], "circuit A")
	_entry("select.type.lamp").action.call()
	var lamps: Array = kit.model.selection.duplicate()
	lamps.sort()
	assert_eq(lamps, ["a1", "b1", "bare"])
	_entry("select.no_circuit").action.call()
	assert_eq(kit.model.selection, ["bare"], "the TGBT marker takes no circuit, so it is not 'without circuit'")


func test_select_custom_texts() -> void:
	kit.add("text", {"pos": [1000, 1000], "text": "salon"}, "plain")
	kit.add("text", {"pos": [2000, 1000], "text": "cuisine", "size_pt": 14.0}, "big")
	kit.add("text", {"pos": [3000, 1000], "text": "hall", "font": "OpenDyslexic"}, "font")
	_entry("select.custom_text").action.call()
	var chosen: Array = kit.model.selection.duplicate()
	chosen.sort()
	assert_eq(chosen, ["big", "font"])


func test_select_by_filter_skips_greyed_out_circuits() -> void:
	_lamp("a1", [1000, 1000], "A")
	_lamp("b1", [2000, 1000], "B")
	kit.model.focus.toggle("A")
	_entry("select.type.lamp").action.call()
	assert_eq(kit.model.selection, ["b1"])


# --- anchoring ----------------------------------------------------------------------------------


func test_anchoring_by_clicking_the_parent_makes_a_stack_that_moves_as_one() -> void:
	_lamp("socket", [2000, 2000], "A", 1)
	_lamp("switch", [2600, 2000], "A", 2)
	kit.model.set_selection(["switch"])
	_entry("anchor.set").action.call()
	assert_eq(kit.model.tool_name, "anchor")
	kit.click(Vector2(2000, 2000))
	assert_eq(kit.model.tool_name, "select", "the tool ends after the click")
	assert_eq(_props("switch")["anchor_parent"], "socket")
	assert_eq(_props("switch")["anchor_offset"], [600, 0])
	kit.model.move_entities(["socket"], Vector2i(0, 1000))
	assert_eq(_props("switch")["pos"], [2600, 3000], "it followed")


func test_anchoring_needs_selected_symbols_and_refuses_cycles() -> void:
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	_entry("anchor.set").action.call()
	assert_eq(kit.model.tool_name, "select")
	assert_eq(seen.size(), 1)
	_lamp("a", [1000, 1000], "A", 1)
	_lamp("b", [2000, 1000], "A", 2)
	kit.model.set_selection(["b"])
	assert_true(kit.model.anchor_selection_to("a").ok)
	kit.model.set_selection(["a"])
	assert_false(kit.model.anchor_selection_to("b").ok, "a would depend on b which depends on a")
	assert_eq(_props("a")["anchor_parent"], "")


func test_clicking_empty_space_keeps_the_anchor_tool_waiting() -> void:
	_lamp("a", [1000, 1000])
	kit.model.set_selection(["a"])
	kit.model.begin_anchor()
	kit.click(Vector2(9000, 9000))
	assert_eq(kit.model.tool_name, "anchor")
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.tool_name, "select")


func test_detaching_leaves_symbols_where_they_are() -> void:
	_lamp("p", [1000, 1000], "A", 1)
	_lamp("c", [1500, 1000], "A", 2)
	kit.model.set_selection(["c"])
	kit.model.anchor_selection_to("p")
	kit.model.set_selection(["c"])
	kit.model.detach_selection()
	assert_eq(_props("c")["anchor_parent"], "")
	assert_eq(_props("c")["pos"], [1500, 1000])
	kit.model.move_entities(["p"], Vector2i(0, 500))
	assert_eq(_props("c")["pos"], [1500, 1000], "no longer follows")


# --- labels by hand, stacks under transforms ----------------------------------------------------


func _label_centre(id: String) -> Vector2:
	var entity: Entity = kit.sheet().entities[id]
	return EntityGeometry.vec(entity.props["pos"]) + SymbolGeometry.effective_label_offset(entity, kit.model.ctx())


func test_dragging_a_label_places_it_and_pins_it() -> void:
	_lamp("l", [3000, 3000])
	var before: Vector2 = _label_centre("l")
	kit.drag(before, before + Vector2(400, 300))
	assert_true(_props("l")["label_pinned"])
	var after: Vector2 = _label_centre("l")
	assert_almost_eq(after.x, before.x + 400.0, 1.0)
	assert_almost_eq(after.y, before.y + 300.0, 1.0)
	assert_eq(_props("l")["pos"], [3000, 3000], "the symbol did not move")
	kit.model.undo()
	assert_false(_props("l")["label_pinned"], "one undo step")


func test_dragging_the_count_badge_moves_only_the_badge() -> void:
	kit.add("symbol", {"symbol_type": "socket", "pos": [3000, 3000], "circuit": "A", "index": 1, "count": 3}, "s")
	var entity: Entity = kit.sheet().entities["s"]
	var badge: Vector2 = EntityGeometry.vec(entity.props["pos"]) + SymbolGeometry.effective_count_offset(entity, kit.model.ctx())
	var label_before: Array = _props("s")["label_offset"]
	kit.drag(badge, badge + Vector2(-300, 0))
	assert_ne(_props("s")["count_offset"], [0, 0])
	assert_eq(_props("s")["label_offset"], label_before)


func test_clicking_a_label_selects_its_symbol() -> void:
	_lamp("l", [3000, 3000])
	kit.click(_label_centre("l"))
	assert_eq(kit.model.selection, ["l"])


func test_unpinning_lets_the_solver_move_the_label_again() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [3000, 3000], "circuit": "A", "index": 1, "label_offset": [5, 5], "label_pinned": true}, "l")
	kit.model.unpin_labels()
	assert_false(_props("l")["label_pinned"])
	kit.model.relabel()
	assert_ne(_props("l")["label_offset"], [5, 5])


func test_rotating_a_parent_turns_its_whole_stack_and_keeps_the_anchoring_sound() -> void:
	_lamp("p", [2000, 2000], "A", 1)
	_lamp("c", [2600, 2000], "A", 2)
	kit.model.set_selection(["c"])
	kit.model.anchor_selection_to("p")
	kit.model.set_selection(["p"])
	kit.model.rotate_selection(true)
	assert_eq(kit.doc().check_integrity(), "")
	assert_ne(_props("c")["pos"], [2600, 2000], "the child came along")
	var parent: Vector2 = EntityGeometry.vec(_props("p")["pos"])
	var child: Vector2 = EntityGeometry.vec(_props("c")["pos"])
	assert_almost_eq(parent.distance_to(child), 600.0, 1.0, "the stack turned rigidly")


func test_a_move_gesture_previews_the_whole_stack() -> void:
	_lamp("p", [2000, 2000], "A", 1)
	_lamp("c", [2600, 2000], "A", 2)
	kit.model.set_selection(["c"])
	kit.model.anchor_selection_to("p")
	kit.model.set_selection(["p"])
	kit.move(Vector2(2000, 2000))
	kit.press(Vector2(2000, 2000))
	kit.move(Vector2(2000, 3000))
	var overrides: Dictionary = kit.model.tool.overrides(kit.model)
	assert_true(overrides.has("p"))
	assert_true(overrides.has("c"), "the anchored symbol is drawn moving too")
	kit.release(Vector2(2000, 3000))
	assert_eq(_props("c")["pos"], [2600, 3000])


func test_changing_the_focus_refreshes_drawing_without_dirtying_the_project() -> void:
	_lamp("a", [1000, 1000])
	var revision: int = kit.model.revision
	var view_revision: int = kit.model.view_revision
	kit.model.focus_toggle("A")
	assert_eq(kit.model.revision, revision, "the project is not modified")
	assert_gt(kit.model.view_revision, view_revision, "but caches must redraw")
	kit.model.focus_solo("A", ["A", "B"])
	assert_eq(kit.model.focus.dimmed_letters(), ["B"])
