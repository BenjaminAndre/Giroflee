extends GutTest


func test_version_is_semver() -> void:
	var regex: RegEx = RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	assert_not_null(regex.search(AppInfo.version()), "version '%s' is not MAJOR.MINOR.PATCH" % AppInfo.version())


func test_engine_version_is_pinned() -> void:
	assert_eq(AppInfo.engine_version(), "4.7.2", "SRD pins Godot 4.7.2 (CI, project features)")


func test_strict_typing_warnings_are_errors() -> void:
	# SRD 10.4: untyped declarations and unsafe accesses are errors, not warnings.
	for setting: String in [
		"untyped_declaration",
		"unsafe_property_access",
		"unsafe_method_access",
		"unsafe_cast",
		"unsafe_call_argument",
	]:
		var value: int = ProjectSettings.get_setting("debug/gdscript/warnings/" + setting, 0)
		assert_eq(value, 2, "%s must be set to Error (2)" % setting)


func test_the_project_uses_the_multisampled_2d_renderer() -> void:
	# SRD FR-RENDER-2: the Compatibility renderer has no 2D multisampling, so diagonal walls would be jagged
	assert_eq(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "mobile")
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d")
	assert_eq(msaa, 2, "4x multisampling for 2D")
	var fallback: bool = ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3")
	assert_true(fallback, "machines without Vulkan still start")
