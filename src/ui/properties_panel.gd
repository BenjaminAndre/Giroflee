class_name PropertiesPanel
extends PanelContainer
## Docked, context-sensitive properties (SRD FR-CFG-1). With nothing selected it shows the
## étage settings and the project settings; with a selection it shows the properties of that
## entity (several of the same type are edited together). The editors are generated from the
## Schema, and every change is a command through the EditorModel, so it is undoable.

const LABELS: Dictionary = {
	"name": "Nom de l'étage",
	"paper_w_mm": "Page : largeur (mm)",
	"paper_h_mm": "Page : hauteur (mm)",
	"scale_den": "Échelle 1 /",
	"frame_cols": "Colonnes du cadre",
	"frame_rows": "Lignes du cadre",
	"grid_step_mm": "Pas de la grille (mm)",
	"hints": "Repères A4 / A3",
	"title_pos_mm": "Titre : position (mm)",
	"ghost_on": "Afficher l'étage fantôme",
	"ghost_sheets": "Étages fantômes",
	"font_family": "Police",
	"font_size_pt": "Taille de base (pt)",
	"wall_weight_mm": "Épaisseur des murs (mm page)",
	"provisoire_mark": "Marque PROVISOIRE",
	"points": "Points",
	"weight_mm": "Épaisseur (mm page)",
	"kind": "Type",
	"pos": "Position (mm)",
	"width_mm": "Largeur (mm)",
	"rotation": "Rotation (°)",
	"flip_h": "Retourné horizontalement",
	"flip_v": "Retourné verticalement",
	"steps": "Nombre de marches",
	"tread_mm": "Giron (mm)",
	"size": "Dimensions (mm)",
	"text": "Texte",
	"role": "Rôle",
	"font": "Police (vide = projet)",
	"size_pt": "Taille (pt, 0 = projet)",
	"symbol_type": "Symbole",
	"circuit": "Circuit",
	"index": "Indice",
	"count": "Nombre",
	"height_mm": "Hauteur (mm)",
	"symbol_scale": "Échelle des symboles",
}

const TYPE_TITLES: Dictionary = {
	"wall": "Mur",
	"stair": "Escalier",
	"grey_block": "Bloc gris",
	"text": "Texte",
	"symbol": "Symbole",
}

const HIDDEN: Array[String] = [
	"symbol_type", "anchor_parent", "anchor_offset", "label_pinned", "label_offset", "count_offset",
	"host_wall", "host_offset_mm",
]

const FONT_CHOICES: Array[String] = ["Atkinson Hyperlegible", "OpenDyslexic"]

var model: EditorModel
var _box: VBoxContainer
var _signature: String = ""
## True while a change made from this panel is being applied: the editors stay as they are
## (the user may be in the middle of typing in one), instead of being rebuilt under them.
var _busy: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(360, 0)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func bind(p_model: EditorModel) -> void:
	if model != null and model.changed.is_connected(refresh):
		model.changed.disconnect(refresh)
	model = p_model
	model.changed.connect(refresh)
	_signature = ""
	refresh()


## Rebuilds the editors when the selection, the étage or the document changed.
func refresh() -> void:
	if model == null or _busy:
		return
	var signature: String = _compute_signature()
	if signature == _signature:
		return
	_signature = signature
	_rebuild()


func _compute_signature() -> String:
	return "%s|%s|%d|%d" % [model.active_sheet_id, ",".join(PackedStringArray(model.selection)), model.revision, model.view_revision]


## Runs `change` (a model call) without rebuilding the editors around the user, then records
## the new state as current.
func _commit(change: Callable) -> void:
	_busy = true
	change.call()
	_busy = false
	_signature = _compute_signature()


func _rebuild() -> void:
	for child: Node in _box.get_children():
		child.queue_free()
		_box.remove_child(child)
	if model.sheet().kind == "unifilaire":
		_build_sheet_name()
		var board: BoardEditor = BoardEditor.new(model, _commit)
		_box.add_child(board)
		board.build_unifilaire()
		return
	var entities: Array[Entity] = model.selected_entities()
	if entities.is_empty():
		_build_sheet_section()
		_build_project_section()
		var cartouche: BoardEditor = BoardEditor.new(model, _commit)
		_box.add_child(cartouche)
		cartouche.build_cartouche()
		return
	var first: Entity = entities[0]
	for entity: Entity in entities:
		if entity.type != first.type:
			_add_header("%d éléments sélectionnés" % entities.size())
			return
	_build_entity_section(entities)


# --- sections -----------------------------------------------------------------------------


## The unifilaire's own settings are just its name (its page is fixed).
func _build_sheet_name() -> void:
	var sheet: Sheet = model.sheet()
	_add_row("name", "string", sheet.props["name"], _on_sheet_prop.bind("name"))


func _build_sheet_section() -> void:
	var sheet: Sheet = model.sheet()
	_add_header("Étage")
	for key: String in Schema.SHEET_SPEC.keys():
		var entry: Dictionary = Schema.SHEET_SPEC[key]
		var kind: String = entry["kind"]
		if key == "ghost_sheets":
			_add_ghost_sheets(sheet)
			continue
		_add_row(key, kind, sheet.props[key], _on_sheet_prop.bind(key))


func _build_project_section() -> void:
	_add_header("Projet")
	for key: String in Schema.CONFIG_SPEC.keys():
		var entry: Dictionary = Schema.CONFIG_SPEC[key]
		var kind: String = entry["kind"]
		if key == "font_family":
			var family: String = model.doc().config[key]
			_add_font_choice(family)
			continue
		_add_row(key, kind, model.doc().config[key], _on_config_prop.bind(key))


func _build_entity_section(entities: Array[Entity]) -> void:
	var first: Entity = entities[0]
	var title: String = str(TYPE_TITLES.get(first.type, ""))
	if first.type == "opening":
		var opening_kind: String = first.props["kind"]
		title = "Porte" if opening_kind == "door" else "Fenêtre"
	elif first.type == "symbol":
		var def: SymbolLibrary.Def = SymbolLibrary.for_pack(model.doc().pack_ref).def(str(first.props["symbol_type"]))
		title = def.title if def != null else "Symbole"
	if entities.size() > 1:
		title += " (%d)" % entities.size()
	_add_header(title)
	var spec: Dictionary = Schema.entity_spec(first.type)
	for key: String in spec.keys():
		if HIDDEN.has(key):
			continue
		var entry: Dictionary = spec[key]
		var kind: String = entry["kind"]
		if key == "kind":
			continue
		_add_row(key, kind, first.props[key], _on_entity_prop.bind(key))


# --- commit callbacks ---------------------------------------------------------------------


func _on_sheet_prop(value: Variant, key: String) -> void:
	_commit(func() -> void: model.set_sheet_props({key: value}))


func _on_config_prop(value: Variant, key: String) -> void:
	_commit(func() -> void: model.set_config(key, value))


func _on_entity_prop(value: Variant, key: String) -> void:
	_commit(func() -> void: model.apply_props(model.selection.duplicate(), {key: value}))


# --- widgets ------------------------------------------------------------------------------


func _add_header(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.1, 0.35, 0.65))
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_box.add_child(spacer)
	_box.add_child(label)


## One labelled editor for a property. `commit` is called with the new value.
func _add_row(key: String, kind: String, value: Variant, commit: Callable) -> void:
	var editor: Control = _make_editor(kind, value, commit)
	if editor == null:
		return
	if kind == "bool":
		_box.add_child(editor)
		(editor as CheckBox).text = str(LABELS.get(key, key))
		return
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = str(LABELS.get(key, key))
	label.custom_minimum_size = Vector2(170, 0)
	label.clip_text = true
	label.tooltip_text = label.text
	row.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	_box.add_child(row)


func _make_editor(kind: String, value: Variant, commit: Callable) -> Control:
	match kind:
		"int":
			var current: int = value
			return _spin(float(current), 1.0, true, func(v: float) -> void: commit.call(roundi(v)))
		"float":
			var number: float = value
			return _spin(number, 0.1, false, func(v: float) -> void: commit.call(v))
		"string":
			var text: String = value
			var edit: LineEdit = LineEdit.new()
			edit.text = text
			edit.text_submitted.connect(func(t: String) -> void: commit.call(t))
			edit.focus_exited.connect(func() -> void:
				if edit.text != text:
					commit.call(edit.text))
			return edit
		"bool":
			var on: bool = value
			var box: CheckBox = CheckBox.new()
			box.button_pressed = on
			box.toggled.connect(func(pressed: bool) -> void: commit.call(pressed))
			return box
		"vec2i":
			var pair: Array = value
			var px: int = pair[0]
			var py: int = pair[1]
			var row: HBoxContainer = HBoxContainer.new()
			var x_spin: SpinBox = _spin(float(px), 1.0, true, Callable())
			var y_spin: SpinBox = _spin(float(py), 1.0, true, Callable())
			var send: Callable = func(_v: float) -> void: commit.call([roundi(x_spin.value), roundi(y_spin.value)])
			x_spin.value_changed.connect(send)
			y_spin.value_changed.connect(send)
			row.add_child(x_spin)
			row.add_child(y_spin)
			return row
		"points":
			var points: Array = value
			var label: Label = Label.new()
			label.text = "%d points" % points.size()
			return label
	if kind.begins_with("enum:"):
		var options: PackedStringArray = kind.substr(5).split("|")
		var chosen: String = value
		var picker: OptionButton = OptionButton.new()
		for option: String in options:
			picker.add_item(option)
		picker.select(options.find(chosen))
		picker.item_selected.connect(func(index: int) -> void: commit.call(options[index]))
		return picker
	return null


func _spin(value: float, step: float, whole: bool, on_change: Callable) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = -10000000.0
	spin.max_value = 10000000.0
	spin.step = step
	spin.rounded = whole
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value
	if on_change.is_valid():
		spin.value_changed.connect(on_change)
	return spin


func _add_font_choice(current: String) -> void:
	var picker: OptionButton = OptionButton.new()
	for choice: String in FONT_CHOICES:
		picker.add_item(choice)
	var index: int = FONT_CHOICES.find(current)
	if index < 0:
		picker.add_item(current)
		index = picker.item_count - 1
	picker.select(index)
	picker.item_selected.connect(func(i: int) -> void:
		_commit(func() -> void: model.set_config("font_family", picker.get_item_text(i))))
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = str(LABELS["font_family"])
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	_box.add_child(row)


func _add_ghost_sheets(sheet: Sheet) -> void:
	var label: Label = Label.new()
	label.text = str(LABELS["ghost_sheets"])
	_box.add_child(label)
	var chosen: Array = sheet.props["ghost_sheets"]
	for other_id: String in model.doc().sheet_order:
		if other_id == sheet.id:
			continue
		var check: CheckBox = CheckBox.new()
		check.text = model.doc().get_sheet(other_id).display_name()
		check.button_pressed = chosen.has(other_id)
		check.toggled.connect(func(pressed: bool) -> void:
			var current_ghosts: Array = model.sheet().props["ghost_sheets"]
			var next: Array = current_ghosts.duplicate()
			if pressed and not next.has(other_id):
				next.append(other_id)
			elif not pressed:
				next.erase(other_id)
			_commit(func() -> void: model.set_sheet_props({"ghost_sheets": next})))
		_box.add_child(check)
