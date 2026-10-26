extends GutTest
## The SRD is the source of truth (CLAUDE.md); a docs patch once silently dropped a whole section.
## These checks make that impossible to miss.

const REQUIRED_HEADINGS: Array[String] = [
	"## 0. Working agreements", "## 1. Vision", "## 5. Domain model", "## 6. Plan-sheet editing",
	"## 7. Modal keyboard model", "## 8. The unifilaire", "## 9. Report", "## 10. Architecture",
	"## 11. Packs and symbol library", "## 12. Look and accessibility", "## 13. Export and persistence",
	"## 14. Licensing", "## 15. Validation and acceptance", "## 16. CI/CD", "## 17. Suggested implementation order",
	"## 18. Decisions log", "## 19. Implementation notes", "### 19.1", "### 19.2", "### 19.3", "### 19.4", "### 19.5", "### 19.6",
]

const REQUIRED_REQUIREMENTS: Array[String] = [
	"FR-PROJ-1", "FR-PREV-1", "FR-HANDLE-1", "FR-RENDER-1", "FR-MENU-1", "FR-TOOLBAR-1", "FR-UI-1", "FR-BRAND-1",
	"FR-LEG-1", "FR-SYM-1", "FR-SYM-9", "FR-EDIT-7", "FR-STACK-1", "FR-QB-1", "FR-FOCUS-1", "ARCH-2", "WA-1", "WA-7",
]


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_srd_has_every_section() -> void:
	var srd: String = _read("res://SRD.md")
	assert_ne(srd, "")
	for heading: String in REQUIRED_HEADINGS:
		assert_true(srd.contains("\n" + heading), "SRD lost its section '%s'" % heading)


func test_srd_has_the_key_requirements() -> void:
	var srd: String = _read("res://SRD.md")
	for id: String in REQUIRED_REQUIREMENTS:
		assert_true(srd.contains(id), "SRD lost requirement %s" % id)


func test_srd_sections_are_in_order() -> void:
	var srd: String = _read("res://SRD.md")
	var last: int = -1
	for heading: String in ["## 18.", "## 19.", "### 19.1", "### 19.2", "### 19.3", "### 19.4", "### 19.5", "### 19.6"]:
		var at: int = srd.find("\n" + heading)
		assert_true(at > last, "%s is out of order or missing" % heading)
		last = at


func test_changelog_has_an_unreleased_section_and_the_released_versions() -> void:
	var log: String = _read("res://CHANGELOG.md")
	assert_true(log.contains("## [Unreleased]"))
	assert_true(log.contains("## [0.1.1]"))
	assert_true(log.contains("## [0.1.0]"))


func test_claude_md_points_to_the_srd() -> void:
	var notes: String = _read("res://CLAUDE.md")
	assert_true(notes.contains("SRD.md"))
	assert_true(notes.contains("CHANGELOG.md"))
