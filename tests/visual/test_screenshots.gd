extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Opt-in visual check: drives the real window and saves what it renders as PNG files in
## user://screenshots/. Needs a display, so it is not part of the default (headless) suite:
##   godot --path . -s addons/gut/gut_cmdln.gd -gexit -gdir=res://tests/visual

const OUT_DIR: String = "user://screenshots"

var h: UiHarness


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	h = await UiHarness.create(self)


func _shot(name: String) -> void:
	for i: int in 3:
		await get_tree().process_frame
	var image: Image = h.window.get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	image.save_png(path)
	gut.p("screenshot: %s" % ProjectSettings.globalize_path(path))


func _room() -> void:
	h.key("W")
	h.click(Vector2(3000, 3000))
	h.click(Vector2(11000, 3000))
	h.click(Vector2(11000, 9000))
	h.click(Vector2(3000, 9000))
	h.click(Vector2(3000, 3000))
	h.key("D")
	h.click(Vector2(6000, 3100))
	h.key("F")
	h.click(Vector2(11100, 6000))
	h.key("E")
	h.click(Vector2(8000, 6000))
	h.key("S")
	h.drag(Vector2(4000, 7000), Vector2(6000, 8200))
	h.key("Escape")
	h.key("Escape")


func test_screenshot_room() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	await h.play(self)
	h.model().add_text(Vector2(5000, 5000), "Salon", "room")
	await _shot("room")
	assert_true(true)


func test_screenshot_selection_handles() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	await h.play(self)
	h.click(Vector2(7000, 3000))
	await h.play(self)
	await _shot("selected_wall")
	assert_true(true)


func test_screenshot_placement_preview_and_palette() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	h.key("D")
	h.move(Vector2(9000, 3100))
	await h.play(self)
	await _shot("door_preview")
	h.key("Escape")
	h.key("P", ["ctrl"])
	await h.play(self)
	h.window.palette._field.text = "etage"
	h.window.palette._field.text_changed.emit("etage")
	await _shot("palette")
	assert_true(true)


func test_screenshot_ghost_view() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	await h.play(self)
	h.model().duplicate_sheet(false)
	h.model().toggle_ghost()
	h.model().set_active_sheet(h.model().doc().sheet_order[1])
	await _shot("ghost")
	assert_true(true)


func test_screenshot_transform_handles_and_wall_preview() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	await h.play(self)
	h.model().set_selection(h.model().sheet().sorted_entity_ids().filter(func(id: String) -> bool: return h.model().sheet().entities[id].type in ["grey_block", "stair"]))
	await _shot("transform_handles")
	h.model().clear_selection()
	h.key("W")
	h.click(Vector2(13000, 3000))
	h.click(Vector2(16000, 3000))
	h.move(Vector2(16000, 6500))
	await h.play(self)
	await _shot("wall_preview")
	assert_true(true)


func test_screenshot_electrical_plan() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	_room()
	h.key("L")
	h.click(Vector2(5000, 6000))
	h.key("I")
	h.click(Vector2(3400, 6000), false, ["alt"])
	h.key("L")
	h.click(Vector2(8000, 6000))
	h.key("I", ["shift"])
	h.click(Vector2(5000, 3400), false, ["alt"])
	h.key("C")
	h.key("H")
	h.key("P")
	h.click(Vector2(4000, 3250))
	h.click(Vector2(6000, 3250))
	h.key("X")
	h.key("3")
	h.click(Vector2(10000, 3250))
	h.key("Escape")
	h.key("Escape")
	await h.play(self)
	h.model().add_text(Vector2(7000, 4600), "Salon", "room")
	h.model().clear_selection()
	h.model().view().fit_rect(Rect2(2500, 2500, 9000, 4200))
	await _shot("electrical_plan")
	h.window.circuits.click_circuit("A", false)
	await _shot("electrical_plan_focus")
	assert_true(true)


func test_screenshot_unifilaire() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	var model: EditorModel = h.model()
	model.add_text(Vector2(5000, 5000), "Salon", "room")
	model.add_text(Vector2(9000, 5000), "Cuisine", "room")
	var circuits: Array = [["A", 5200, 5200], ["B", 9200, 5200], ["C", 5000, 4000]]
	for entry: Array in circuits:
		var letter: String = entry[0]
		var x: int = entry[1]
		var y: int = entry[2]
		for i: int in 3:
			model.add_entities([{"id": "%s-l%d" % [letter, i], "type": "symbol", "props": {"symbol_type": "lamp", "pos": [x + i * 400, y], "circuit": letter, "index": i + 1}}])
		model.add_entities([{"id": "%s-sw" % letter, "type": "symbol", "props": {"symbol_type": "switch", "pos": [x - 600, y], "circuit": letter, "index": 1}}])
		model.add_entities([{"id": "%s-so" % letter, "type": "symbol", "props": {"symbol_type": "socket", "pos": [x, y + 600], "circuit": letter, "index": 4, "count": 3}}])
	model.add_entities([{"id": "C-open", "type": "symbol", "props": {"symbol_type": "switch", "pos": [4000, 4000], "circuit": "C", "index": 5}}])
	var catalog: Catalog = Catalog.for_pack("belgium")
	var head: Array = []
	for item_id: String in catalog.usual_head:
		head.append({"id": "h-%s" % item_id, "catalog": item_id})
	model.session.run_one("doc.set", {"section": "board", "key": "head", "value": head})
	model.session.run_one("doc.set", {"section": "board", "key": "bus", "value": [
		{"type": "circuit", "letter": "C"}, {"type": "device", "id": "d1", "catalog": "diff_40a_30ma_a"},
		{"type": "circuit", "letter": "A"}, {"type": "circuit", "letter": "B"}, {"type": "circuit", "letter": "F"}]})
	model.set_cartouche_field("address", "Rue de l'Exemple 1, 5000 Namur")
	model.set_cartouche_field("owner", "Jeanne Exemple")
	model.set_circuit_field("A", "title", "Salon / Cuisine")
	model.show_unifilaire()
	model.select_uni({"kind": "column", "letter": "A"})
	h.model().view().fit_rect(Rect2(0, 0, 420, 297))
	await _shot("unifilaire")
	assert_true(true)
