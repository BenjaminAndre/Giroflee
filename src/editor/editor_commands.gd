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
	list.append(Entry.new("edit.snap", "Activer ou désactiver l'accrochage", "", _toggle_snap.bind(model)))
	list.append(Entry.new("tool.select", "Outil de sélection", "Échap", model.set_tool.bind("select")))
	list.append(Entry.new("tool.wall", "Outil mur", "W", model.set_tool.bind("wall")))
	list.append(Entry.new("tool.door", "Outil porte", "D", model.set_tool.bind("door")))
	list.append(Entry.new("tool.window", "Outil fenêtre", "F", model.set_tool.bind("window")))
	list.append(Entry.new("tool.stair", "Outil escalier", "E", model.set_tool.bind("stair")))
	list.append(Entry.new("tool.block", "Outil bloc gris", "S", model.set_tool.bind("block")))
	list.append(Entry.new("tool.text", "Outil texte", "T", model.set_tool.bind("text")))
	return list


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


static func _toggle_snap(model: EditorModel) -> void:
	model.snap_enabled = not model.snap_enabled
	model.notice.emit("Accrochage activé" if model.snap_enabled else "Accrochage désactivé")
	model.changed.emit()
