extends GutTest
## Every script under src/ must parse under the strict typing rules.


func test_all_source_scripts_load() -> void:
	var paths: Array[String] = []
	_collect("res://src", paths)
	assert_true(paths.size() > 0, "found source scripts")
	for path: String in paths:
		var script: Resource = load(path)
		assert_not_null(script, "%s failed to load" % path)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
