extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The author's workflow for the electrical plan, replayed with real input events (SRD TEST-3, section
## 6.2): draw a room, place a lamp, Alt-place its switch, start a new circuit, place sockets against the
## wall, a triple socket, then edit and undo.

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _room() -> void:
	h.key("W")
	for p: Vector2 in [Vector2(3000, 3000), Vector2(11000, 3000), Vector2(11000, 9000), Vector2(3000, 9000), Vector2(3000, 3000)]:
		h.click(p)
	h.key("Escape")
	h.key("Escape")


func _symbols() -> Dictionary:
	var out: Dictionary = {}
	var sheet: Sheet = h.model().sheet()
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "symbol":
			var pos: Array = entity.props["pos"]
			out["%d,%d" % [pos[0], pos[1]]] = entity
	return out


func test_a_room_with_a_lamp_its_switch_and_sockets() -> void:
	_room()
	h.key("L")
	h.click(Vector2(7000, 6000))
	h.key("I")
	h.click(Vector2(4000, 6000), false, ["alt"])
	h.key("L")
	h.click(Vector2(9000, 6000))
	h.key("C")
	h.key("H")
	h.key("P")
	h.click(Vector2(5000, 3250))
	h.key("X")
	h.key("3")
	h.click(Vector2(9000, 3250))
	await h.play(self)

	var model: EditorModel = h.model()
	var symbols: Dictionary = _symbols()
	assert_eq(symbols.size(), 5)
	var lamp1: Entity = symbols["7000,6000"]
	var switch1: Entity = symbols["4000,6000"]
	var lamp2: Entity = symbols["9000,6000"]
	assert_eq([lamp1.props["circuit"], lamp1.props["index"]], ["A", 1])
	assert_eq([switch1.props["circuit"], switch1.props["index"]], ["A", 1], "Alt: the switch is the lamp's point")
	assert_eq([lamp2.props["circuit"], lamp2.props["index"]], ["A", 2], "a new point without Alt")
	assert_eq(Numbering.point_count(model.doc(), "A"), 2, "lamp + switch count once")

	var sockets: Array[Entity] = []
	for entity: Entity in symbols.values():
		if entity.props["symbol_type"] == "socket":
			sockets.append(entity)
	assert_eq(sockets.size(), 2)
	sockets.sort_custom(func(a: Entity, b: Entity) -> bool: return int(a.props["pos"][0]) < int(b.props["pos"][0]))
	assert_eq([sockets[0].props["circuit"], sockets[0].props["index"], sockets[0].props["count"]], ["H", 1, 1])
	assert_eq([sockets[1].props["circuit"], sockets[1].props["index"], sockets[1].props["count"]], ["H", 2, 3], "triple socket")
	for socket: Entity in sockets:
		assert_eq(socket.props["rotation"], 0.0, "facing into the room, away from the south wall")
		assert_eq(socket.props["pos"][1], 3145, "its back against the drawn edge of the wall")
	assert_eq(Numbering.point_count(model.doc(), "H"), 2, "a triple socket is one point")
	assert_eq(model.doc().check_integrity(), "")

	# undo removes the last placement only
	model.undo()
	assert_eq(_symbols().size(), 4)


func test_selecting_symbols_and_changing_their_circuit_with_the_keyboard() -> void:
	_room()
	h.key("L")
	h.click(Vector2(5000, 6000))
	h.click(Vector2(7000, 6000))
	h.key("Escape")
	h.key("Escape")
	h.drag(Vector2(4000, 5000), Vector2(8000, 7000))
	h.key("C")
	h.key("K")
	await h.play(self)
	for entity: Entity in _symbols().values():
		assert_eq(entity.props["circuit"], "K")
	assert_eq(Numbering.circuits_in_use(h.model().doc()), ["K"])
	assert_eq(h.model().active_circuit, "A", "the active circuit is untouched when a selection was changed")


func test_pipette_then_alt_links_a_new_symbol_to_an_existing_point() -> void:
	_room()
	h.key("L")
	h.click(Vector2(6000, 6000))
	h.key("Escape")
	h.key("Escape")
	h.move(Vector2(6000, 6000))
	h.key("A")
	h.key("I")
	h.click(Vector2(4000, 6000), false, ["alt"])
	await h.play(self)
	var symbols: Dictionary = _symbols()
	var switch: Entity = symbols["4000,6000"]
	var lamp: Entity = symbols["6000,6000"]
	assert_eq(switch.props["index"], lamp.props["index"])
	assert_eq(switch.props["circuit"], lamp.props["circuit"])
