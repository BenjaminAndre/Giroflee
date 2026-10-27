extends GutTest
@warning_ignore_start("unsafe_call_argument")
## M2b: menu bar (FR-MENU), tool bar (FR-TOOLBAR) and the Latte theme (FR-UI) in the real window.

var h: UiHarness


func before_each() -> void:
	UserPrefs.path = "user://prefs_test.json"
	h = await UiHarness.create(self)


func after_each() -> void:
	if FileAccess.file_exists(UserPrefs.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPrefs.path))
	ProjectFiles.clear_autosave(98)


func _item(menu: PopupMenu, label: String) -> int:
	for i: int in menu.item_count:
		if menu.get_item_text(i).begins_with(label):
			return i
	return -1


func _press(menu_title: String, label: String) -> void:
	var menu: PopupMenu = h.window.menu(menu_title)
	assert_not_null(menu, "menu %s exists" % menu_title)
	var index: int = _item(menu, label)
	assert_true(index >= 0, "%s > %s exists" % [menu_title, label])
	menu.about_to_popup.emit()
	menu.id_pressed.emit(menu.get_item_id(index))


func _checked(menu_title: String, label: String) -> bool:
	var menu: PopupMenu = h.window.menu(menu_title)
	menu.about_to_popup.emit()
	return menu.is_item_checked(_item(menu, label))


# --- menu bar -------------------------------------------------------------------------------------


func test_the_menu_bar_has_the_five_menus() -> void:
	assert_not_null(h.window.menu_bar)
	for title: String in ["Fichier", "Édition", "Étage", "Affichage", "Projet"]:
		assert_not_null(h.window.menu(title), title)


func test_menus_list_their_commands_with_approved_shortcuts_only() -> void:
	var file: PopupMenu = h.window.menu("Fichier")
	for label: String in ["Nouveau projet", "Ouvrir", "Enregistrer", "Enregistrer sous"]:
		assert_true(_item(file, label) >= 0, label)
	assert_string_contains(file.get_item_text(_item(file, "Nouveau projet")), "Ctrl+N")
	assert_false(file.get_item_text(_item(file, "Enregistrer")).contains("Ctrl+S"), "no key was approved for saving (WA-1)")
	var edit: PopupMenu = h.window.menu("Édition")
	assert_string_contains(edit.get_item_text(_item(edit, "Annuler")), "Ctrl+Z")
	var sheet: PopupMenu = h.window.menu("Étage")
	assert_string_contains(sheet.get_item_text(_item(sheet, "Nouvel étage")), "Ctrl+T")
	assert_string_contains(sheet.get_item_text(_item(sheet, "Renommer")), "F2")


func test_menu_items_do_not_register_global_shortcuts() -> void:
	# a menu shortcut would fire in addition to the editor's own key handling
	for title: String in ["Fichier", "Édition", "Étage", "Affichage", "Projet"]:
		var menu: PopupMenu = h.window.menu(title)
		for i: int in menu.item_count:
			assert_null(menu.get_item_shortcut(i), "%s item %d has no Shortcut resource" % [title, i])


func test_etage_menu_creates_and_duplicates_and_deletes() -> void:
	_press("Étage", "Nouvel étage")
	assert_eq(h.model().doc().plan_ids().size(), 2)
	_press("Étage", "Dupliquer l'étage")
	assert_eq(h.model().doc().plan_ids().size(), 3)
	_press("Étage", "Supprimer l'étage")
	assert_eq(h.model().doc().plan_ids().size(), 2)


func test_edition_menu_undoes_and_redoes() -> void:
	h.model().add_entities([{"id": "w", "type": "wall", "props": {"points": [[0, 0], [1000, 0]]}}])
	_press("Édition", "Annuler")
	assert_false(h.model().sheet().entities.has("w"))
	_press("Édition", "Rétablir")
	assert_true(h.model().sheet().entities.has("w"))
	h.model().set_selection(["w"])
	_press("Édition", "Supprimer")
	assert_false(h.model().sheet().entities.has("w"))


func test_the_ghost_item_is_a_project_wide_check_item() -> void:
	assert_false(_checked("Affichage", "Étage fantôme"))
	_press("Affichage", "Étage fantôme")
	assert_true(h.model().doc().config["ghost_on"])
	assert_true(_checked("Affichage", "Étage fantôme"), "the check mark follows the state")
	_press("Étage", "Nouvel étage")
	assert_true(_checked("Affichage", "Étage fantôme"), "still on in another étage: it is project-wide")
	h.model().undo()
	h.model().undo()
	assert_false(_checked("Affichage", "Étage fantôme"), "undoable, and the item follows")


func test_the_hints_item_and_snap_item() -> void:
	assert_true(_checked("Affichage", "Repères A4"))
	_press("Affichage", "Repères A4")
	assert_false(h.model().doc().config["hints"])
	assert_true(_checked("Affichage", "Accrochage"))
	_press("Affichage", "Accrochage")
	assert_false(h.model().snap_enabled)
	assert_false(_checked("Affichage", "Accrochage"))


func test_project_settings_item_shows_the_project_section_without_a_popup() -> void:
	h.model().add_entities([{"id": "w", "type": "wall", "props": {"points": [[0, 0], [1000, 0]]}}])
	h.model().set_selection(["w"])
	_press("Projet", "Réglages du projet")
	assert_eq(h.model().selection, [], "the selection is cleared so the project settings show")
	var found: bool = false
	for label: Node in _all(h.window.panel, "Label"):
		if (label as Label).text == "Colonnes du cadre":
			found = true
	assert_true(found, "the frame settings are in the panel")


func _all(node: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	_collect(node, type_name, out)
	return out


func _collect(node: Node, type_name: String, out: Array[Node]) -> void:
	if node.get_class() == type_name:
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, type_name, out)


func test_the_panel_project_section_holds_the_project_wide_settings() -> void:
	var labels: Array[String] = []
	for node: Node in _all(h.window.panel, "Label"):
		labels.append((node as Label).text)
	for expected: String in ["Colonnes du cadre", "Lignes du cadre", "Titre : position (mm)"]:
		assert_true(labels.has(expected), expected)
	var checks: Array[String] = []
	for node: Node in _all(h.window.panel, "CheckBox"):
		checks.append((node as CheckBox).text)
	assert_true(checks.has("Afficher l'étage fantôme"))
	assert_true(checks.has("Repères A4 / A3"))
	assert_false(labels.has("Page : largeur (mm)") and false)


func test_editing_the_frame_in_the_panel_changes_the_project_for_every_etage() -> void:
	_press("Étage", "Nouvel étage")
	var spin: SpinBox = null
	for node: Node in _all(h.window.panel, "SpinBox"):
		if (node as SpinBox).value == 17.0:
			spin = node as SpinBox
	assert_not_null(spin)
	spin.value = 9.0
	assert_eq(h.model().doc().config["frame_cols"], 9)
	h.model().set_active_sheet(h.model().doc().plan_ids()[0])
	var numbers: int = 0
	for op: DrawOp in h.model().page_list().ops:
		if op.layer == "frame" and op.kind == DrawOp.TEXT and op.text.is_valid_int():
			numbers += 1
	assert_eq(numbers, 9)


# --- tool bar -------------------------------------------------------------------------------------


func test_the_tool_bar_is_visible_by_default_with_one_button_per_tool() -> void:
	assert_true(h.window.toolbar.visible)
	for tool_name: String in ["select", "wall", "door", "window", "stair", "block", "text"]:
		assert_not_null(h.window.toolbar.button_for(tool_name), tool_name)


func test_buttons_are_icon_only_with_a_tooltip_naming_the_hot_key() -> void:
	var expected: Dictionary = {
		"select": "Sélection (Échap)", "wall": "Mur (W)", "door": "Porte (D)", "window": "Fenêtre (F)",
		"stair": "Escalier (E)", "block": "Bloc gris (S)", "text": "Texte (T)",
	}
	for tool_name: String in expected.keys():
		var button: Button = h.window.toolbar.button_for(tool_name)
		assert_eq(button.text, "", "icon only")
		assert_not_null(button.icon, "%s has an icon" % tool_name)
		assert_eq(button.tooltip_text, expected[tool_name])


func test_clicking_a_button_selects_the_tool_and_the_keyboard_presses_the_button() -> void:
	h.window.toolbar.button_for("wall").pressed.emit()
	assert_eq(h.model().tool_name, "wall")
	h.key("D")
	await h.play(self)
	assert_eq(h.model().tool_name, "door")
	assert_true(h.window.toolbar.button_for("door").button_pressed)
	assert_false(h.window.toolbar.button_for("wall").button_pressed, "exactly one tool is pressed")
	h.key("Escape")
	await h.play(self)
	assert_true(h.window.toolbar.button_for("select").button_pressed)


func test_the_tool_bar_can_be_hidden_from_the_menu_and_the_choice_is_remembered() -> void:
	assert_true(_checked("Affichage", "Barre d'outils"))
	_press("Affichage", "Barre d'outils")
	assert_false(h.window.toolbar.visible)
	assert_false(_checked("Affichage", "Barre d'outils"))
	assert_false(UserPrefs.load_prefs()["toolbar_visible"], "stored outside the project")
	var second: UiHarness = await UiHarness.create(self)
	assert_false(second.window.toolbar.visible, "a new window starts with the stored choice")
	_press("Affichage", "Barre d'outils")
	assert_true(h.window.toolbar.visible)


func test_hiding_the_tool_bar_is_not_a_document_change() -> void:
	var before: int = h.model().revision
	_press("Affichage", "Barre d'outils")
	assert_eq(h.model().revision, before)
	assert_false(h.model().session.can_undo())


# --- theme ----------------------------------------------------------------------------------------


func test_the_window_uses_the_latte_theme() -> void:
	assert_not_null(h.window.theme)
	assert_eq(h.window.theme.get_color("font_color", "Label"), AppTheme.TEXT)
	var panel_style: StyleBoxFlat = h.window.theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_eq(panel_style.bg_color, AppTheme.BASE)


func test_the_canvas_workspace_is_light() -> void:
	assert_true(CanvasView.WORKSPACE.get_luminance() > 0.7, "no dark mode")
	assert_eq(CanvasView.WORKSPACE, AppTheme.CRUST)
