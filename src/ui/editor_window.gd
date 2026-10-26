class_name EditorWindow
extends Control
## The editor: étage tabs on top, the canvas in the middle, the properties panel on the right,
## a status bar at the bottom, and the command palette and inline text editor as overlays.
## One project per window (SRD FR-CFG-2); the tabs are the étages. No dialogs except the
## file pickers behind "Ouvrir" and "Enregistrer sous".

const AUTOSAVE_SECONDS: float = 15.0
const NOTICE_SECONDS: float = 5.0

var slot: int = 0
var project_path: String = ""
var model: EditorModel
var input: EditorInput

var menu_bar: MenuBar
var toolbar: ToolPalette
var canvas: CanvasView
var panel: PropertiesPanel
var circuits: CircuitPanel
var quickbar_view: QuickbarView
var palette: PaletteOverlay
var tabs: TabBar
var status_hint: Label
var status_info: Label

var _add_button: Button
var _inline: LineEdit
var _inline_commit: Callable = Callable()
var _inline_done: bool = true
var _syncing_tabs: bool = false
var _saved_revision: int = 0
var _autosaved_revision: int = 0
var _notice_left: float = 0.0
var _notice_text: String = ""
var _autosave_timer: Timer
## Menu title -> PopupMenu, and menu title -> {item id: {"do": Callable, "state": Callable?}}.
var _menus: Dictionary = {}
var _menu_items: Dictionary = {}


func _init() -> void:
	theme = AppTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	menu_bar = MenuBar.new()
	menu_bar.prefer_global_menu = false
	root.add_child(menu_bar)

	var top: HBoxContainer = HBoxContainer.new()
	root.add_child(top)
	tabs = TabBar.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	tabs.tab_changed.connect(_on_tab_changed)
	tabs.gui_input.connect(_on_tabs_input)
	top.add_child(tabs)
	_add_button = Button.new()
	_add_button.text = "+"
	_add_button.tooltip_text = "Nouvel étage (Ctrl+T)"
	_add_button.focus_mode = Control.FOCUS_NONE
	_add_button.pressed.connect(func() -> void: model.new_sheet())
	top.add_child(_add_button)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var work: HBoxContainer = HBoxContainer.new()
	work.add_theme_constant_override("separation", 0)
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(work)
	toolbar = ToolPalette.new()
	var prefs: Dictionary = UserPrefs.load_prefs()
	var show_toolbar: bool = prefs["toolbar_visible"]
	toolbar.visible = show_toolbar
	work.add_child(toolbar)
	canvas = CanvasView.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work.add_child(canvas)
	var side: VBoxContainer = VBoxContainer.new()
	split.add_child(side)
	circuits = CircuitPanel.new()
	side.add_child(circuits)
	panel = PropertiesPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(panel)

	quickbar_view = QuickbarView.new()
	root.add_child(quickbar_view)

	var status_bar: PanelContainer = PanelContainer.new()
	status_bar.theme_type_variation = "ToolPanel"
	root.add_child(status_bar)
	var bottom: HBoxContainer = HBoxContainer.new()
	status_bar.add_child(bottom)
	status_hint = Label.new()
	status_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_hint.clip_text = true
	bottom.add_child(status_hint)
	status_info = Label.new()
	bottom.add_child(status_info)
	_build_menus()

	palette = PaletteOverlay.new()
	palette.closed.connect(func() -> void: canvas.grab_focus())
	add_child(palette)

	_inline = LineEdit.new()
	_inline.visible = false
	_inline.text_submitted.connect(func(_t: String) -> void: _finish_inline(true))
	_inline.focus_exited.connect(func() -> void: _finish_inline(true))
	_inline.gui_input.connect(_on_inline_input)
	add_child(_inline)

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(autosave)
	add_child(_autosave_timer)


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice_text = ""
			_update_status()


# --- project ------------------------------------------------------------------------------


## Shows `doc` (a fresh project when null) in this window.
func open_document(doc: Document, p_path: String = "") -> void:
	var document: Document = doc if doc != null else Document.new_project()
	project_path = p_path
	var session: Session = Session.new(InProcessChannel.new(document))
	model = EditorModel.new(session)
	input = EditorInput.new(model)
	model.clipboard_get = func() -> String: return DisplayServer.clipboard_get()
	model.clipboard_set = func(text: String) -> void: DisplayServer.clipboard_set(text)
	model.sheet_changed.connect(_sync_tabs)
	model.changed.connect(_update_status)
	model.notice.connect(_show_notice)
	model.text_requested.connect(_on_text_requested)
	model.rename_requested.connect(_on_rename_requested)
	input.palette_requested.connect(open_palette)
	input.new_window_requested.connect(new_window)
	canvas.bind(model, input)
	panel.bind(model)
	circuits.bind(model)
	quickbar_view.bind(model)
	toolbar.bind(model)
	_saved_revision = model.revision
	_autosaved_revision = model.revision
	_sync_tabs()
	_update_status()
	_update_title()
	canvas.grab_focus.call_deferred()


func is_dirty() -> bool:
	return model != null and model.revision != _saved_revision


func autosave() -> void:
	if model == null or model.revision == _autosaved_revision:
		return
	var error: String = ProjectFiles.write_autosave(model.doc(), slot, project_path)
	if error.is_empty():
		_autosaved_revision = model.revision


func save() -> void:
	if project_path.is_empty():
		save_as()
		return
	_write_to(project_path)


func save_as() -> void:
	_pick_file(DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, "Enregistrer le projet", _write_to)


## Opens a project: in this window when it is still empty, otherwise in a new one, so that
## nothing is ever replaced behind the user's back.
func open_project() -> void:
	_pick_file(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Ouvrir un projet", _open_picked)


func new_window(extra_args: PackedStringArray = PackedStringArray()) -> void:
	var args: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_args():
		if arg == "--":
			break
		args.append(arg)
	args.append("--")
	args.append("--slot=%d" % ProjectFiles.next_free_slot())
	args.append_array(extra_args)
	if args.size() > 0 and OS.create_instance(args) < 0:
		_show_notice("Impossible d'ouvrir une nouvelle fenêtre")


func _write_to(path: String) -> void:
	var target: String = path if path.ends_with(".giroflee") else path + ".giroflee"
	var error: String = DocumentIO.save_file(model.doc(), target)
	if not error.is_empty():
		_show_notice(error)
		return
	project_path = target
	_saved_revision = model.revision
	autosave()
	_update_title()
	_show_notice("Enregistré : %s" % target.get_file())


func _open_picked(path: String) -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file(path)
	if loaded.document == null:
		_show_notice("%s : %s" % [path.get_file(), loaded.error])
		return
	if model != null and model.session.history.undo_depth() == 0 and project_path.is_empty():
		open_document(loaded.document, path)
	else:
		new_window(PackedStringArray(["--open", path]))


func _pick_file(mode: DisplayServer.FileDialogMode, title: String, callback: Callable) -> void:
	var filters: PackedStringArray = PackedStringArray(["*.giroflee ; Projet Giroflée"])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(title, "", "", false, mode, filters,
			func(status: bool, paths: PackedStringArray, _filter: int) -> void:
				if status and not paths.is_empty():
					callback.call_deferred(paths[0]))
		return
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == DisplayServer.FILE_DIALOG_MODE_SAVE_FILE else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = title
	dialog.filters = PackedStringArray(["*.giroflee ; Projet Giroflée"])
	dialog.file_selected.connect(func(path: String) -> void: callback.call(path))
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(_p: String) -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


# --- menu bar -----------------------------------------------------------------------------


## The PopupMenu of a top-level menu ("Fichier", "Édition", "Symboles", "Étage", "Affichage", "Projet").
func menu(title: String) -> PopupMenu:
	if _menus.has(title):
		var popup: PopupMenu = _menus[title]
		return popup
	return null


func set_toolbar_visible(shown: bool) -> void:
	toolbar.visible = shown
	UserPrefs.set_value("toolbar_visible", shown)


func _build_menus() -> void:
	# a shortcut is shown only when the author approved one (WA-1); it is text, not a binding,
	# so the editor's own key handling stays the single place where keys are interpreted
	_add_menu("Fichier", [
		{"text": "Nouveau projet (nouvelle fenêtre)", "hint": "Ctrl+N", "do": func() -> void: new_window(PackedStringArray(["--new"]))},
		{"text": "Ouvrir…", "do": func() -> void: open_project()},
		{"text": "Enregistrer", "do": func() -> void: save()},
		{"text": "Enregistrer sous…", "do": func() -> void: save_as()},
	])
	_add_menu("Édition", [
		{"text": "Annuler", "hint": "Ctrl+Z", "do": func() -> void: model.undo()},
		{"text": "Rétablir", "hint": "Ctrl+Y", "do": func() -> void: model.redo()},
		{"separator": true},
		{"text": "Couper", "hint": "Ctrl+X", "do": func() -> void: model.cut_selection()},
		{"text": "Copier", "hint": "Ctrl+C", "do": func() -> void: model.copy_selection()},
		{"text": "Coller", "hint": "Ctrl+V", "do": func() -> void: model.paste()},
		{"text": "Dupliquer", "hint": "Ctrl+D", "do": func() -> void: model.duplicate_selection()},
		{"text": "Supprimer", "do": func() -> void: model.delete_selection()},
		{"text": "Tout sélectionner", "do": func() -> void: model.select_all()},
		{"separator": true},
		{"text": "Copier les propriétés", "do": func() -> void: model.copy_settings()},
		{"text": "Coller les propriétés", "do": func() -> void: model.paste_settings()},
	])
	_add_menu("Symboles", [
		{"text": "Pipette", "hint": "A", "do": func() -> void: model.pipette()},
		{"text": "Replacer les étiquettes", "do": func() -> void: model.relabel()},
		{"text": "Libérer les étiquettes fixées à la main", "do": func() -> void: model.unpin_labels()},
		{"text": "Compacter la numérotation", "do": func() -> void: model.compact_numbering()},
		{"separator": true},
		{"text": "Ancrer à un symbole", "do": func() -> void: model.begin_anchor()},
		{"text": "Détacher", "do": func() -> void: model.detach_selection()},
	])
	_add_menu("Étage", [
		{"text": "Nouvel étage", "hint": "Ctrl+T", "do": func() -> void: model.new_sheet()},
		{"text": "Dupliquer l'étage", "do": func() -> void: model.duplicate_sheet(false)},
		{"text": "Dupliquer l'étage avec les symboles", "do": func() -> void: model.duplicate_sheet(true)},
		{"text": "Renommer l'étage", "hint": "F2", "do": func() -> void: model.rename_requested.emit(model.active_sheet_id)},
		{"text": "Supprimer l'étage", "do": func() -> void: model.delete_sheet()},
	])
	_add_menu("Affichage", [
		{"text": "Étage fantôme", "do": func() -> void: model.toggle_ghost(), "state": func() -> bool: return _config_flag("ghost_on")},
		{"text": "Repères A4 / A3", "do": func() -> void: model.toggle_hints(), "state": func() -> bool: return _config_flag("hints")},
		{"text": "Accrochage", "do": func() -> void: EditorCommands.toggle_snap(model), "state": func() -> bool: return model.snap_enabled},
		{"text": "Barre d'outils", "do": func() -> void: set_toolbar_visible(not toolbar.visible), "state": func() -> bool: return toolbar.visible},
	])
	_add_menu("Projet", [
		{"text": "Réglages du projet", "do": func() -> void: show_project_settings()},
	])


## Shows the project-wide settings in the Properties panel (no popup window).
func show_project_settings() -> void:
	model.set_tool("select")
	model.clear_selection()
	panel.refresh()


func _add_menu(title: String, items: Array) -> void:
	var popup: PopupMenu = PopupMenu.new()
	popup.name = title
	menu_bar.add_child(popup)
	_menus[title] = popup
	var actions: Dictionary = {}
	var next_id: int = 1
	for item: Variant in items:
		var entry: Dictionary = item
		if entry.has("separator"):
			popup.add_separator()
			continue
		var label: String = entry["text"]
		var hint: String = entry.get("hint", "")
		if not hint.is_empty():
			label = "%s    %s" % [label, hint]
		if entry.has("state"):
			popup.add_check_item(label, next_id)
		else:
			popup.add_item(label, next_id)
		actions[next_id] = entry
		next_id += 1
	_menu_items[title] = actions
	popup.id_pressed.connect(_on_menu_pressed.bind(title))
	popup.about_to_popup.connect(_refresh_menu.bind(title))


func _config_flag(key: String) -> bool:
	var value: bool = model.doc().config[key]
	return value


func _on_menu_pressed(id: int, title: String) -> void:
	var actions: Dictionary = _menu_items[title]
	if not actions.has(id) or model == null:
		return
	var entry: Dictionary = actions[id]
	var action: Callable = entry["do"]
	action.call()
	_refresh_menu(title)


## Check marks always show the current state.
func _refresh_menu(title: String) -> void:
	if model == null:
		return
	var popup: PopupMenu = _menus[title]
	var actions: Dictionary = _menu_items[title]
	for key: Variant in actions.keys():
		var entry: Dictionary = actions[key]
		if entry.has("state"):
			var state: Callable = entry["state"]
			var checked: bool = state.call()
			var item_id: int = key
			popup.set_item_checked(popup.get_item_index(item_id), checked)


# --- palette ------------------------------------------------------------------------------


func open_palette() -> void:
	var entries: Array[EditorCommands.Entry] = EditorCommands.build(model)
	entries.append(EditorCommands.Entry.new("file.open", "Ouvrir un projet…", "", open_project))
	entries.append(EditorCommands.Entry.new("file.save", "Enregistrer", "", save))
	entries.append(EditorCommands.Entry.new("file.save_as", "Enregistrer sous…", "", save_as))
	entries.append(EditorCommands.Entry.new("file.new", "Nouveau projet (nouvelle fenêtre)", "Ctrl+N", new_window.bind(PackedStringArray(["--new"]))))
	palette.open(entries)
	palette.position = Vector2((size.x - palette.custom_minimum_size.x) * 0.5, 70.0)


# --- keys ---------------------------------------------------------------------------------


func _unhandled_key_input(event: InputEvent) -> void:
	if input == null or palette.visible:
		return
	if input.handle(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


# --- tabs ---------------------------------------------------------------------------------


func _sync_tabs() -> void:
	_syncing_tabs = true
	tabs.clear_tabs()
	for sheet_id: String in model.doc().sheet_order:
		tabs.add_tab(model.doc().get_sheet(sheet_id).display_name())
	var index: int = model.doc().sheet_order.find(model.active_sheet_id)
	if index >= 0:
		tabs.current_tab = index
	_syncing_tabs = false
	_update_title()


func _on_tab_changed(index: int) -> void:
	if _syncing_tabs or model == null:
		return
	var order: Array[String] = model.doc().sheet_order
	if index >= 0 and index < order.size():
		model.set_active_sheet(order[index])
		canvas.grab_focus()


func _on_tabs_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
			_on_rename_requested(model.active_sheet_id)


# --- inline text editing --------------------------------------------------------------------


func _on_text_requested(world_pos: Vector2, entity_id: String, initial: String) -> void:
	var view: ViewTransform = model.view()
	var screen: Vector2 = canvas.global_position - global_position + view.world_to_screen(world_pos)
	var base_pt: float = model.doc().config["font_size_pt"]
	var size_world: float = model.ctx().pt_to_world(base_pt * PlanTheme.role_factor("free"))
	var font_px: int = clampi(roundi(size_world * view.zoom), 12, 64)
	var commit: Callable = func(text: String) -> void:
		if entity_id.is_empty():
			if not text.strip_edges().is_empty():
				model.add_text(world_pos, text)
		else:
			model.set_text(entity_id, text)
	_begin_inline(Rect2(screen + Vector2(0, -font_px * 1.4), Vector2(260, font_px * 1.6 + 8)), initial, font_px, commit)


func _on_rename_requested(sheet_id: String) -> void:
	var index: int = model.doc().sheet_order.find(sheet_id)
	if index < 0:
		return
	var rect: Rect2 = tabs.get_tab_rect(index)
	rect.position += tabs.global_position - global_position
	var commit: Callable = func(text: String) -> void: model.rename_sheet(sheet_id, text)
	_begin_inline(Rect2(rect.position, Vector2(maxf(rect.size.x, 180.0), rect.size.y)), model.doc().get_sheet(sheet_id).display_name(), 14, commit)


func _begin_inline(rect: Rect2, initial: String, font_px: int, commit: Callable) -> void:
	_inline_commit = commit
	_inline_done = false
	_inline.position = rect.position
	_inline.size = rect.size
	_inline.text = initial
	_inline.add_theme_font_size_override("font_size", font_px)
	_inline.visible = true
	_inline.grab_focus()
	_inline.select_all()


func _finish_inline(accept: bool) -> void:
	if _inline_done:
		return
	_inline_done = true
	_inline.visible = false
	var text: String = _inline.text
	var commit: Callable = _inline_commit
	_inline_commit = Callable()
	if accept and commit.is_valid():
		commit.call(text)
	canvas.grab_focus()


func _on_inline_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE:
			_finish_inline(false)
			_inline.accept_event()


# --- status -------------------------------------------------------------------------------


func _show_notice(message: String) -> void:
	_notice_text = message
	_notice_left = NOTICE_SECONDS
	_update_status()


func _update_status() -> void:
	if model == null:
		return
	var hint: String = model.tool.hint(model)
	if model.pending_prefix == "C":
		hint = "Circuit : tapez une lettre (A à Z) pour la sélection, ou pour les prochains symboles · Échap = annuler"
	elif model.pending_prefix == "X":
		hint = "Nombre : tapez un chiffre (1 à 9) · Échap = annuler"
	status_hint.text = _notice_text if not _notice_text.is_empty() else hint
	var circuit_text: String = "circuit %s%s" % [model.active_circuit, " ×%d" % model.place_count if model.place_count > 1 else ""]
	var view: ViewTransform = model.view()
	var snap_text: String = ""
	if model.hover_snap != null and model.hover_snap.kind != SnapEngine.NONE:
		snap_text = "  ·  %s" % ("sommet" if model.hover_snap.kind == SnapEngine.VERTEX else ("milieu" if model.hover_snap.kind == SnapEngine.MIDPOINT else "grille"))
	var pos: Vector2 = model.hover
	status_info.text = "%s  ·  x %s  y %s  ·  zoom %d %%%s " % [circuit_text, Fmt.length(pos.x), Fmt.length(pos.y), roundi(view.zoom * 100.0 / 0.1), snap_text]
	_update_title()


func _update_title() -> void:
	if model == null or not is_inside_tree():
		return
	var name: String = project_path.get_file().get_basename() if not project_path.is_empty() else "Sans titre"
	var window: Window = get_window()
	if window != null:
		window.title = "%s%s — %s" % [name, " •" if is_dirty() else "", AppInfo.APP_NAME]
