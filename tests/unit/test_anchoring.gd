extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD FR-STACK: anchoring a symbol to another symbol makes a stack. The commands keep the invariant
## `anchor_offset == pos - parent.pos` true, so a stack always moves as one and undo is exact.

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	TestKit.add_sheet(s, "s2")
	doc = s.document()


func _sym(id: String, pos: Array, parent: String = "", offset: Array = [0, 0], sheet: String = "s1") -> CommandResult:
	var props: Dictionary = {"symbol_type": "socket", "pos": pos, "circuit": "A", "index": 1, "anchor_parent": parent, "anchor_offset": offset}
	return TestKit.add_entity(s, sheet, id, "symbol", props)


func _p(id: String) -> Dictionary:
	return TestKit.entity_props(doc, id)


func _stack() -> void:
	# socket (low) <- switch (waist) <- lamp (high), drawn side by side on the plan
	_sym("socket", [1000, 1000])
	_sym("switch", [1400, 1000], "socket", [400, 0])
	_sym("lamp", [1800, 1000], "switch", [400, 0])


# --- adding ---------------------------------------------------------------------------------------------


func test_a_symbol_can_be_added_already_anchored() -> void:
	_sym("a", [1000, 1000])
	var result: CommandResult = _sym("b", [1300, 1100], "a", [300, 100])
	assert_true(result.ok, result.error)
	assert_eq(_p("b")["anchor_parent"], "a")


func test_an_inconsistent_offset_is_refused() -> void:
	_sym("a", [1000, 1000])
	var result: CommandResult = _sym("b", [1300, 1100], "a", [999, 0])
	assert_false(result.ok)
	assert_string_contains(result.error, "offset")


func test_the_parent_must_exist_be_a_symbol_and_not_the_symbol_itself() -> void:
	assert_false(_sym("orphan", [0, 0], "ghost", [0, 0]).ok, "unknown parent")
	TestKit.add_wall(s, "s1", "w", [[0, 0], [10, 0]])
	var on_wall: CommandResult = _sym("c", [0, 0], "w", [0, 0])
	assert_false(on_wall.ok, "a wall cannot be an anchor parent")
	assert_false(_sym("self", [0, 0], "self", [0, 0]).ok)


func test_children_and_parents_can_be_added_in_one_batch_in_any_order() -> void:
	var items: Array = [
		{"id": "kid", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [500, 500], "circuit": "A", "index": 1, "anchor_parent": "mum", "anchor_offset": [100, 0]}},
		{"id": "mum", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [400, 500], "circuit": "A", "index": 2}},
	]
	assert_true(s.run_one("entity.add", {"sheet": "s1", "items": items}).ok)


func test_a_parent_on_another_etage_is_refused() -> void:
	_sym("a", [0, 0], "", [0, 0], "s2")
	assert_false(_sym("b", [100, 0], "a", [100, 0], "s1").ok, "stacks live on one étage")


# --- updating --------------------------------------------------------------------------------------------


func test_anchoring_an_existing_symbol() -> void:
	_sym("a", [1000, 1000])
	_sym("b", [1500, 1000])
	var result: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"anchor_parent": "a", "anchor_offset": [500, 0]}}]})
	assert_true(result.ok, result.error)


func test_a_wrong_offset_in_an_update_is_refused() -> void:
	_sym("a", [1000, 1000])
	_sym("b", [1500, 1000])
	var result: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"anchor_parent": "a", "anchor_offset": [1, 0]}}]})
	assert_false(result.ok)
	assert_eq(_p("b")["anchor_parent"], "", "nothing changed")


func test_cycles_are_refused() -> void:
	_stack()
	var result: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "socket", "props": {"anchor_parent": "lamp", "anchor_offset": [800, 0]}}]})
	assert_false(result.ok)
	assert_string_contains(result.error, "cycle")


func test_moving_a_child_with_update_requires_its_offset_to_follow() -> void:
	_sym("a", [1000, 1000])
	_sym("b", [1300, 1000], "a", [300, 0])
	assert_false(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"pos": [1300, 1500]}}]}).ok, "stale offset")
	var ok: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"pos": [1300, 1500], "anchor_offset": [300, 500]}}]})
	assert_true(ok.ok, ok.error)


func test_moving_a_parent_with_update_must_carry_the_children() -> void:
	_sym("a", [1000, 1000])
	_sym("b", [1300, 1000], "a", [300, 0])
	var alone: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "a", "props": {"pos": [2000, 1000]}}]})
	assert_false(alone.ok, "the child would be left behind with a stale offset")
	var together: CommandResult = s.run_one("entity.update", {"sheet": "s1", "items": [
		{"id": "a", "props": {"pos": [2000, 1000]}},
		{"id": "b", "props": {"pos": [2300, 1000]}},
	]})
	assert_true(together.ok, together.error)


func test_detaching_resets_the_offset() -> void:
	_sym("a", [1000, 1000])
	_sym("b", [1300, 1000], "a", [300, 0])
	assert_true(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"anchor_parent": "", "anchor_offset": [0, 0]}}]}).ok)
	assert_eq(_p("b")["anchor_parent"], "")
	assert_false(s.run_one("entity.update", {"sheet": "s1", "items": [{"id": "b", "props": {"anchor_parent": "", "anchor_offset": [5, 5]}}]}).ok, "an unanchored symbol keeps a zero offset")


# --- moving ----------------------------------------------------------------------------------------------


func test_moving_a_parent_carries_the_whole_stack_once() -> void:
	_stack()
	assert_true(s.run_one("entity.move", {"sheet": "s1", "ids": ["socket"], "delta": [0, 500]}).ok)
	assert_eq(_p("socket")["pos"], [1000, 1500])
	assert_eq(_p("switch")["pos"], [1400, 1500])
	assert_eq(_p("lamp")["pos"], [1800, 1500])
	assert_eq(_p("switch")["anchor_offset"], [400, 0], "offsets unchanged: it moved with its parent")
	assert_eq(doc.check_integrity(), "")


func test_selecting_a_parent_and_its_child_does_not_move_the_child_twice() -> void:
	_stack()
	assert_true(s.run_one("entity.move", {"sheet": "s1", "ids": ["socket", "switch"], "delta": [100, 0]}).ok)
	assert_eq(_p("switch")["pos"], [1500, 1000])
	assert_eq(_p("lamp")["pos"], [1900, 1000])


func test_moving_a_child_alone_changes_only_its_offset() -> void:
	_stack()
	assert_true(s.run_one("entity.move", {"sheet": "s1", "ids": ["switch"], "delta": [0, 300]}).ok)
	assert_eq(_p("socket")["pos"], [1000, 1000], "the parent stays")
	assert_eq(_p("switch")["pos"], [1400, 1300])
	assert_eq(_p("switch")["anchor_offset"], [400, 300], "its place within the stack changed")
	assert_eq(_p("lamp")["pos"], [1800, 1300], "its own child went along")
	assert_eq(_p("lamp")["anchor_offset"], [400, 0])
	assert_eq(doc.check_integrity(), "")


func test_a_move_of_a_stack_is_one_undo_step() -> void:
	_stack()
	s.history.clear()
	s.run_one("entity.move", {"sheet": "s1", "ids": ["socket"], "delta": [700, 0]})
	assert_eq(s.history.undo_depth(), 1)
	assert_true(s.undo())
	assert_eq(_p("lamp")["pos"], [1800, 1000])
	assert_eq(doc.check_integrity(), "")


# --- removing --------------------------------------------------------------------------------------------


func test_deleting_a_parent_frees_its_children_where_they_are() -> void:
	_stack()
	assert_true(s.run_one("entity.remove", {"sheet": "s1", "ids": ["switch"]}).ok)
	assert_eq(_p("lamp")["anchor_parent"], "", "the lamp no longer hangs on a deleted switch")
	assert_eq(_p("lamp")["anchor_offset"], [0, 0])
	assert_eq(_p("lamp")["pos"], [1800, 1000], "it stays where it was")
	assert_eq(_p("socket")["pos"], [1000, 1000])
	assert_eq(doc.check_integrity(), "")
	assert_true(s.undo())
	assert_eq(_p("lamp")["anchor_parent"], "switch", "undo restores the stack")


func test_deleting_a_whole_stack_is_fine() -> void:
	_stack()
	assert_true(s.run_one("entity.remove", {"sheet": "s1", "ids": ["socket", "switch", "lamp"]}).ok)
	assert_eq(doc.check_integrity(), "")


func test_deleting_a_child_leaves_the_parent_alone() -> void:
	_stack()
	assert_true(s.run_one("entity.remove", {"sheet": "s1", "ids": ["lamp"]}).ok)
	assert_eq(_p("switch")["anchor_parent"], "socket")


# --- closure helpers and integrity -----------------------------------------------------------------------


func test_descendants_are_the_whole_chain_in_id_order() -> void:
	_stack()
	var sheet: Sheet = doc.get_sheet("s1")
	assert_eq(AnchorRules.descendants(sheet, ["socket"]), ["lamp", "switch"])
	assert_eq(AnchorRules.descendants(sheet, ["switch"]), ["lamp"])
	assert_eq(AnchorRules.descendants(sheet, ["lamp"]), [])
	assert_eq(AnchorRules.descendants(sheet, ["socket", "switch"]), ["lamp"], "already-listed ids are not repeated")


func test_integrity_check_catches_a_broken_stack_in_a_loaded_file() -> void:
	_stack()
	var raw: Dictionary = JSON.parse_string(TestKit.json(doc))
	var sheets: Array = raw["sheets"]
	var first: Dictionary = sheets[0]
	var entities: Array = first["entities"]
	for item: Variant in entities:
		var entity: Dictionary = item
		if entity["id"] == "lamp":
			var props: Dictionary = entity["props"]
			props["anchor_offset"] = [1, 1]
	var loaded: DocumentIO.LoadResult = DocumentIO.from_dict(raw)
	assert_null(loaded.document, "a stale anchor offset is a corrupt file")
	assert_string_contains(loaded.error, "offset")


func test_recompute_offsets_after_a_transform() -> void:
	_stack()
	var sheet: Sheet = doc.get_sheet("s1")
	var moved: Dictionary = {}
	for id: String in ["socket", "switch", "lamp"]:
		var e: Entity = sheet.entities[id]
		moved[id] = EntityMover.rotated_props_90("symbol", e.props, Vector2i(1000, 1000), true)
	var fixed: Dictionary = AnchorRules.recompute_offsets(sheet, moved)
	var offset: Array = fixed["switch"]["anchor_offset"]
	assert_eq(offset, [0, 400], "rotated 90 degrees CCW about the parent: +x becomes +y")
	var lamp_offset: Array = fixed["lamp"]["anchor_offset"]
	assert_eq(lamp_offset, [0, 400])


# --- copy, paste and duplicate -----------------------------------------------------------------------------


func test_copying_a_parent_copies_its_stack_and_pasting_recreates_the_anchoring() -> void:
	_stack()
	var sheet: Sheet = doc.get_sheet("s1")
	var parsed: Dictionary = Clipboard.parse(Clipboard.serialize(sheet, ["socket"]))
	var items: Array = parsed["items"]
	assert_eq(items.size(), 3, "the switch and the lamp come along (FR-STACK-3)")
	var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(5000, 5000), IdGenerator.new(8))
	assert_true(s.run_one("entity.add", {"sheet": "s2", "items": built["items"]}).ok, s.last_error)
	var roots: int = 0
	var new_ids: Array = built["new_ids"]
	for raw_id: Variant in new_ids:
		var props: Dictionary = TestKit.entity_props(doc, str(raw_id))
		if str(props["anchor_parent"]).is_empty():
			roots += 1
		else:
			assert_true(new_ids.has(props["anchor_parent"]), "anchored to the copy, not the original")
	assert_eq(roots, 1)
	assert_eq(doc.check_integrity(), "")


func test_copying_a_child_alone_drops_its_anchor() -> void:
	_stack()
	var parsed: Dictionary = Clipboard.parse(Clipboard.serialize(doc.get_sheet("s1"), ["switch"]))
	var items: Array = parsed["items"]
	assert_eq(items.size(), 2, "the switch and its own child, the lamp")
	var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(0, 0), IdGenerator.new(9))
	assert_true(s.run_one("entity.add", {"sheet": "s2", "items": built["items"]}).ok, s.last_error)
	var roots: Array[String] = []
	var new_ids: Array = built["new_ids"]
	for raw_id: Variant in new_ids:
		if str(_p(str(raw_id))["anchor_parent"]).is_empty():
			roots.append(str(raw_id))
	assert_eq(roots.size(), 1, "the copied switch is the root: its parent was not copied")
	assert_eq(_p(roots[0])["anchor_offset"], [0, 0])


func test_duplicating_an_etage_with_symbols_keeps_the_stacks() -> void:
	var kit: EditorKit = EditorKit.create()
	var source: String = kit.model.active_sheet_id
	for item: Dictionary in [
		{"id": "k-sock", "pos": [1000, 1000], "p": "", "o": [0, 0]},
		{"id": "k-sw", "pos": [1400, 1000], "p": "k-sock", "o": [400, 0]},
	]:
		var props: Dictionary = {"symbol_type": "socket", "pos": item["pos"], "circuit": "A", "index": 1, "anchor_parent": item["p"], "anchor_offset": item["o"]}
		assert_true(kit.model.add_entities([{"id": item["id"], "type": "symbol", "props": props}]).ok)
	kit.model.duplicate_sheet(true)
	var copies: Array[Entity] = kit.entities_of("symbol")
	assert_eq(copies.size(), 2)
	for entity: Entity in copies:
		if not str(entity.props["anchor_parent"]).is_empty():
			assert_true(kit.sheet().entities.has(entity.props["anchor_parent"]), "anchored to the copy on the new étage")
			assert_ne(entity.props["anchor_parent"], "k-sock")
	assert_ne(kit.model.active_sheet_id, source)
	assert_eq(kit.doc().check_integrity(), "")


# --- transforms carry stacks -------------------------------------------------------------------------------------


func test_a_transform_of_a_parent_carries_its_stack_as_followers() -> void:
	_stack()
	var expanded: Dictionary = SelectionTransform.with_followers(doc.get_sheet("s1"), ["socket"])
	assert_eq(expanded["followers"], ["lamp", "switch"])
	var expanded_ids: Array = expanded["ids"]
	assert_eq(expanded_ids, ["socket", "lamp", "switch"])
