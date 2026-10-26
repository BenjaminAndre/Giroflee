extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Placing and editing electric symbols from the keyboard and mouse (SRD FR-SYM, FR-FOCUS, FR-EDIT-3).

var kit: EditorKit
var _newest: String = ""


func before_each() -> void:
	kit = EditorKit.create()


func _symbols() -> Array[Entity]:
	return kit.entities_of("symbol")


## The symbol the latest _place created (ids are random, so "last in the list" means nothing).
func _last() -> Entity:
	return kit.sheet().entities[_newest]


func _place(world: Vector2, alt: bool = false) -> void:
	var before: Array[String] = kit.sheet().sorted_entity_ids()
	kit.click(world, false, false, alt)
	for entity_id: String in kit.sheet().sorted_entity_ids():
		if not before.has(entity_id):
			_newest = entity_id


# --- tools and keys -----------------------------------------------------------------------------


func test_the_symbol_keys_select_their_tools() -> void:
	kit.key(KEY_L)
	assert_eq(kit.model.tool_name, "lamp")
	kit.key(KEY_I)
	assert_eq(kit.model.tool_name, "switch")
	kit.key(KEY_I, true)
	assert_eq(kit.model.tool_name, "switch_two_way")
	kit.key(KEY_P)
	assert_eq(kit.model.tool_name, "socket")


func test_placing_gives_the_active_circuit_and_the_next_free_index() -> void:
	kit.key(KEY_L)
	_place(Vector2(2000, 2000))
	_place(Vector2(3000, 2000))
	var all: Array[Entity] = _symbols()
	assert_eq(all.size(), 2)
	for entity: Entity in all:
		assert_eq(entity.props["circuit"], "A")
		assert_eq(entity.props["symbol_type"], "lamp")
	var indices: Array = [all[0].props["index"], all[1].props["index"]]
	indices.sort()
	assert_eq(indices, [1, 2])
	assert_eq(kit.model.tool_name, "lamp", "the tool stays for the next one")


func test_alt_reuses_the_previous_index() -> void:
	kit.key(KEY_L)
	_place(Vector2(2000, 2000))
	kit.key(KEY_I)
	_place(Vector2(2600, 2000), true)
	var all: Array[Entity] = _symbols()
	assert_eq(all[0].props["index"], all[1].props["index"], "switch linked to the lamp")
	kit.key(KEY_L)
	_place(Vector2(4000, 2000))
	assert_eq(_last().props["index"], 2, "without Alt a new point")


func test_markers_take_no_circuit() -> void:
	kit.model.set_tool("panel")
	_place(Vector2(2000, 2000))
	assert_eq(_last().props["circuit"], "")
	assert_eq(_last().props["index"], 0)


func test_a_placed_symbol_already_has_its_labels_placed() -> void:
	kit.key(KEY_L)
	_place(Vector2(2000, 2000))
	assert_ne(_last().props["label_offset"], [0, 0])
	assert_eq(kit.session.history.undo_depth(), 1, "one undo step for the symbol and its labels")


# --- circuits, counts ---------------------------------------------------------------------------


func test_c_then_a_letter_sets_the_active_circuit_when_nothing_is_selected() -> void:
	kit.key(KEY_C)
	assert_eq(kit.model.pending_prefix, "C")
	kit.key(KEY_H)
	assert_eq(kit.model.pending_prefix, "")
	assert_eq(kit.model.active_circuit, "H")
	kit.key(KEY_L)
	_place(Vector2(2000, 2000))
	assert_eq(_last().props["circuit"], "H")
	assert_eq(_last().props["index"], 1, "first of its circuit")


func test_c_then_a_letter_reassigns_the_selection_keeping_links() -> void:
	kit.key(KEY_L)
	_place(Vector2(2000, 2000))
	kit.key(KEY_I)
	_place(Vector2(2600, 2000), true)
	kit.key(KEY_L)
	_place(Vector2(5000, 2000))
	kit.key(KEY_ESCAPE)
	kit.key(KEY_ESCAPE)
	kit.model.set_selection(kit.sheet().sorted_entity_ids())
	kit.key(KEY_C)
	kit.key(KEY_B)
	var by_pos: Dictionary = {}
	for entity: Entity in _symbols():
		assert_eq(entity.props["circuit"], "B")
		by_pos[entity.props["pos"][0]] = entity.props["index"]
	assert_eq(by_pos[2000], by_pos[2600], "the lamp and its switch are still one point")
	assert_ne(by_pos[2000], by_pos[5000])
	assert_eq(kit.model.active_circuit, "A", "only the symbols moved")


func test_c_then_something_else_cancels() -> void:
	kit.key(KEY_C)
	kit.key(KEY_5)
	assert_eq(kit.model.pending_prefix, "")
	assert_eq(kit.model.active_circuit, "A")
	kit.key(KEY_C)
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.pending_prefix, "")


func test_x_then_a_digit_sets_the_count_of_the_selection_or_of_the_next_placements() -> void:
	kit.key(KEY_P)
	_place(Vector2(2000, 2000))
	kit.model.set_selection([_last().id])
	kit.key(KEY_X)
	kit.key(KEY_3)
	assert_eq(_last().props["count"], 3)
	kit.model.clear_selection()
	kit.key(KEY_X)
	kit.key(KEY_2)
	assert_eq(kit.model.place_count, 2)
	_place(Vector2(4000, 2000))
	assert_eq(_last().props["count"], 2)


func test_digits_are_read_from_the_physical_key() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_AMPERSAND
	event.physical_keycode = KEY_1
	assert_eq(EditorInput.digit_of(event), 1, "AZERTY top row")


# --- sockets and walls --------------------------------------------------------------------------


func test_a_socket_sits_on_the_wall_edge_and_faces_into_the_room() -> void:
	kit.add("wall", {"points": [[0, 0], [5000, 0]]})
	kit.key(KEY_P)
	_place(Vector2(2500, 200))
	assert_eq(_last().props["pos"], [2500, 145], "35 mm to the wall's drawn edge (half the 1.4 mm line at 1:50) plus the 110 mm back of the symbol")
	assert_eq(_last().props["rotation"], 0.0)
	_place(Vector2(1500, -200))
	assert_eq(_last().props["pos"], [1500, -145])
	assert_eq(_last().props["rotation"], 180.0)


func test_rotating_by_hand_overrides_the_wall_orientation() -> void:
	kit.add("wall", {"points": [[0, 0], [5000, 0]]})
	kit.key(KEY_P)
	kit.key(KEY_R)
	_place(Vector2(2500, 200))
	assert_eq(_last().props["rotation"], 270.0)
	assert_eq(_last().props["pos"][1], 200 - 200 % 100, "on the grid, not on the wall")


func test_a_socket_far_from_any_wall_keeps_the_placement_rotation() -> void:
	kit.add("wall", {"points": [[0, 0], [5000, 0]]})
	kit.key(KEY_P)
	_place(Vector2(2500, 4000))
	assert_eq(_last().props["rotation"], 0.0)


# --- pipette ------------------------------------------------------------------------------------


func test_the_pipette_copies_a_symbol_into_its_tool_and_alt_links_to_it() -> void:
	kit.add("symbol", {"symbol_type": "socket", "pos": [3000, 3000], "circuit": "D", "index": 4, "count": 2, "rotation": 90.0, "flip_h": true}, "src")
	kit.move(Vector2(3000, 3000))
	kit.key(KEY_A)
	assert_eq(kit.model.tool_name, "socket")
	assert_eq(kit.model.active_circuit, "D")
	assert_eq(kit.model.place_count, 2)
	assert_eq(kit.model.place_rotation, 90.0)
	assert_true(kit.model.place_flip_h)
	_place(Vector2(6000, 3000), true)
	assert_eq(_last().props["circuit"], "D")
	assert_eq(_last().props["index"], 4, "Alt right after the pipette reuses its index")
	assert_eq(_last().props["rotation"], 90.0, "the pipetted rotation sticks")


func test_the_pipette_copies_openings_and_stairs_parameters() -> void:
	kit.add("opening", {"kind": "door", "pos": [1000, 1000], "width_mm": 800})
	kit.move(Vector2(1400, 1000))
	kit.key(KEY_A)
	assert_eq(kit.model.tool_name, "door")
	assert_eq(kit.model.defaults["door_width"], 800)


func test_the_pipette_over_nothing_does_nothing() -> void:
	kit.move(Vector2(9000, 9000))
	kit.key(KEY_A)
	assert_eq(kit.model.tool_name, "select")


# --- circuit focus ------------------------------------------------------------------------------


func test_greyed_out_circuits_are_not_picked_boxed_or_pipetted() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1}, "a1")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [4000, 2000], "circuit": "B", "index": 1}, "b1")
	kit.model.focus.toggle("A")
	kit.click(Vector2(2000, 2000))
	assert_eq(kit.model.selection, [], "not picked")
	kit.drag(Vector2(1000, 1000), Vector2(5000, 3000))
	assert_eq(kit.model.selection, ["b1"], "not box-selected")
	kit.model.set_tool("select")
	kit.move(Vector2(2000, 2000))
	kit.key(KEY_A)
	assert_eq(kit.model.tool_name, "select", "not pipetted")


func test_the_page_is_drawn_with_circuit_colours_and_grey_for_dimmed_circuits() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1}, "a1")
	var plain: DrawList = kit.model.page_list()
	kit.model.focus.toggle("A")
	var dimmed: DrawList = kit.model.page_list()
	var before: Color = Color.BLACK
	var after: Color = Color.BLACK
	for op: DrawOp in plain.ops:
		if op.layer == "symbols" and op.entity_id == "a1":
			before = op.color
	for op: DrawOp in dimmed.ops:
		if op.layer == "symbols" and op.entity_id == "a1":
			after = op.color
	assert_eq(before, CircuitPalette.color("A"))
	assert_eq(after, PlanTheme.GHOST)


# --- paste, numbering ---------------------------------------------------------------------------


func test_pasting_symbols_gives_fresh_indices_and_keeps_pairs_together() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1}, "l1")
	kit.add("symbol", {"symbol_type": "switch", "pos": [2600, 2000], "circuit": "A", "index": 1}, "s1")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [4000, 2000], "circuit": "A", "index": 2}, "l2")
	kit.model.set_selection(["l1", "s1"])
	kit.model.copy_selection()
	kit.model.paste(Vector2(8000, 8000))
	var fresh: Array[Entity] = []
	for entity: Entity in _symbols():
		if not ["l1", "s1", "l2"].has(entity.id):
			fresh.append(entity)
	assert_eq(fresh.size(), 2)
	assert_eq(fresh[0].props["index"], fresh[1].props["index"], "the pair is still a pair")
	assert_eq(fresh[0].props["index"], 3, "next free index of circuit A")


func test_compacting_the_numbering_closes_gaps_in_one_undo_step() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1}, "x1")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [3000, 2000], "circuit": "A", "index": 4}, "x4")
	kit.model.compact_numbering()
	assert_eq(kit.sheet().entities["x4"].props["index"], 2)
	kit.model.undo()
	assert_eq(kit.sheet().entities["x4"].props["index"], 4)


func test_replacing_the_labels_moves_unpinned_ones_only() -> void:
	kit.add("symbol", {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1, "label_offset": [1, 1]}, "free")
	kit.add("symbol", {"symbol_type": "lamp", "pos": [4000, 2000], "circuit": "A", "index": 2, "label_offset": [1, 1], "label_pinned": true}, "pinned")
	kit.model.relabel()
	assert_ne(kit.sheet().entities["free"].props["label_offset"], [1, 1])
	assert_eq(kit.sheet().entities["pinned"].props["label_offset"], [1, 1])
