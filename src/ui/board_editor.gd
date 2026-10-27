class_name BoardEditor
extends VBoxContainer
## The unifilaire's side of the Properties panel (SRD FR-UNI-7) and the cartouche fields: circuit
## titles and protection, the bus devices, the head chain. Every change is a command through the
## EditorModel, so it is undoable. No dialogs.

var model: EditorModel
## Runs a model call without the panel rebuilding under the user's hands.
var commit: Callable = Callable()


func _init(p_model: EditorModel, p_commit: Callable) -> void:
	model = p_model
	commit = p_commit
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The unifilaire sections, then the cartouche.
func build_unifilaire() -> void:
	_header("Unifilaire")
	_build_selection()
	_build_bus()
	_build_head()
	var derived: UniModel = UnifilaireBuilder.derive(model.doc())
	var layout: UnifilaireLayout = UnifilaireLayout.compute(model.doc(), model.sheet(), derived)
	var notes: Array[String] = derived.warnings + layout.warnings
	for note: String in notes:
		var label: Label = Label.new()
		label.text = "⚠ %s" % note
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", AppTheme.PEACH)
		add_child(label)
	build_cartouche()


func build_cartouche() -> void:
	_header("Cartouche")
	var labels: Dictionary = CartoucheBuilder.field_labels(model.doc().pack_ref)
	for key: String in CartoucheBuilder.field_keys(model.doc().pack_ref):
		var stored: String = str(model.doc().cartouche.get(key, ""))
		var edit: LineEdit = LineEdit.new()
		edit.text = stored
		edit.name = "cartouche_%s" % key
		var send: Callable = func(text: String) -> void: commit.call(func() -> void: model.set_cartouche_field(key, text))
		edit.text_submitted.connect(send)
		edit.focus_exited.connect(func() -> void:
			if edit.text != str(model.doc().cartouche.get(key, "")):
				send.call(edit.text))
		_row(str(labels.get(key, key)), edit)


# --- what is selected -----------------------------------------------------------------------------


func _build_selection() -> void:
	var selected: Dictionary = model.uni_selection
	match str(selected.get("kind", "")):
		"column":
			_build_circuit(str(selected["letter"]))
		"device":
			_build_device(str(selected["id"]))
		"head":
			_build_head_item(str(selected["id"]))
		"point":
			var label: Label = Label.new()
			label.text = "Point %s%s (clic : voir le symbole sur le plan)" % [str(selected["letter"]), str(selected["index"])]
			add_child(label)
		_:
			var hint: Label = Label.new()
			hint.text = "Cliquez un circuit, un appareil ou un élément de la tête de ligne pour le modifier."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(hint)


func _build_circuit(letter: String) -> void:
	var derived: UniModel = UnifilaireBuilder.derive(model.doc())
	var column: UniModel.Column = derived.column_for(letter)
	if column == null:
		return
	var catalog: Catalog = Catalog.for_pack(model.doc().pack_ref)
	var stored: Dictionary = {}
	if model.doc().circuits.has(letter):
		stored = model.doc().circuits[letter]
	_subheader("Circuit %s" % letter)
	var title: LineEdit = LineEdit.new()
	title.name = "circuit_title"
	title.text = str(stored.get("title", ""))
	title.placeholder_text = UnifilaireBuilder.proposed_title(model.doc(), letter) if column.title_proposed or title.text.is_empty() else ""
	var send_title: Callable = func(text: String) -> void: commit.call(func() -> void: model.set_circuit_field(letter, "title", text))
	title.text_submitted.connect(send_title)
	title.focus_exited.connect(func() -> void:
		if title.text != str(_stored_field(letter, "title")):
			send_title.call(title.text))
	_row("Titre", title)
	_add_choice("Disjoncteur", "breaker", letter, catalog, stored)
	_add_choice("Câble", "cable", letter, catalog, stored)
	var points: Label = Label.new()
	points.text = "%d point(s)" % column.points.size()
	add_child(points)
	if column.spare:
		_button("Retirer ce circuit de réserve", func() -> void: model.remove_spare_circuit(letter))


func _stored_field(letter: String, field: String) -> String:
	if not model.doc().circuits.has(letter):
		return ""
	var stored: Dictionary = model.doc().circuits[letter]
	return str(stored.get(field, ""))


## An OptionButton over the catalogue items of `kind`, the first entry being the pack default.
func _add_choice(label: String, kind: String, letter: String, catalog: Catalog, stored: Dictionary) -> void:
	var picker: OptionButton = OptionButton.new()
	picker.name = "circuit_%s" % kind
	var default_item: Catalog.Item = catalog.item(catalog.default_for(kind))
	picker.add_item("Par défaut (%s)" % (default_item.title if default_item != null else "-"))
	var items: Array[Catalog.Item] = catalog.items_of(kind)
	var chosen: int = 0
	for i: int in items.size():
		picker.add_item(items[i].title)
		if items[i].id == str(stored.get(kind, "")):
			chosen = i + 1
	picker.select(chosen)
	picker.item_selected.connect(func(index: int) -> void:
		var value: String = "" if index == 0 else items[index - 1].id
		model.set_circuit_field(letter, kind, value))
	_row(label, picker)


func _build_device(device_id: String) -> void:
	var catalog: Catalog = Catalog.for_pack(model.doc().pack_ref)
	var catalog_id: String = ""
	for raw: Variant in model.materialized_bus():
		var entry: Dictionary = raw
		if entry["type"] == "device" and entry["id"] == device_id:
			catalog_id = str(entry["catalog"])
	var item: Catalog.Item = catalog.item(catalog_id)
	_subheader("Appareil de la barre")
	var name_label: Label = Label.new()
	name_label.text = item.title if item != null else catalog_id
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(name_label)
	var note: Label = Label.new()
	note.text = "Il protège les circuits qui le suivent, plus loin de l'arrivée."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	_button("Retirer l'appareil", func() -> void: model.remove_bus_device(device_id))


func _build_head_item(item_id: String) -> void:
	var catalog: Catalog = Catalog.for_pack(model.doc().pack_ref)
	var catalog_id: String = ""
	for raw: Variant in model.head_items():
		var entry: Dictionary = raw
		if entry["id"] == item_id:
			catalog_id = str(entry["catalog"])
	var item: Catalog.Item = catalog.item(catalog_id)
	_subheader("Tête de ligne")
	var name_label: Label = Label.new()
	name_label.text = item.title if item != null else catalog_id
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(name_label)
	_button("Plus près de l'arrivée", func() -> void: model.move_head_item(item_id, -1))
	_button("Plus près de la barre", func() -> void: model.move_head_item(item_id, 1))
	_button("Retirer", func() -> void: model.remove_head_item(item_id))


# --- the bus and the head chain -------------------------------------------------------------------


func _build_bus() -> void:
	_header("Barre")
	_button("Ajouter un circuit de réserve", func() -> void: model.add_spare_circuit())
	var catalog: Catalog = Catalog.for_pack(model.doc().pack_ref)
	var devices: Array[Catalog.Item] = catalog.items_of("differential") + catalog.items_of("breaker")
	var picker: OptionButton = OptionButton.new()
	picker.name = "bus_device_choice"
	for item: Catalog.Item in devices:
		picker.add_item(item.title)
	var row: HBoxContainer = HBoxContainer.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	var add: Button = Button.new()
	add.name = "bus_device_add"
	add.text = "Ajouter"
	add.pressed.connect(func() -> void:
		if picker.selected >= 0:
			model.add_bus_device(devices[picker.selected].id))
	row.add_child(add)
	add_child(row)


func _build_head() -> void:
	_header("Tête de ligne")
	var catalog: Catalog = Catalog.for_pack(model.doc().pack_ref)
	var head: Array = model.head_items()
	if head.is_empty():
		var empty: Label = Label.new()
		empty.text = "Aucune : le compteur, le différentiel et le disjoncteur général restent à choisir."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(empty)
		_button("Insérer la tête habituelle", func() -> void: model.insert_usual_head())
	for raw: Variant in head:
		var entry: Dictionary = raw
		var item: Catalog.Item = catalog.item(str(entry["catalog"]))
		var id: String = str(entry["id"])
		_button(item.title if item != null else str(entry["catalog"]), func() -> void: model.select_uni({"kind": "head", "id": id}))
	var every: Array[Catalog.Item] = []
	for kind: String in Catalog.KINDS:
		every.append_array(catalog.items_of(kind))
	var picker: OptionButton = OptionButton.new()
	picker.name = "head_choice"
	for item: Catalog.Item in every:
		picker.add_item(item.title)
	var row: HBoxContainer = HBoxContainer.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	var add: Button = Button.new()
	add.name = "head_add"
	add.text = "Ajouter"
	add.pressed.connect(func() -> void:
		if picker.selected >= 0:
			model.add_head_item(every[picker.selected].id))
	row.add_child(add)
	add_child(row)


# --- widgets ----------------------------------------------------------------------------------------


func _header(text: String) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	add_child(spacer)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", AppTheme.BLUE)
	add_child(label)


func _subheader(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", AppTheme.SUBTEXT0)
	add_child(label)


func _row(text: String, control: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(120, 0)
	label.clip_text = true
	label.tooltip_text = text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	add_child(row)


func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
	return button
