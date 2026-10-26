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

var canvas: CanvasView
var panel: PropertiesPanel
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


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

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
	canvas = CanvasView.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(canvas)
	panel = PropertiesPanel.new()
	split.add_child(panel)

	var bottom: HBoxContainer = HBoxContainer.new()
	root.add_child(bottom)
	status_hint = Label.new()
	status_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_hint.clip_text = true
	bottom.add_child(status_hint)
	status_info = Label.new()
	bottom.add_child(status_info)

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
	status_hint.text = _notice_text if not _notice_text.is_empty() else model.tool.hint(model)
	var view: ViewTransform = model.view()
	var snap_text: String = ""
	if model.hover_snap != null and model.hover_snap.kind != SnapEngine.NONE:
		snap_text = "  ·  %s" % ("sommet" if model.hover_snap.kind == SnapEngine.VERTEX else ("milieu" if model.hover_snap.kind == SnapEngine.MIDPOINT else "grille"))
	var pos: Vector2 = model.hover
	status_info.text = "x %s  y %s  ·  zoom %d %%%s " % [Fmt.length(pos.x), Fmt.length(pos.y), roundi(view.zoom * 100.0 / 0.1), snap_text]
	_update_title()


func _update_title() -> void:
	if model == null or not is_inside_tree():
		return
	var name: String = project_path.get_file().get_basename() if not project_path.is_empty() else "Sans titre"
	var window: Window = get_window()
	if window != null:
		window.title = "%s%s — %s" % [name, " •" if is_dirty() else "", AppInfo.APP_NAME]
