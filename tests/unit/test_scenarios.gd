extends GutTest
@warning_ignore_start("unsafe_call_argument")
## TEST-2: JSON command scripts run through the CLI, compared with golden project files.
## Regenerate goldens with tools/regen-golden.sh and review the diff.

const SCENARIO_DIR: String = "res://tests/scenarios"
const GOLDEN_DIR: String = "res://tests/golden"
const TMP_DIR: String = "user://scenario_out"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after_each() -> void:
	var dir: DirAccess = DirAccess.open(TMP_DIR)
	if dir != null:
		for file: String in dir.get_files():
			dir.remove(file)


func _scenarios() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(SCENARIO_DIR)
	for file: String in dir.get_files():
		if file.ends_with(".json"):
			names.append(file.get_basename())
	return names


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func test_there_are_scenarios() -> void:
	assert_true(_scenarios().size() >= 1)


func test_every_scenario_reproduces_its_golden_file() -> void:
	for name: String in _scenarios():
		var out: String = "%s/%s.giroflee" % [TMP_DIR, name]
		var cli: Cli = Cli.new()
		var code: int = cli.run(PackedStringArray(["run-script", "%s/%s.json" % [SCENARIO_DIR, name], "--out", out]))
		assert_eq(code, Cli.EXIT_OK, "%s: %s" % [name, "\n".join(cli.output)])
		var golden: String = _read("%s/%s.giroflee" % [GOLDEN_DIR, name])
		assert_ne(golden, "", "%s has no golden file (run tools/regen-golden.sh)" % name)
		assert_eq(_read(out), golden, "%s drifted from its golden file" % name)


func test_every_golden_file_loads_and_is_sound() -> void:
	for name: String in _scenarios():
		var loaded: DocumentIO.LoadResult = DocumentIO.load_file("%s/%s.giroflee" % [GOLDEN_DIR, name])
		assert_eq(loaded.error, "", name)
		assert_eq(loaded.document.check_integrity(), "", name)
		# loading and saving again must not change a single byte
		assert_eq(DocumentIO.to_json(loaded.document), _read("%s/%s.giroflee" % [GOLDEN_DIR, name]), name)


func test_basic_floor_content() -> void:
	var loaded: DocumentIO.LoadResult = DocumentIO.load_file("%s/basic_floor.giroflee" % GOLDEN_DIR)
	var doc: Document = loaded.document
	assert_eq(doc.sheet_order, ["sheet-rez", "sheet-etage", "sheet-cave"], "sheet.move put the cave last")
	assert_false(doc.has_entity("rez-window-1"), "removed in the script")
	assert_eq(TestKit.entity_props(doc, "rez-lamp-1")["pos"], [2250, 2400], "moved by [250, -100]")
	assert_eq(TestKit.entity_props(doc, "rez-room-1")["text"], "Salle de séjour")
	assert_eq(doc.get_sheet("sheet-etage").props["frame_cols"], 0)
	assert_eq(doc.config["font_size_pt"], 11.0)
	assert_eq(doc.cartouche["owner"], "Jeanne Exemple")
