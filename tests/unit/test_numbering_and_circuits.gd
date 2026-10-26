extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD 5.2, FR-SYM-2/3/7/8, FR-LOOK-2, FR-FOCUS: circuits, indices, points, colours and focus.

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1", "Rez")
	TestKit.add_sheet(s, "s2", "Étage")
	doc = s.document()


func _add(sheet: String, id: String, circuit: String, index: int, type: String = "lamp", count: int = 1) -> void:
	var props: Dictionary = {"symbol_type": type, "pos": [1000, 1000], "circuit": circuit, "index": index, "count": count}
	var result: CommandResult = TestKit.add_entity(s, sheet, id, "symbol", props)
	assert_true(result.ok, result.error)


func _index_of(id: String) -> int:
	return TestKit.entity_props(doc, id)["index"]


func _apply(plan: Dictionary) -> void:
	var commands: Array[Command] = []
	for sheet_id: String in plan.keys():
		commands.append(s.command("entity.update", {"sheet": sheet_id, "items": plan[sheet_id]}))
	if not commands.is_empty():
		assert_true(s.run(commands).ok, s.last_error)


# --- Numbering ---------------------------------------------------------------------------------


func test_next_index_is_one_more_than_the_highest_in_the_circuit_across_all_sheets() -> void:
	assert_eq(Numbering.next_index(doc, "A"), 1)
	_add("s1", "a1", "A", 1)
	_add("s1", "a3", "A", 3)
	_add("s2", "a5", "A", 5)
	_add("s1", "b2", "B", 2)
	assert_eq(Numbering.next_index(doc, "A"), 6, "stable indices: gaps are not refilled (FR-SYM-8)")
	assert_eq(Numbering.next_index(doc, "B"), 3)
	assert_eq(Numbering.next_index(doc, "C"), 1)


func test_unassigned_symbols_and_markers_do_not_count() -> void:
	_add("s1", "u", "A", 0)
	_add("s1", "panel", "", 0, "panel")
	assert_eq(Numbering.next_index(doc, "A"), 1)
	assert_eq(Numbering.circuits_in_use(doc), ["A"], "a marker without a circuit is not a circuit")


func test_circuits_in_use_are_sorted_letters() -> void:
	_add("s1", "x", "C", 1)
	_add("s2", "y", "A", 1)
	_add("s1", "z", "C", 2)
	assert_eq(Numbering.circuits_in_use(doc), ["A", "C"])


func test_symbols_sharing_a_circuit_and_index_form_one_group() -> void:
	_add("s1", "lamp", "A", 2)
	_add("s1", "sw1", "A", 2, "switch")
	_add("s2", "sw2", "A", 2, "switch")
	_add("s1", "other", "A", 3)
	var groups: Dictionary = Numbering.groups(doc, "A")
	assert_eq(groups.keys(), [2, 3])
	assert_eq(groups[2], ["lamp", "sw1", "sw2"], "groups span étages, ids sorted")
	assert_eq(groups[3], ["other"])


func test_a_group_counts_as_one_point_whatever_its_size_or_count() -> void:
	_add("s1", "lamp", "A", 1)
	_add("s1", "sw1", "A", 1, "switch")
	_add("s1", "sw2", "A", 1, "switch")
	_add("s1", "triple", "A", 2, "socket", 3)
	_add("s1", "single", "A", 3, "socket")
	assert_eq(Numbering.point_count(doc, "A"), 3, "lamp+2 switches = 1, triple socket = 1, socket = 1 (SRD 5.2)")
	assert_eq(Numbering.point_count(doc, "B"), 0)


func test_unassigned_symbols_are_not_points_yet() -> void:
	_add("s1", "u", "A", 0)
	assert_eq(Numbering.point_count(doc, "A"), 0)


func test_compacting_closes_the_gaps_in_order_and_keeps_links() -> void:
	_add("s1", "a1", "A", 1)
	_add("s1", "a3", "A", 3)
	_add("s2", "a3b", "A", 3, "switch")
	_add("s1", "a7", "A", 7)
	_add("s1", "b4", "B", 4)
	_apply(Numbering.compact_plan(doc, "A"))
	assert_eq(_index_of("a1"), 1)
	assert_eq(_index_of("a3"), 2)
	assert_eq(_index_of("a3b"), 2, "the linked switch on another étage moved with its group")
	assert_eq(_index_of("a7"), 3)
	assert_eq(_index_of("b4"), 4, "other circuits are untouched when one circuit is compacted")


func test_compacting_every_circuit_and_when_there_is_nothing_to_do() -> void:
	_add("s1", "a2", "A", 2)
	_add("s1", "b5", "B", 5)
	_apply(Numbering.compact_plan(doc))
	assert_eq(_index_of("a2"), 1)
	assert_eq(_index_of("b5"), 1)
	assert_eq(Numbering.compact_plan(doc).size(), 0, "already compact: an empty plan, not a no-op command")


func test_compacting_leaves_unassigned_symbols_alone() -> void:
	_add("s1", "u", "A", 0)
	_add("s1", "a4", "A", 4)
	_apply(Numbering.compact_plan(doc, "A"))
	assert_eq(_index_of("u"), 0)
	assert_eq(_index_of("a4"), 1)


func test_reassigning_a_selection_to_another_circuit_keeps_its_groups_together() -> void:
	_add("s1", "lamp", "A", 2)
	_add("s1", "sw", "A", 2, "switch")
	_add("s1", "sock", "A", 5, "socket")
	_add("s1", "c1", "C", 1)
	var items: Array = Numbering.reassign_items(doc, "s1", ["lamp", "sw", "sock"], "C")
	_apply({"s1": items})
	assert_eq(TestKit.entity_props(doc, "lamp")["circuit"], "C")
	assert_eq(_index_of("lamp"), 2, "next free index in C after C1")
	assert_eq(_index_of("sw"), 2, "the switch stays linked to its lamp")
	assert_eq(_index_of("sock"), 3, "a different group gets the next index")


func test_reassigning_gives_unassigned_symbols_their_own_indices() -> void:
	_add("s1", "u1", "A", 0)
	_add("s1", "u2", "A", 0)
	_apply({"s1": Numbering.reassign_items(doc, "s1", ["u1", "u2"], "D")})
	assert_eq(_index_of("u1"), 1)
	assert_eq(_index_of("u2"), 2)


func test_reassigning_part_of_a_group_breaks_that_link_by_design() -> void:
	_add("s1", "lamp", "A", 2)
	_add("s1", "sw", "A", 2, "switch")
	_apply({"s1": Numbering.reassign_items(doc, "s1", ["sw"], "B")})
	assert_eq(TestKit.entity_props(doc, "sw")["circuit"], "B")
	assert_eq(TestKit.entity_props(doc, "lamp")["circuit"], "A", "the unselected lamp stays")


func test_reassigning_ignores_entities_that_are_not_circuit_symbols() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [10, 0]])
	_add("s1", "panel", "", 0, "panel")
	assert_eq(Numbering.reassign_items(doc, "s1", ["w", "panel"], "B").size(), 0)


# --- CircuitPalette -----------------------------------------------------------------------------


func test_there_are_26_letters_and_eight_distinct_colour_blind_safe_colours() -> void:
	assert_eq(CircuitPalette.LETTERS.size(), 26)
	assert_eq(CircuitPalette.LETTERS[0], "A")
	assert_eq(CircuitPalette.LETTERS[25], "Z")
	for i: int in 8:
		for j: int in range(i + 1, 8):
			var a: Color = CircuitPalette.COLORS[i]
			var b: Color = CircuitPalette.COLORS[j]
			var distance: float = Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_true(distance > 0.25, "colours %d and %d are clearly different" % [i, j])


func test_colours_repeat_after_eight_letters_but_the_pattern_tells_them_apart() -> void:
	assert_eq(CircuitPalette.color("A"), CircuitPalette.color("I"))
	assert_ne(CircuitPalette.pattern("A"), CircuitPalette.pattern("I"), "colour is never the only cue (FR-LOOK-2)")
	assert_eq(CircuitPalette.pattern("A"), 0)
	assert_eq(CircuitPalette.pattern("H"), 0)
	assert_eq(CircuitPalette.pattern("I"), 1)
	assert_eq(CircuitPalette.pattern("Z"), 3)


func test_non_letters_are_black_and_flagged() -> void:
	assert_eq(CircuitPalette.color(""), PlanTheme.BLACK)
	assert_eq(CircuitPalette.color("a"), PlanTheme.BLACK)
	assert_true(CircuitPalette.is_letter("Q"))
	assert_false(CircuitPalette.is_letter("q") or CircuitPalette.is_letter("AB") or CircuitPalette.is_letter(""))


# --- CircuitFocus ------------------------------------------------------------------------------------


var _all: Array[String] = ["A", "B", "C", "D"]


func test_nothing_is_dimmed_at_first() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	assert_eq(focus.dimmed_letters(), [])
	assert_false(focus.is_dimmed("A"))


func test_a_click_greys_a_circuit_out_and_another_click_restores_it() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.toggle("B")
	assert_true(focus.is_dimmed("B"))
	assert_false(focus.is_dimmed("A"))
	assert_eq(focus.dimmed_letters(), ["B"])
	focus.toggle("B")
	assert_false(focus.is_dimmed("B"))


func test_solo_greys_out_every_other_circuit() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.solo("C", _all)
	assert_eq(focus.dimmed_letters(), ["A", "B", "D"])
	assert_true(focus.is_solo("C"))
	assert_false(focus.is_dimmed("C"))


func test_double_clicking_the_solo_circuit_restores_what_was_visible_before() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.toggle("B")
	focus.solo("C", _all)
	focus.solo("C", _all)
	assert_eq(focus.dimmed_letters(), ["B"], "B was greyed before the solo and still is; A and D are back")
	assert_false(focus.is_solo("C"))


func test_toggling_during_a_solo_adds_to_what_is_visible_and_the_restore_still_goes_back_to_before() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.toggle("D")
	focus.solo("A", _all)
	focus.toggle("B")
	assert_false(focus.is_dimmed("B"), "clicking a greyed circuit shows it again")
	assert_true(focus.is_dimmed("C"))
	focus.solo("A", _all)
	assert_eq(focus.dimmed_letters(), ["D"])


func test_solo_on_a_greyed_circuit_shows_it() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.toggle("A")
	focus.solo("A", _all)
	assert_false(focus.is_dimmed("A"))


func test_soloing_another_circuit_replaces_the_solo_but_remembers_the_original_state() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.toggle("D")
	focus.solo("A", _all)
	focus.solo("B", _all)
	assert_true(focus.is_solo("B"))
	assert_eq(focus.dimmed_letters(), ["A", "C", "D"])
	focus.solo("B", _all)
	assert_eq(focus.dimmed_letters(), ["D"], "restores the state from before the first solo")


func test_circuits_that_appear_later_are_visible() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.solo("A", _all)
	assert_false(focus.is_dimmed("E"), "a circuit created after the solo is not greyed")


func test_reset_clears_everything() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	focus.solo("A", _all)
	focus.reset()
	assert_eq(focus.dimmed_letters(), [])
	assert_false(focus.is_solo("A"))


func test_focus_is_view_state_not_document_state() -> void:
	var focus: CircuitFocus = CircuitFocus.new()
	_add("s1", "a1", "A", 1)
	var before: String = TestKit.json(doc)
	focus.toggle("A")
	focus.solo("B", _all)
	assert_eq(TestKit.json(doc), before, "greying circuits never touches the project (ARCH-7)")
