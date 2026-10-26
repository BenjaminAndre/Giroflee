extends GutTest


func test_ids_are_uuid_v4_shaped() -> void:
	var gen: IdGenerator = IdGenerator.new(7)
	var regex: RegEx = RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	for i: int in 20:
		var id: String = gen.next_uuid()
		assert_not_null(regex.search(id), id)


func test_same_seed_gives_the_same_sequence() -> void:
	var a: IdGenerator = IdGenerator.new(42)
	var b: IdGenerator = IdGenerator.new(42)
	for i: int in 10:
		assert_eq(a.next_uuid(), b.next_uuid())


func test_ids_do_not_repeat() -> void:
	var gen: IdGenerator = IdGenerator.new(1)
	var seen: Dictionary = {}
	for i: int in 500:
		var id: String = gen.next_uuid()
		assert_false(seen.has(id))
		seen[id] = true


func test_unseeded_generators_differ() -> void:
	assert_ne(IdGenerator.new().next_uuid(), IdGenerator.new().next_uuid())
