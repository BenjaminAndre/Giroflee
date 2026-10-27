class_name EditorCommands
extends RefCounted
## The commands of the palette (Ctrl+P): every user-level action by its French name, with the
## approved shortcut shown when there is one (SRD FR-KEY-1). Commands for the project file
## (open, save) and the window are provided by the UI, which appends them to this list.


class Entry:
	extends RefCounted
	var id: String = ""
	var title: String = ""
	var shortcut: String = ""
	var action: Callable = Callable()

	func _init(p_id: String, p_title: String, p_shortcut: String, p_action: Callable) -> void:
		id = p_id
		title = p_title
		shortcut = p_shortcut
		action = p_action


## The model-level commands.
static func build(model: EditorModel) -> Array[Entry]:
	var list: Array[Entry] = []
	list.append(Entry.new("sheet.new", "Nouvel étage", "Ctrl+T", model.new_sheet))
	list.append(Entry.new("sheet.duplicate", "Dupliquer l'étage", "", model.duplicate_sheet.bind(false)))
	list.append(Entry.new("sheet.duplicate_full", "Dupliquer l'étage avec les symboles", "", model.duplicate_sheet.bind(true)))
	list.append(Entry.new("sheet.delete", "Supprimer l'étage", "", model.delete_sheet))
	list.append(Entry.new("sheet.rename", "Renommer l'étage", "F2", func() -> void: model.rename_requested.emit(model.active_sheet_id)))
	list.append(Entry.new("sheet.unifilaire", "Aller à l'unifilaire", "", model.show_unifilaire))
	list.append(Entry.new("sheet.move_left", "Déplacer l'étage vers la gauche", "", model.shift_sheet.bind(-1)))
	list.append(Entry.new("sheet.move_right", "Déplacer l'étage vers la droite", "", model.shift_sheet.bind(1)))
	list.append(Entry.new("sheet.next", "Étage suivant", "Ctrl+Tab", model.cycle_sheet.bind(1)))
	list.append(Entry.new("sheet.previous", "Étage précédent", "Ctrl+Maj+Tab", model.cycle_sheet.bind(-1)))
	list.append(Entry.new("sheet.ghost", "Afficher ou masquer l'étage fantôme", "", model.toggle_ghost))
	list.append(Entry.new("sheet.hints", "Afficher ou masquer les repères A4 et A3", "", model.toggle_hints))
	list.append(Entry.new("edit.undo", "Annuler", "Ctrl+Z", model.undo))
	list.append(Entry.new("edit.redo", "Rétablir", "Ctrl+Y", model.redo))
	list.append(Entry.new("edit.copy", "Copier la sélection", "Ctrl+C", model.copy_selection))
	list.append(Entry.new("edit.cut", "Couper la sélection", "Ctrl+X", model.cut_selection))
	list.append(Entry.new("edit.paste", "Coller", "Ctrl+V", model.paste))
	list.append(Entry.new("edit.duplicate", "Dupliquer la sélection", "Ctrl+D", model.duplicate_selection))
	list.append(Entry.new("edit.delete", "Supprimer la sélection", "Suppr", model.delete_selection))
	list.append(Entry.new("edit.select_all", "Tout sélectionner", "Ctrl+A", model.select_all))
	list.append(Entry.new("edit.snap", "Activer ou désactiver l'accrochage", "", toggle_snap.bind(model)))
	list.append(Entry.new("tool.select", "Outil de sélection", "Échap", model.set_tool.bind("select")))
	list.append(Entry.new("tool.wall", "Outil mur", "W", model.set_tool.bind("wall")))
	list.append(Entry.new("tool.door", "Outil porte", "D", model.set_tool.bind("door")))
	list.append(Entry.new("tool.window", "Outil fenêtre", "F", model.set_tool.bind("window")))
	list.append(Entry.new("tool.stair", "Outil escalier", "E", model.set_tool.bind("stair")))
	list.append(Entry.new("tool.block", "Outil bloc gris", "S", model.set_tool.bind("block")))
	list.append(Entry.new("tool.text", "Outil texte", "T", model.set_tool.bind("text")))
	_add_symbol_commands(model, list)
	return list


static func _add_symbol_commands(model: EditorModel, list: Array[Entry]) -> void:
	var library: SymbolLibrary = SymbolLibrary.for_pack(model.doc().pack_ref)
	var keys: Dictionary = {"lamp": "L", "switch": "I", "switch_two_way": "Maj+I", "socket": "P"}
	for type: String in library.order:
		var def: SymbolLibrary.Def = library.def(type)
		list.append(Entry.new("tool.symbol.%s" % type, "Outil %s" % def.title.to_lower(), str(keys.get(type, "")), model.set_tool.bind(type)))
	list.append(Entry.new("edit.pipette", "Pipette : prendre l'outil de l'élément sous le curseur", "A", model.pipette))
	list.append(Entry.new("symbols.relabel", "Replacer les étiquettes", "", model.relabel))
	list.append(Entry.new("symbols.unpin", "Libérer les étiquettes fixées à la main", "", model.unpin_labels))
	list.append(Entry.new("symbols.compact", "Compacter la numérotation", "", model.compact_numbering))
	list.append(Entry.new("anchor.set", "Ancrer à un symbole", "", model.begin_anchor))
	list.append(Entry.new("anchor.detach", "Détacher", "", model.detach_selection))
	list.append(Entry.new("edit.copy_settings", "Copier les propriétés", "", model.copy_settings))
	list.append(Entry.new("edit.paste_settings", "Coller les propriétés", "", model.paste_settings))
	for letter: String in Numbering.circuits_in_use(model.doc()):
		var circuit: String = letter
		list.append(Entry.new("select.circuit.%s" % circuit, "Sélectionner tout le circuit %s" % circuit, "",
			func() -> void: model.select_filtered(Selectors.symbols_of_circuit(model.sheet(), circuit), "circuit %s" % circuit)))
	for type: String in library.order:
		var def: SymbolLibrary.Def = library.def(type)
		var kind: String = type
		var title: String = def.title
		list.append(Entry.new("select.type.%s" % kind, "Sélectionner tous les symboles de type %s" % title.to_lower(), "",
			func() -> void: model.select_filtered(Selectors.symbols_of_type(model.sheet(), kind), title.to_lower())))
	list.append(Entry.new("select.no_circuit", "Sélectionner les symboles sans circuit", "",
		func() -> void: model.select_filtered(Selectors.symbols_without_circuit(model.sheet(), library), "sans circuit")))
	list.append(Entry.new("select.custom_text", "Sélectionner les textes à police ou taille personnalisée", "",
		func() -> void: model.select_filtered(Selectors.custom_texts(model.sheet()), "textes personnalisés")))
	for slot: int in range(1, Quickbar.SLOTS + 1):
		list.append(Entry.new("quickbar.set.%d" % slot, "Barre rapide : mémoriser l'outil actuel dans la case %d" % slot, "", model.store_quickbar.bind(slot)))
	list.append(Entry.new("quickbar.clear", "Barre rapide : vider toutes les cases", "", model.quickbar.clear))


## Indices of `entries` matching `query`, best first. An empty query lists everything.
static func search(entries: Array[Entry], query: String) -> Array[int]:
	var titles: PackedStringArray = PackedStringArray()
	for entry: Entry in entries:
		titles.append(entry.title)
	if query.strip_edges().is_empty():
		var all: Array[int] = []
		for i: int in entries.size():
			all.append(i)
		return all
	return Fuzzy.rank(query, titles)


static func toggle_snap(model: EditorModel) -> void:
	model.snap_enabled = not model.snap_enabled
	model.notice.emit("Accrochage activé" if model.snap_enabled else "Accrochage désactivé")
	model.changed.emit()
