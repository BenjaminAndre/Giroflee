extends GutTest
@warning_ignore_start("unsafe_call_argument")


func test_invert_reverses_order_and_swaps_states() -> void:
	var ops: Array[Dictionary] = [
		Patch.value_op("cartouche", "a", null, 1),
		Patch.value_op("cartouche", "a", 1, 2),
	]
	var inverse: Array[Dictionary] = Patch.invert(ops)
	assert_eq(inverse.size(), 2)
	assert_eq(inverse[0]["before"], 2)
	assert_eq(inverse[0]["after"], 1)
	assert_eq(inverse[1]["before"], 1)
	assert_eq(inverse[1]["after"], null)


func test_invert_twice_is_identity() -> void:
	var ops: Array[Dictionary] = [
		Patch.entity_op("s", "e", null, {"type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1], "rotation": 0.0}}),
		Patch.order_op(["a"], ["a", "b"]),
	]
	assert_eq(Patch.invert(Patch.invert(ops)), ops)


func test_invert_does_not_alias_the_source() -> void:
	var state: Dictionary = {"type": "grey_block", "props": {"pos": [0, 0]}}
	var ops: Array[Dictionary] = [Patch.entity_op("s", "e", state, null)]
	var inverse: Array[Dictionary] = Patch.invert(ops)
	var after: Dictionary = inverse[0]["after"]
	var props: Dictionary = after["props"]
	props["pos"] = [9, 9]
	var original_props: Dictionary = state["props"]
	assert_eq(original_props["pos"], [0, 0])


func test_applier_adds_updates_and_removes_entities() -> void:
	var doc: Document = Document.new_project()
	var setup: Array[Dictionary] = [
		Patch.sheet_op("s", null, {"kind": "plan", "props": Schema.normalize(Schema.SHEET_SPEC, {"name": "A"}, true)["props"]}),
		Patch.order_op([], ["s"]),
		Patch.entity_op("s", "e", null, {"type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1], "rotation": 0.0}}),
	]
	assert_eq(PatchApplier.apply(doc, setup), "")
	assert_true(doc.has_entity("e"))
	var update: Array[Dictionary] = [
		Patch.entity_op("s", "e",
			{"type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1], "rotation": 0.0}},
			{"type": "grey_block", "props": {"pos": [5, 5], "size": [1, 1], "rotation": 0.0}}),
	]
	assert_eq(PatchApplier.apply(doc, update), "")
	assert_eq(TestKit.entity_props(doc, "e")["pos"], [5, 5])
	assert_eq(PatchApplier.apply(doc, Patch.invert(update)), "")
	assert_eq(TestKit.entity_props(doc, "e")["pos"], [0, 0])
	assert_eq(PatchApplier.apply(doc, Patch.invert(setup)), "")
	assert_eq(doc.sheets.size(), 0)
	assert_eq(doc.check_integrity(), "")


func test_applier_rolls_back_everything_when_a_later_op_fails() -> void:
	var doc: Document = Document.new_project()
	var ops: Array[Dictionary] = [
		Patch.value_op("cartouche", "ok", null, "fine"),
		Patch.value_op("cartouche", "bad", "was-never-there", "x"),
	]
	var error: String = PatchApplier.apply(doc, ops)
	assert_ne(error, "")
	assert_string_contains(error, "op 1")
	assert_false(doc.cartouche.has("ok"), "op 0 rolled back")


func test_applier_without_check_before_is_lenient() -> void:
	var doc: Document = Document.new_project()
	var ops: Array[Dictionary] = [Patch.value_op("cartouche", "k", "ignored", "v")]
	assert_eq(PatchApplier.apply(doc, ops, false), "")
	assert_eq(doc.cartouche["k"], "v")


func test_applier_refuses_to_delete_a_sheet_that_still_has_entities() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "s1")
	TestKit.add_wall(s, "s1", "w", [[0, 0], [1, 0]])
	var doc: Document = s.document()
	var meta: Dictionary = doc.get_sheet("s1").meta()
	var error: String = PatchApplier.apply(doc, [Patch.sheet_op("s1", meta, null)])
	assert_string_contains(error, "still holds entities")
	assert_true(doc.sheets.has("s1"))


func test_validate_ops_accepts_a_real_patch() -> void:
	var s: Session = TestKit.session()
	var result: CommandResult = TestKit.add_sheet(s, "s1")
	assert_eq(Patch.validate_ops(result.patch.ops), "")
