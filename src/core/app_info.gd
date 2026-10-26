class_name AppInfo
extends RefCounted
## Static facts about the running application (version, engine).

const APP_NAME: String = "Giroflée"


## Application version as stamped by CI into project.godot (config/version).
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Godot engine version, e.g. "4.7.2".
static func engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%s.%s.%s" % [info["major"], info["minor"], info["patch"]]
