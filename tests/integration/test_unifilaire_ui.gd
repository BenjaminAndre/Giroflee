extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The unifilaire and its board editor in the real window (SRD FR-TAB, FR-UNI-7, FR-CART).

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)
	h.model().add_entities([
		{"id": "a1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [2000, 2000], "circuit": "A", "index": 1}},
		{"id": "a2", "type": "symbol", "props": {"symbol_type": "socket", "pos": [3000, 2000], "circuit": "A", "index": 2}},
		{"id": "b1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [4000, 2000], "circuit": "B", "index": 1}},
	])


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _show() -> UnifilaireLayout:
	h.window.uni_button.pressed.emit()
	await get_tree().process_frame
	return UnifilaireLayout.compute(h.model().doc(), h.model().sheet(), UnifilaireBuilder.derive(h.model().doc()))


func _page_to_world(x: float, y: float) -> Vector2:
	return FrameBuilder.page_to_world(h.model().sheet(), x, y)


func _labels() -> Array[String]:
	var out: Array[String] = []
	for node: Node in h.window.panel.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


func _buttons() -> Array[String]:
	var out: Array[String] = []
	for node: Node in h.window.panel.find_children("*", "Button", true, false):
		out.append((node as Button).text)
	return out


func _edit(node_name: String) -> LineEdit:
	return h.window.panel.find_child(node_name, true, false) as LineEdit


func test_the_panel_of_the_unifilaire_has_the_board_sections() -> void:
	await _show()
	var labels: Array[String] = _labels()
	for wanted: String in ["Unifilaire", "Barre", "Tête de ligne", "Cartouche"]:
		assert_true(labels.has(wanted), wanted)
	var buttons: Array[String] = _buttons()
	assert_true(buttons.has("Ajouter un circuit de réserve"))
	assert_true(buttons.has("Insérer la tête habituelle"))


func test_drawing_tools_are_greyed_out_on_the_unifilaire_and_back_on_a_plan() -> void:
	await _show()
	assert_true(h.window.toolbar.button_for("wall").disabled)
	assert_true(h.window.toolbar.button_for("lamp").disabled)
	assert_false(h.window.toolbar.button_for("select").disabled)
	h.window.tabs.current_tab = 0
	assert_false(h.window.toolbar.button_for("wall").disabled)


func test_clicking_a_column_with_the_mouse_shows_its_settings() -> void:
	var layout: UnifilaireLayout = await _show()
	var region: UnifilaireLayout.Region = layout.region_of("column", "B")
	h.click(_page_to_world(region.rect.get_center().x, layout.y_bus - 12.0))
	await h.play(self)
	assert_eq(h.model().uni_selection["letter"], "B")
	assert_not_null(_edit("circuit_title"))
	assert_true(_labels().has("Circuit B"))


func test_typing_a_circuit_title_and_choosing_its_breaker() -> void:
	await _show()
	h.model().select_uni({"kind": "column", "letter": "A"})
	await get_tree().process_frame
	var title: LineEdit = _edit("circuit_title")
	title.text = "Salon / Cuisine"
	title.text_submitted.emit(title.text)
	assert_eq(h.model().doc().circuits["A"]["title"], "Salon / Cuisine")
	var texts: Array[String] = []
	for op: DrawOp in h.model().page_list().ops:
		if op.kind == DrawOp.TEXT:
			texts.append(op.text)
	assert_true(texts.has("Salon / Cuisine"), "the page shows it")
	var picker: OptionButton = h.window.panel.find_child("circuit_breaker", true, false) as OptionButton
	assert_not_null(picker)
	picker.item_selected.emit(2)
	assert_eq(h.model().doc().circuits["A"]["breaker"], "breaker_c40_3ka")
	h.model().undo()
	h.model().undo()
	assert_false(h.model().doc().circuits.has("A"), "both edits undone")


func test_inserting_the_usual_head_and_adding_a_bus_device_from_the_panel() -> void:
	await _show()
	for node: Node in h.window.panel.find_children("*", "Button", true, false):
		var button: Button = node
		if button.text == "Insérer la tête habituelle":
			button.pressed.emit()
	assert_eq(h.model().head_items().size(), 5)
	await get_tree().process_frame
	assert_false(_buttons().has("Insérer la tête habituelle"), "the panel was rebuilt with the head listed")
	var add: Button = h.window.panel.find_child("bus_device_add", true, false) as Button
	add.pressed.emit()
	assert_eq(h.model().materialized_bus().size(), 3, "A, B and the device")
	await get_tree().process_frame
	assert_true(_labels().has("Appareil de la barre"), "the new device is selected")


func test_a_spare_circuit_can_be_added_and_removed_from_the_panel() -> void:
	await _show()
	for node: Node in h.window.panel.find_children("*", "Button", true, false):
		var button: Button = node
		if button.text == "Ajouter un circuit de réserve":
			button.pressed.emit()
	assert_eq(h.model().uni_selection["letter"], "C")
	await get_tree().process_frame
	var remove: Button = null
	for node: Node in h.window.panel.find_children("*", "Button", true, false):
		var button: Button = node
		if button.text == "Retirer ce circuit de réserve":
			remove = button
	assert_not_null(remove)
	remove.pressed.emit()
	assert_eq(h.model().materialized_bus().size(), 2)


func test_the_cartouche_is_edited_from_the_plan_and_from_the_unifilaire() -> void:
	h.model().clear_selection()
	await get_tree().process_frame
	var owner: LineEdit = _edit("cartouche_owner")
	assert_not_null(owner, "listed in the panel when nothing is selected on a plan")
	owner.text = "Jeanne Exemple"
	owner.text_submitted.emit(owner.text)
	assert_eq(h.model().doc().cartouche["owner"], "Jeanne Exemple")
	await _show()
	assert_eq(_edit("cartouche_owner").text, "Jeanne Exemple", "the same project field")
	var address: LineEdit = _edit("cartouche_address")
	address.text = "Rue de l'Exemple 1"
	address.focus_exited.emit()
	assert_eq(h.model().doc().cartouche["address"], "Rue de l'Exemple 1", "leaving the field commits it")


func test_clicking_a_point_jumps_to_the_symbol_on_its_plan_and_selects_it() -> void:
	var layout: UnifilaireLayout = await _show()
	var region: UnifilaireLayout.Region = layout.region_of("point", "A", 2)
	h.click(_page_to_world(region.rect.get_center().x, region.rect.get_center().y))
	await h.play(self)
	assert_eq(h.model().sheet().kind, "plan")
	assert_eq(h.model().selection, ["a2"])
	assert_false(h.window.uni_button.button_pressed)


func test_dragging_a_column_through_real_events_reorders_the_bus() -> void:
	var layout: UnifilaireLayout = await _show()
	var from: UnifilaireLayout.Region = layout.region_of("column", "A")
	var y: float = layout.y_bus - 12.0
	h.drag(_page_to_world(from.rect.get_center().x, y), _page_to_world(layout.slot_x[1] + layout.slot_w[1] * 0.8, y))
	await h.play(self)
	var letters: Array[String] = []
	for raw: Variant in h.model().materialized_bus():
		var entry: Dictionary = raw
		letters.append(str(entry["letter"]))
	assert_eq(letters, ["B", "A"])
