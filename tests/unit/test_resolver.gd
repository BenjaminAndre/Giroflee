extends GutTest
@warning_ignore_start("unsafe_call_argument")

var doc: Document
var resolver: Resolver
var counter: int = 0


func before_each() -> void:
	doc = Document.new_project()
	resolver = Resolver.new(doc)
	counter = 0


func _cmd(type: String, payload: Dictionary, id: String = "") -> Command:
	counter += 1
	return Command.make(type, payload, id if not id.is_empty() else "c%d" % counter)


func _add_sheet(sheet_id: String = "s1") -> CommandResult:
	return resolver.submit(_cmd("sheet.add", {"id": sheet_id, "kind": "plan", "props": {"name": "Rez"}}))


func test_submit_applies_numbers_and_returns_the_patch() -> void:
	var result: CommandResult = _add_sheet()
	assert_true(result.ok, result.error)
	assert_eq(result.patch.seq, 1)
	assert_eq(result.patch.command_id, "c1")
	assert_eq(resolver.seq, 1)
	assert_true(doc.sheets.has("s1"))
	var second: CommandResult = _add_sheet("s2")
	assert_eq(second.patch.seq, 2, "seq increases monotonically")


func test_committed_signal_carries_the_patch() -> void:
	watch_signals(resolver)
	_add_sheet()
	assert_signal_emit_count(resolver, "committed", 1)
	var params: Array = get_signal_parameters(resolver, "committed")
	var patch: Patch = params[0]
	assert_eq(patch.seq, 1)
	assert_eq(patch.ops.size(), 2, "sheet op + order op")


func test_failed_command_changes_nothing_and_emits_nothing() -> void:
	_add_sheet()
	var before: String = DocumentIO.to_json(doc)
	watch_signals(resolver)
	var result: CommandResult = resolver.submit(_cmd("sheet.add", {"id": "s1", "kind": "plan", "props": {"name": "dup"}}))
	assert_false(result.ok)
	assert_signal_not_emitted(resolver, "committed")
	assert_eq(DocumentIO.to_json(doc), before)
	assert_eq(resolver.seq, 1, "failed commands are not numbered")


func test_unknown_type_and_missing_id_are_rejected() -> void:
	assert_false(resolver.submit(_cmd("frobnicate", {})).ok)
	assert_false(resolver.submit(Command.make("sheet.add", {}, "")).ok)


func test_a_command_id_can_only_be_applied_once() -> void:
	var first: CommandResult = _add_sheet()
	assert_true(first.ok)
	var again: CommandResult = resolver.submit(_cmd("sheet.add", {"id": "s2", "kind": "plan", "props": {"name": "X"}}, "c1"))
	assert_false(again.ok)
	assert_string_contains(again.error, "already applied")
	assert_false(doc.sheets.has("s2"))


func test_a_failed_command_id_may_be_retried() -> void:
	var bad: CommandResult = resolver.submit(_cmd("entity.add", {"sheet": "s1", "items": []}, "retry"))
	assert_false(bad.ok)
	_add_sheet()
	var good: CommandResult = resolver.submit(_cmd("entity.add", {"sheet": "s1", "items": []}, "retry"))
	assert_true(good.ok, good.error)


func test_every_registered_type_has_a_handler() -> void:
	var names: PackedStringArray = CommandRegistry.types()
	assert_true(names.size() >= 11)
	for name: String in names:
		assert_true(CommandRegistry.handler_for(name).is_valid(), name)
	assert_false(CommandRegistry.handler_for("nope").is_valid())


func test_patch_apply_with_stale_before_state_is_rejected_atomically() -> void:
	_add_sheet()
	resolver.submit(_cmd("entity.add", {"sheet": "s1", "items": [{"id": "g", "type": "grey_block", "props": {"pos": [0, 0], "size": [10, 10]}}]}))
	var snapshot: String = DocumentIO.to_json(doc)
	var stale: Dictionary = {
		"op": "entity", "sheet": "s1", "id": "g",
		"before": {"type": "grey_block", "props": {"pos": [999, 999], "size": [10, 10], "rotation": 0.0}},
		"after": null,
	}
	var good: Dictionary = {"op": "value", "section": "cartouche", "key": "k", "before": null, "after": "v"}
	var result: CommandResult = resolver.submit(_cmd("patch.apply", {"ops": [good, stale]}))
	assert_false(result.ok)
	assert_string_contains(result.error, "changed since")
	assert_eq(DocumentIO.to_json(doc), snapshot, "the first (valid) op was rolled back too")


func test_patch_apply_validates_structure() -> void:
	assert_false(resolver.submit(_cmd("patch.apply", {})).ok)
	assert_false(resolver.submit(_cmd("patch.apply", {"ops": [1]})).ok)
	assert_false(resolver.submit(_cmd("patch.apply", {"ops": [{"op": "teleport", "before": 1, "after": 2}]})).ok)
	assert_false(resolver.submit(_cmd("patch.apply", {"ops": [{"op": "value", "section": "cartouche", "key": "k", "before": null, "after": null}]})).ok, "neither before nor after")
	assert_false(resolver.submit(_cmd("patch.apply", {"ops": [{"op": "value", "section": "nope", "key": "k", "before": null, "after": 1}]})).ok)


func test_in_process_channel_forwards_commits() -> void:
	var channel: InProcessChannel = InProcessChannel.new(Document.new_project())
	watch_signals(channel)
	var result: CommandResult = channel.submit(Command.make("sheet.add", {"id": "s", "kind": "plan", "props": {"name": "A"}}, "x1"))
	assert_true(result.ok)
	assert_signal_emit_count(channel, "committed", 1)
	assert_true(channel.get_document().sheets.has("s"))


func test_abstract_channel_refuses() -> void:
	var channel: CommandChannel = CommandChannel.new()
	assert_false(channel.submit(Command.make("sheet.add", {}, "x")).ok)
	assert_null(channel.get_document())
