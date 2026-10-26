extends GutTest
@warning_ignore_start("unsafe_call_argument")
## TEST-3: the real EditorWindow driven by replayed input (keys, mouse, wheel).

var h: UiHarness


func before_each() -> void:
	h = await UiHarness.create(self)


func after_each() -> void:
	ProjectFiles.clear_autosave(98)


func _walls() -> Array[Entity]:
	var out: Array[Entity] = []
	for id: String in h.model().sheet().sorted_entity_ids():
		var entity: Entity = h.model().sheet().entities[id]
		if entity.type == "wall":
			out.append(entity)
	return out


func test_the_window_starts_with_one_tab_and_a_fitted_page() -> void:
	assert_eq(h.window.tabs.tab_count, 1)
	assert_eq(h.window.tabs.get_tab_title(0), "Rez")
	assert_true(h.window.canvas.size.x > 800.0, "the canvas has its real size")
	var visible: Rect2 = h.model().view().visible_world_rect()
	assert_true(visible.encloses(FrameBuilder.page_rect(h.model().sheet())), "page fitted in the real canvas")
	assert_string_contains(h.window.status_hint.text, "Sélection")


func test_drawing_a_room_with_the_mouse_and_keyboard() -> void:
	h.key("W")
	h.click(Vector2(3000, 3000))
	h.click(Vector2(9000, 3000))
	h.click(Vector2(9000, 8000))
	h.click(Vector2(3000, 8000))
	h.click(Vector2(3000, 3000))
	await h.play(self)
	var walls: Array[Entity] = _walls()
	assert_eq(walls.size(), 1, "clicking the first point closed the loop")
	var points: Array = walls[0].props["points"]
	assert_eq(points.size(), 5)
	assert_eq(h.window.status_hint.text.begins_with("Mur"), true, "status bar shows the tool hint")


func test_wall_door_window_stair_and_undo_through_real_input() -> void:
	h.key("W")
	h.click(Vector2(3000, 3000))
	h.click(Vector2(9000, 3000), true)
	h.key("D")
	h.click(Vector2(6000, 3200))
	h.key("F")
	h.click(Vector2(4000, 2800))
	h.key("E")
	h.click(Vector2(11000, 5000))
	await h.play(self)
	assert_eq(h.model().sheet().entities.size(), 4)
	var door: Entity = null
	for id: String in h.model().sheet().sorted_entity_ids():
		var entity: Entity = h.model().sheet().entities[id]
		if entity.type == "opening" and entity.props["kind"] == "door":
			door = entity
	assert_not_null(door)
	assert_ne(door.props["host_wall"], "", "the door attached to the wall")
	for i: int in 4:
		h.key("Z", ["ctrl"])
	await h.play(self)
	assert_eq(h.model().sheet().entities.size(), 0, "four undo steps remove everything")
	for i: int in 4:
		h.key("Y", ["ctrl"])
	await h.play(self)
	assert_eq(h.model().sheet().entities.size(), 4)


func test_select_move_and_delete_with_the_mouse() -> void:
	h.model().add_entities([{"id": "blk", "type": "grey_block", "props": {"pos": [4000, 4000], "size": [2000, 1000]}}])
	h.click(Vector2(5000, 4500))
	h.drag(Vector2(5000, 4500), Vector2(7000, 6500))
	await h.play(self)
	assert_eq(h.model().sheet().entities["blk"].props["pos"], [6000, 6000])
	h.key("Delete")
	await h.play(self)
	assert_false(h.model().sheet().entities.has("blk"))


func test_ctrl_wheel_zooms_and_wheel_pans_the_view() -> void:
	var before: float = h.model().view().zoom
	var p: Vector2 = h.at(Vector2(10000, 7000))
	h.events.append({"frame": 0, "type": "wheel", "direction": "up", "pos": [p.x, p.y], "mods": ["ctrl"]})
	await h.play(self)
	assert_true(h.model().view().zoom > before)
	var centre: Vector2 = h.model().view().center
	h.events.append({"frame": 0, "type": "wheel", "direction": "down", "pos": [p.x, p.y]})
	await h.play(self)
	assert_ne(h.model().view().center, centre)


func test_ctrl_t_adds_a_tab_and_ctrl_tab_switches() -> void:
	h.key("T", ["ctrl"])
	await h.play(self)
	assert_eq(h.window.tabs.tab_count, 2)
	assert_eq(h.window.tabs.current_tab, 1)
	h.key("Tab", ["ctrl"])
	await h.play(self)
	assert_eq(h.window.tabs.current_tab, 0)
	assert_eq(h.model().active_sheet_id, h.model().doc().sheet_order[0])


func test_clicking_a_tab_switches_the_etage() -> void:
	h.model().new_sheet()
	h.window.tabs.current_tab = 0
	assert_eq(h.model().active_sheet_id, h.model().doc().sheet_order[0])


func test_the_plus_button_creates_an_etage() -> void:
	h.window._add_button.pressed.emit()
	assert_eq(h.window.tabs.tab_count, 2)


func test_palette_opens_filters_and_runs_a_command() -> void:
	h.model().add_entities([{"id": "w", "type": "wall", "props": {"points": [[0, 0], [4000, 0]]}}])
	h.key("P", ["ctrl"])
	await h.play(self)
	assert_true(h.window.palette.visible)
	h.window.palette._field.text = "dupl etage"
	h.window.palette._field.text_changed.emit("dupl etage")
	h.key("Enter")
	await h.play(self)
	assert_eq(h.model().doc().sheet_order.size(), 2, "'Dupliquer l'étage' ran")
	assert_false(h.window.palette.visible)
	assert_eq(h.model().sheet().entities.size(), 1, "the wall was copied")


func test_palette_escape_closes_it_without_running_anything() -> void:
	h.key("P", ["ctrl"])
	await h.play(self)
	h.key("Escape")
	await h.play(self)
	assert_false(h.window.palette.visible)
	assert_eq(h.model().doc().sheet_order.size(), 1)


func test_tool_keys_do_not_leak_into_the_palette_search() -> void:
	h.key("P", ["ctrl"])
	await h.play(self)
	h.key("W")
	await h.play(self)
	assert_eq(h.model().tool_name, "select", "the palette owns the keyboard while it is open")


func test_text_tool_opens_the_inline_editor_and_creates_the_label() -> void:
	h.key("T")
	h.click(Vector2(5000, 5000))
	await h.play(self)
	assert_true(h.window._inline.visible)
	h.window._inline.text = "Salle à manger"
	h.window._inline.text_submitted.emit("Salle à manger")
	assert_false(h.window._inline.visible)
	var labels: Array[String] = []
	for id: String in h.model().sheet().sorted_entity_ids():
		var entity: Entity = h.model().sheet().entities[id]
		if entity.type == "text":
			labels.append(entity.props["text"])
	assert_eq(labels, ["Salle à manger"])


func test_inline_editor_escape_cancels() -> void:
	h.key("T")
	h.click(Vector2(5000, 5000))
	await h.play(self)
	h.window._inline.text = "oublié"
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	h.window._on_inline_input(escape)
	assert_false(h.window._inline.visible)
	assert_eq(h.model().sheet().entities.size(), 0)


func test_f2_renames_the_etage_in_place() -> void:
	h.key("F2")
	await h.play(self)
	assert_true(h.window._inline.visible)
	h.window._inline.text = "+1"
	h.window._inline.text_submitted.emit("+1")
	assert_eq(h.window.tabs.get_tab_title(0), "+1", "the tab shows the new name")
	assert_eq(h.model().sheet().display_name(), "+1")


# --- properties panel ------------------------------------------------------------------------


func _first_of(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child: Node in node.get_children():
		var found: Node = _first_of(child, type_name)
		if found != null:
			return found
	return null


func _all_of(node: Node, type_name: String, out: Array[Node]) -> void:
	if node.get_class() == type_name:
		out.append(node)
	for child: Node in node.get_children():
		_all_of(child, type_name, out)


func test_panel_shows_etage_and_project_settings_when_nothing_is_selected() -> void:
	var labels: Array[Node] = []
	_all_of(h.window.panel, "Label", labels)
	var texts: Array[String] = []
	for node: Node in labels:
		texts.append((node as Label).text)
	assert_true(texts.has("Étage") and texts.has("Projet"))
	assert_true(texts.has("Nom de l'étage"))
	assert_true(texts.has("Épaisseur des murs (mm page)"))


func test_editing_a_panel_field_is_one_undoable_command() -> void:
	var spins: Array[Node] = []
	_all_of(h.window.panel, "SpinBox", spins)
	var scale_spin: SpinBox = null
	for node: Node in spins:
		if (node as SpinBox).value == 50.0:
			scale_spin = node as SpinBox
	assert_not_null(scale_spin, "found the scale field")
	h.model().session.history.clear()
	scale_spin.value = 100.0
	assert_eq(h.model().sheet().props["scale_den"], 100)
	assert_eq(h.model().session.history.undo_depth(), 1)
	h.model().undo()
	assert_eq(h.model().sheet().props["scale_den"], 50)


func test_selecting_an_entity_shows_its_own_properties() -> void:
	h.model().add_entities([{"id": "d", "type": "opening", "props": {"kind": "door", "pos": [0, 0], "width_mm": 900}}])
	h.model().set_selection(["d"])
	var labels: Array[Node] = []
	_all_of(h.window.panel, "Label", labels)
	var texts: Array[String] = []
	for node: Node in labels:
		texts.append((node as Label).text)
	assert_true(texts.has("Porte"), "header names the entity")
	assert_true(texts.has("Largeur (mm)"))
	assert_false(texts.has("Nom de l'étage"), "the étage settings are hidden while editing an entity")
	var spins: Array[Node] = []
	_all_of(h.window.panel, "SpinBox", spins)
	for node: Node in spins:
		if (node as SpinBox).value == 900.0:
			(node as SpinBox).value = 1000.0
	assert_eq(h.model().sheet().entities["d"].props["width_mm"], 1000)


func test_panel_edits_several_selected_entities_together() -> void:
	h.model().add_entities([
		{"id": "a", "type": "text", "props": {"pos": [0, 0], "text": "A"}},
		{"id": "b", "type": "text", "props": {"pos": [0, 900], "text": "B"}},
	])
	h.model().set_selection(["a", "b"])
	var spins: Array[Node] = []
	_all_of(h.window.panel, "SpinBox", spins)
	for node: Node in spins:
		var spin: SpinBox = node as SpinBox
		if spin.value == 0.0 and spin.step == 0.1:
			spin.value = 18.0
	assert_eq(h.model().sheet().entities["a"].props["size_pt"], 18.0)
	assert_eq(h.model().sheet().entities["b"].props["size_pt"], 18.0)


# --- files -----------------------------------------------------------------------------------


func test_autosave_and_recovery_round_trip() -> void:
	h.model().add_entities([{"id": "w", "type": "wall", "props": {"points": [[0, 0], [4000, 0]]}}])
	h.window.autosave()
	var recovered: Dictionary = ProjectFiles.read_autosave(98)
	var doc: Document = recovered["document"]
	assert_not_null(doc)
	assert_eq(DocumentIO.to_json(doc), DocumentIO.to_json(h.model().doc()))
	assert_eq(recovered["project_path"], "")


func test_autosave_is_skipped_when_nothing_changed() -> void:
	h.window.autosave()
	h.window.autosave()
	ProjectFiles.clear_autosave(98)
	h.window.autosave()
	assert_false(FileAccess.file_exists(ProjectFiles.autosave_path(98)), "no change since the last autosave: nothing written")


func test_save_writes_a_project_that_reopens_identically() -> void:
	h.model().add_entities([{"id": "w", "type": "wall", "props": {"points": [[0, 0], [4000, 0]]}}])
	h.window._write_to("user://integration_save_test")
	assert_eq(h.window.project_path, "user://integration_save_test.giroflee")
	assert_false(h.window.is_dirty())
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file("user://integration_save_test.giroflee")
	assert_eq(loaded.error, "")
	assert_eq(DocumentIO.to_json(loaded.document), DocumentIO.to_json(h.model().doc()))
	h.model().add_entities([{"id": "w2", "type": "wall", "props": {"points": [[0, 0], [0, 4000]]}}])
	assert_true(h.window.is_dirty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://integration_save_test.giroflee"))


func test_opening_a_document_rebinds_everything() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "a", "Cave")
	TestKit.add_sheet(s, "b", "Grenier")
	h.window.open_document(s.document(), "")
	assert_eq(h.window.tabs.tab_count, 2)
	assert_eq(h.window.tabs.get_tab_title(1), "Grenier")
	assert_eq(h.model().active_sheet_id, "a")
