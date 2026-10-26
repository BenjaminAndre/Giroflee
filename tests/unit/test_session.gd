extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	s.history.clear()


func _doc() -> Document:
	return s.document()


func test_one_command_is_one_undo_step() -> void:
	TestKit.add_wall(s, "s1", "w", [[0, 0], [10, 0]])
	assert_true(s.can_undo())
	assert_true(s.undo())
	assert_false(_doc().has_entity("w"))
	assert_false(s.can_undo())
	assert_true(s.can_redo())
	assert_true(s.redo())
	assert_true(_doc().has_entity("w"))


func test_a_gesture_of_many_commands_is_one_undo_step() -> void:
	var commands: Array[Command] = [
		s.command("entity.add", {"sheet": "s1", "items": [{"id": "a", "type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1]}}]}),
		s.command("entity.add", {"sheet": "s1", "items": [{"id": "b", "type": "grey_block", "props": {"pos": [5, 5], "size": [1, 1]}}]}),
		s.command("entity.move", {"sheet": "s1", "ids": ["a", "b"], "delta": [10, 10]}),
	]
	assert_true(s.run(commands).ok)
	assert_eq(s.history.undo_depth(), 1)
	assert_eq(commands[0].tx, commands[2].tx, "commands share the transaction id")
	assert_true(s.undo())
	assert_false(_doc().has_entity("a"))
	assert_false(_doc().has_entity("b"))
	assert_true(s.redo())
	assert_eq(TestKit.entity_props(_doc(), "a")["pos"], [10, 10])
	assert_eq(TestKit.entity_props(_doc(), "b")["pos"], [15, 15])


func test_failed_gesture_rolls_back_and_records_nothing() -> void:
	var before: String = TestKit.json(_doc())
	var commands: Array[Command] = [
		s.command("entity.add", {"sheet": "s1", "items": [{"id": "a", "type": "grey_block", "props": {"pos": [0, 0], "size": [1, 1]}}]}),
		s.command("entity.move", {"sheet": "s1", "ids": ["nope"], "delta": [1, 1]}),
	]
	var result: CommandResult = s.run(commands)
	assert_false(result.ok)
	assert_eq(s.last_error, result.error)
	assert_eq(TestKit.json(_doc()), before, "first command was rolled back")
	assert_false(s.can_undo())


func test_new_action_clears_redo() -> void:
	TestKit.add_wall(s, "s1", "w1", [[0, 0], [10, 0]])
	s.undo()
	assert_true(s.can_redo())
	TestKit.add_wall(s, "s1", "w2", [[0, 0], [0, 10]])
	assert_false(s.can_redo())
	assert_false(s.redo())


func test_undo_and_redo_on_empty_history_do_nothing() -> void:
	assert_false(s.undo())
	assert_false(s.redo())
	assert_eq(s.last_error, "")


func test_changed_signal_fires_once_per_transaction_undo_and_redo() -> void:
	watch_signals(s)
	TestKit.add_wall(s, "s1", "w", [[0, 0], [10, 0]])
	s.undo()
	s.redo()
	assert_signal_emit_count(s, "changed", 3)


func test_failed_run_does_not_emit_changed() -> void:
	watch_signals(s)
	s.run_one("entity.remove", {"sheet": "s1", "ids": ["ghost"]})
	assert_signal_not_emitted(s, "changed")


func test_undo_fails_cleanly_when_the_document_changed_underneath() -> void:
	TestKit.add_symbol(s, "s1", "sym", [0, 0])
	# simulate a conflicting edit that bypasses this session's history (another client)
	var other: Command = Command.make("entity.update", {"sheet": "s1", "items": [{"id": "sym", "props": {"count": 4}}]}, "other-client-1")
	assert_true(s.channel.submit(other).ok)
	var before: String = TestKit.json(_doc())
	assert_false(s.undo(), "undoing the add would silently delete the other client's edit")
	assert_string_contains(s.last_error, "changed since")
	assert_eq(TestKit.json(_doc()), before)
	assert_true(s.can_undo(), "the entry stays on the stack")


func test_run_with_no_commands_fails() -> void:
	var empty: Array[Command] = []
	assert_false(s.run(empty).ok)


func test_no_op_gesture_is_not_recorded() -> void:
	TestKit.add_symbol(s, "s1", "sym", [3, 3])
	s.history.clear()
	assert_true(s.run_one("entity.move", {"sheet": "s1", "ids": ["sym"], "delta": [0, 0]}).ok)
	assert_false(s.can_undo())


func test_commands_get_unique_ids_and_the_author() -> void:
	var a: Command = s.command("sheet.update", {})
	var b: Command = s.command("sheet.update", {})
	assert_ne(a.id, b.id)
	assert_eq(a.author, "local")
