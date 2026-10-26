extends GutTest
@warning_ignore_start("unsafe_call_argument")
## M3 in the real window: symbol tools in the tool bar, the circuit panel with focus, the quickbar strip,
## the status bar, replayed with real input events (SRD TEST-3).

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _symbols() -> Array[Entity]:
	var out: Array[Entity] = []
	var sheet: Sheet = h.model().sheet()
	for entity_id: String in sheet.sorted_entity_ids():
		var entity: Entity = sheet.entities[entity_id]
		if entity.type == "symbol":
			out.append(entity)
	return out


func test_the_tool_bar_has_the_symbol_tools_with_their_keys_in_the_tooltips() -> void:
	var expected: Dictionary = {"lamp": "L", "switch": "I", "switch_two_way": "Maj+I", "socket": "P"}
	for tool_id: String in expected.keys():
		var button: Button = h.window.toolbar.button_for(tool_id)
		assert_not_null(button, tool_id)
		assert_string_contains(button.tooltip_text, str(expected[tool_id]))
		assert_not_null(button.icon, "%s has an icon" % tool_id)
		assert_eq(button.text, "", "icon only")


func test_pressing_l_presses_the_lamp_button_and_clicks_place_lamps() -> void:
	h.key("L")
	h.click(Vector2(5000, 5000))
	h.click(Vector2(7000, 5000))
	await h.play(self)
	assert_true(h.window.toolbar.button_for("lamp").button_pressed)
	assert_eq(_symbols().size(), 2)


func test_the_circuit_panel_lists_circuits_in_use_with_their_point_counts() -> void:
	h.model().add_entities([
		{"id": "a1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [1000, 1000], "circuit": "A", "index": 1}},
		{"id": "a2", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [2000, 1000], "circuit": "A", "index": 2}},
		{"id": "b1", "type": "symbol", "props": {"symbol_type": "socket", "pos": [3000, 1000], "circuit": "B", "index": 1}},
	])
	await get_tree().process_frame
	var panel: CircuitPanel = h.window.circuits
	assert_not_null(panel.row_for("A"))
	assert_not_null(panel.row_for("B"))
	assert_null(panel.row_for("C"))
	var found: String = ""
	for label: Node in panel.row_for("A").find_children("*", "Label", true, false):
		found += (label as Label).text + "|"
	assert_string_contains(found, "2 points")


func test_clicking_a_circuit_greys_it_out_and_double_clicking_isolates_it() -> void:
	h.model().add_entities([
		{"id": "a1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [1000, 1000], "circuit": "A", "index": 1}},
		{"id": "b1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [3000, 1000], "circuit": "B", "index": 1}},
		{"id": "c1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [5000, 1000], "circuit": "C", "index": 1}},
	])
	await get_tree().process_frame
	var panel: CircuitPanel = h.window.circuits
	panel.click_circuit("A", false)
	assert_true(h.model().focus.is_dimmed("A"))
	panel.click_circuit("A", false)
	assert_false(h.model().focus.is_dimmed("A"))
	# double-click = two presses: the first toggles, the second is flagged as the double
	panel.click_circuit("B", false)
	panel.click_circuit("B", true)
	assert_eq(h.model().focus.dimmed_letters(), ["A", "C"], "only B stays visible")
	panel.click_circuit("B", false)
	panel.click_circuit("B", true)
	assert_eq(h.model().focus.dimmed_letters(), [], "back to what it was before the solo")


func test_a_greyed_circuit_is_drawn_grey_and_cannot_be_clicked() -> void:
	h.model().add_entities([{"id": "a1", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [5000, 5000], "circuit": "A", "index": 1}}])
	h.window.circuits.click_circuit("A", false)
	h.click(Vector2(5000, 5000))
	await h.play(self)
	assert_eq(h.model().selection, [], "greyed symbols are not picked")


func test_the_status_bar_shows_the_active_circuit_and_the_pending_key() -> void:
	h.key("C")
	await h.play(self)
	assert_string_contains(h.window.status_hint.text, "lettre")
	h.key("H")
	await h.play(self)
	assert_eq(h.model().active_circuit, "H")
	assert_string_contains(h.window.status_info.text, "circuit H")


func test_the_quickbar_strip_shows_the_stored_tools_and_a_click_uses_one() -> void:
	var strip: QuickbarView = h.window.quickbar_view
	assert_eq(strip.button_for(1).icon, null, "empty slot")
	h.model().set_tool("socket")
	h.model().store_quickbar(1)
	h.model().set_tool("select")
	assert_not_null(strip.button_for(1).icon, "the socket icon")
	strip.button_for(1).pressed.emit()
	assert_eq(h.model().tool_name, "socket")
	assert_true(strip.button_for(1).button_pressed, "the slot of the active tool is lit")


func test_the_symbols_menu_and_palette_expose_the_commands() -> void:
	var menu: PopupMenu = h.window.menu("Symboles")
	assert_not_null(menu)
	var labels: PackedStringArray = PackedStringArray()
	for i: int in menu.item_count:
		labels.append(menu.get_item_text(i))
	for wanted: String in ["Replacer les étiquettes", "Compacter la numérotation", "Ancrer à un symbole", "Détacher"]:
		var present: bool = false
		for label: String in labels:
			present = present or label.begins_with(wanted)
		assert_true(present, wanted)


func test_selecting_a_symbol_shows_its_circuit_properties_not_its_type_field() -> void:
	h.model().add_entities([{"id": "a1", "type": "symbol", "props": {"symbol_type": "socket", "pos": [1000, 1000], "circuit": "A", "index": 1}}])
	h.model().set_selection(["a1"])
	await get_tree().process_frame
	var texts: String = ""
	for label: Node in h.window.panel.find_children("*", "Label", true, false):
		texts += (label as Label).text + "|"
	assert_string_contains(texts, "Prise")
	assert_string_contains(texts, "Circuit")
	assert_string_contains(texts, "Nombre")
	assert_false(texts.contains("Symbole|"), "the pack type is not editable")
