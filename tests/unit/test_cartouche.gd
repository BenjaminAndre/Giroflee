extends GutTest
@warning_ignore_start("unsafe_call_argument")
## The cartouche drawn on every sheet from the pack template (SRD FR-CART-1 to FR-CART-4).

var s: Session
var doc: Document


func before_each() -> void:
	s = TestKit.session()
	s.run_one("sheet.add", {"id": "uni", "kind": "unifilaire", "props": Document.unifilaire_props()})
	TestKit.add_sheet(s, "p1", "Rez")
	TestKit.add_sheet(s, "p2", "Étage")
	doc = s.document()


func _put(key: String, value: String) -> void:
	assert_true(s.run_one("doc.set", {"section": "cartouche", "key": key, "value": value}).ok, s.last_error)


func _ops(sheet_id: String, options: Dictionary = {}) -> Array[DrawOp]:
	var out: Array[DrawOp] = []
	for op: DrawOp in PlanRenderer.build(doc, sheet_id, options).ops:
		if op.layer == "cartouche":
			out.append(op)
	return out


func _texts(sheet_id: String) -> Array[String]:
	var out: Array[String] = []
	for op: DrawOp in _ops(sheet_id):
		if op.kind == DrawOp.TEXT:
			out.append(op.text)
	return out


func test_the_template_lists_the_project_fields() -> void:
	assert_eq(CartoucheBuilder.field_keys("belgium"), ["address", "owner", "installer", "inspector", "date", "signature"])


func test_every_sheet_gets_the_labels_and_the_project_values() -> void:
	_put("address", "Rue de l'Exemple 1")
	_put("owner", "Jeanne Exemple")
	for sheet_id: String in ["uni", "p1", "p2"]:
		var texts: Array[String] = _texts(sheet_id)
		for wanted: String in ["Adresse de l'installation", "Propriétaire", "Installateur", "Organisme de contrôle", "Date", "Signature", "Rue de l'Exemple 1", "Jeanne Exemple"]:
			assert_true(texts.has(wanted), "%s shows '%s'" % [sheet_id, wanted])


func test_variables_give_the_sheet_name_and_the_page() -> void:
	assert_true(_texts("p1").has("Rez"))
	assert_true(_texts("p2").has("Étage"))
	assert_true(_texts("uni").has("Unifilaire"))
	assert_true(_texts("uni").has("1/3"), "the unifilaire is the first page")
	assert_true(_texts("p2").has("3/3"))
	s.run_one("sheet.move", {"id": "p2", "index": 1})
	assert_true(_texts("p2").has("2/3"), "pages follow the tab order")


func test_expand_replaces_project_fields() -> void:
	_put("owner", "Jeanne")
	assert_eq(CartoucheBuilder.expand("{project.owner} - {sheet.name}", doc, doc.get_sheet("p1")), "Jeanne - Rez")


func test_the_cartouche_sits_in_the_reserved_band_at_the_bottom() -> void:
	var sheet: Sheet = doc.get_sheet("p1")
	var page: Rect2 = FrameBuilder.page_rect(sheet)
	var den: float = 50.0
	var band_top: float = (297.0 - PlanTheme.CARTOUCHE_HEIGHT) * den
	for op: DrawOp in _ops("p1"):
		for p: Vector2 in op.points:
			assert_gte(p.y, -0.01, "inside the page")
			assert_lte(p.y, band_top + 0.01 + (0.0 if op.kind != DrawOp.TEXT else 0.0), "below the frame, in world y up")
			assert_lte(p.x, page.size.x + 0.01)


func test_long_values_shrink_to_fit_their_cell() -> void:
	_put("address", "x".repeat(200))
	var longest: float = 0.0
	var normal: float = 0.0
	for op: DrawOp in _ops("p1"):
		if op.kind == DrawOp.TEXT and op.text.begins_with("xxx"):
			longest = op.size
		if op.kind == DrawOp.TEXT and op.text == "Rez":
			normal = op.size
	assert_lt(longest, normal)
	assert_gte(longest, normal * 0.5 - 0.001, "never smaller than half")


func test_the_cartouche_goes_with_the_frame_option() -> void:
	assert_gt(_ops("p1").size(), 0)
	assert_eq(_ops("p1", {"frame": false}).size(), 0)


func test_fields_nobody_filled_in_are_empty_not_shown_as_variables() -> void:
	_put("owner", "Jeanne")
	assert_eq(CartoucheBuilder.expand("{project.installer}|{project.owner}", doc, doc.get_sheet("p1")), "|Jeanne")
	for text: String in _texts("p1"):
		assert_false(text.contains("{project"), "no variable leaks onto the page")
