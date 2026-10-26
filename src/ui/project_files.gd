class_name ProjectFiles
extends RefCounted
## Autosave and recovery (SRD FR-FILE-3, FR-CFG-2): every window (a "slot") silently keeps
## its project in user://autosave/, so there is no "save changes?" dialog and a crash loses
## nothing. A sidecar remembers which file the project was saved to.

const DIR: String = "user://autosave"


static func autosave_path(slot: int) -> String:
	return "%s/slot_%d.giroflee" % [DIR, slot]


static func meta_path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


## Writes the autosave of `slot`. Returns "" on success or an error message.
static func write_autosave(doc: Document, slot: int, project_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var error: String = DocumentIO.save_file(doc, autosave_path(slot))
	if not error.is_empty():
		return error
	var meta: FileAccess = FileAccess.open(meta_path(slot), FileAccess.WRITE)
	if meta == null:
		return "cannot write %s" % meta_path(slot)
	meta.store_string(JSON.stringify({"project_path": project_path}))
	meta.close()
	return ""


## {"document": Document or null, "project_path": String}.
static func read_autosave(slot: int) -> Dictionary:
	var out: Dictionary = {"document": null, "project_path": ""}
	if not FileAccess.file_exists(autosave_path(slot)):
		return out
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file(autosave_path(slot))
	if loaded.document == null:
		return out
	out["document"] = loaded.document
	if FileAccess.file_exists(meta_path(slot)):
		var file: FileAccess = FileAccess.open(meta_path(slot), FileAccess.READ)
		var json: JSON = JSON.new()
		if file != null and json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			var meta: Dictionary = json.data
			out["project_path"] = str(meta.get("project_path", ""))
	return out


static func clear_autosave(slot: int) -> void:
	for path: String in [autosave_path(slot), meta_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The smallest slot number without an autosave (used for a new window).
static func next_free_slot() -> int:
	var slot: int = 1
	while FileAccess.file_exists(autosave_path(slot)):
		slot += 1
	return slot
