extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Property tests on the command architecture (SRD ARCH-3, ARCH-5), driven by seeded random
## command sequences. The same seeds always produce the same sequences, so failures replay.

const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const STEPS: int = 80


## Performs one random command through `s`. Returns true when it was accepted.
func _random_step(s: Session, rng: RandomNumberGenerator) -> bool:
	var doc: Document = s.document()
	var choice: int = rng.randi_range(0, 12)
	if doc.sheet_order.is_empty() or choice == 0:
		var name: String = "S%d" % rng.randi_range(0, 99)
		return s.run_one("sheet.add", {"id": s.ids.next_uuid(), "kind": "plan", "props": {"name": name}}).ok
	var sheet_id: String = doc.sheet_order[rng.randi_range(0, doc.sheet_order.size() - 1)]
	var sheet: Sheet = doc.get_sheet(sheet_id)
	var entity_ids: Array[String] = sheet.sorted_entity_ids()
	var picked: Array[String] = []
	for id: String in entity_ids:
		if rng.randf() < 0.4:
			picked.append(id)
	match choice:
		1, 2:
			var x: int = rng.randi_range(-5000, 5000)
			var y: int = rng.randi_range(-5000, 5000)
			var wall: Dictionary = {"points": [[x, y], [x + rng.randi_range(100, 4000), y], [x, y + 500]]}
			return TestKit.add_entity(s, sheet_id, s.ids.next_uuid(), "wall", wall).ok
		3, 4:
			var circuit: String = char(65 + rng.randi_range(0, 5))
			return TestKit.add_symbol(s, sheet_id, s.ids.next_uuid(), [rng.randi_range(0, 9000), rng.randi_range(0, 9000)], circuit, rng.randi_range(1, 8), "socket").ok
		5:
			var block: Dictionary = {"pos": [rng.randi_range(0, 900), 0], "size": [rng.randi_range(1, 900), rng.randi_range(1, 900)]}
			return TestKit.add_entity(s, sheet_id, s.ids.next_uuid(), "grey_block", block).ok
		6, 7:
			if picked.is_empty():
				return false
			return s.run_one("entity.move", {"sheet": sheet_id, "ids": picked, "delta": [rng.randi_range(-300, 300), rng.randi_range(-300, 300)]}).ok
		8:
			var updates: Array = []
			for id: String in picked:
				var entity: Entity = sheet.entities[id]
				if entity.type == "symbol":
					updates.append({"id": id, "props": {"count": rng.randi_range(1, 4), "circuit": char(65 + rng.randi_range(0, 5))}})
			if updates.is_empty():
				return false
			return s.run_one("entity.update", {"sheet": sheet_id, "items": updates}).ok
		9:
			if picked.is_empty():
				return false
			return s.run_one("entity.remove", {"sheet": sheet_id, "ids": picked}).ok
		10:
			return s.run_one("doc.set", {"section": "config", "key": "font_size_pt", "value": rng.randi_range(6, 20)}).ok
		11:
			if doc.sheet_order.size() < 2:
				return false
			return s.run_one("sheet.remove", {"id": sheet_id}).ok
		12:
			var others: Array[String] = []
			for other: String in doc.sheet_order:
				if other != sheet_id:
					others.append(other)
			var ghosts: Array = []
			if not others.is_empty():
				ghosts.append(others[rng.randi_range(0, others.size() - 1)])
			return s.run_one("sheet.update", {"id": sheet_id, "props": {"ghost_on": not ghosts.is_empty(), "ghost_sheets": ghosts, "name": "R%d" % rng.randi_range(0, 9)}}).ok
	return false


## Runs a whole random session; returns the project JSON after every accepted step.
func _play(seed_value: int) -> Dictionary:
	var s: Session = TestKit.session(seed_value)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var states: Array[String] = [TestKit.json(s.document())]
	for step: int in STEPS:
		var before_depth: int = s.history.undo_depth()
		if _random_step(s, rng):
			# a no-op command (empty patch) is accepted but not recorded; skip it
			if s.history.undo_depth() == before_depth + 1:
				states.append(TestKit.json(s.document()))
		assert_eq(s.document().check_integrity(), "", "integrity after step %d (seed %d)" % [step, seed_value])
	return {"session": s, "states": states}


func test_undo_walks_back_through_every_state_and_redo_forward_again() -> void:
	for seed_value: int in SEEDS:
		var played: Dictionary = _play(seed_value)
		var s: Session = played["session"]
		var states: Array = played["states"]
		assert_true(states.size() > 15, "seed %d produced a meaningful sequence (%d states)" % [seed_value, states.size()])
		for i: int in range(states.size() - 1, 0, -1):
			assert_true(s.undo(), "undo %d (seed %d): %s" % [i, seed_value, s.last_error])
			assert_eq(TestKit.json(s.document()), states[i - 1], "state after undoing step %d (seed %d)" % [i, seed_value])
		assert_false(s.can_undo())
		for i: int in range(1, states.size()):
			assert_true(s.redo(), "redo %d (seed %d): %s" % [i, seed_value, s.last_error])
			assert_eq(TestKit.json(s.document()), states[i], "state after redoing step %d (seed %d)" % [i, seed_value])
		assert_false(s.can_redo())


func test_same_seed_gives_identical_projects() -> void:
	for seed_value: int in SEEDS:
		var a: Array = _play(seed_value)["states"]
		var b: Array = _play(seed_value)["states"]
		assert_eq(a, b, "determinism for seed %d" % seed_value)


func test_every_state_survives_a_save_load_round_trip() -> void:
	for seed_value: int in SEEDS:
		var states: Array = _play(seed_value)["states"]
		for state: Variant in states:
			var text: String = state
			var loaded: DocumentIO.LoadResult = DocumentIO.from_json(text)
			assert_eq(loaded.error, "", "seed %d" % seed_value)
			assert_eq(DocumentIO.to_json(loaded.document), text, "byte-identical after reload (seed %d)" % seed_value)


func test_a_reloaded_document_behaves_like_the_original() -> void:
	# Replaying the second half of a session on a reloaded copy must give the same result.
	var seed_value: int = 3
	var s: Session = TestKit.session(seed_value)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in 40:
		_random_step(s, rng)
	var snapshot: String = TestKit.json(s.document())
	var reloaded: Document = DocumentIO.from_json(snapshot).document
	var s2: Session = Session.new(InProcessChannel.new(reloaded), IdGenerator.new(999))

	# same random stream continues on both sessions; ids differ, so use id-free comparison:
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 12345
	for i: int in 30:
		var ok_a: bool = _random_step(s, rng_a)
		var ok_b: bool = _random_step(s2, rng_b)
		assert_eq(ok_a, ok_b, "a command accepted by one must be accepted by the other (step %d)" % i)
	assert_eq(s.document().sheet_order.size(), s2.document().sheet_order.size())
	assert_eq(s2.document().check_integrity(), "")
