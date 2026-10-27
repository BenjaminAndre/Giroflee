extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Editing the unifilaire and its board (SRD FR-UNI-1, FR-UNI-2, FR-UNI-7): clicking, dragging,
## head chain, bus devices, circuit settings.

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _sym(id: String, type: String, circuit: String, index: int) -> void:
	kit.add("symbol", {"symbol_type": type, "pos": [1000 + index * 300, 1000], "circuit": circuit, "index": index}, id)


func _show() -> UnifilaireLayout:
	kit.model.show_unifilaire()
	return UnifilaireLayout.compute(kit.doc(), kit.model.sheet(), UnifilaireBuilder.derive(kit.doc()))


## World position of a page point (page mm from the top-left corner).
func _world(x: float, y: float) -> Vector2:
	return FrameBuilder.page_to_world(kit.model.sheet(), x, y)


func _bus_letters() -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in kit.model.materialized_bus():
		var entry: Dictionary = raw
		out.append(str(entry.get("letter", "dev:%s" % str(entry.get("id", "")))))
	return out


# --- clicking ---------------------------------------------------------------------------------------


func test_the_unifilaire_has_its_own_select_tool() -> void:
	kit.model.show_unifilaire()
	assert_true(kit.model.tool is UnifilaireTool)
	assert_eq(kit.model.tool_name, "select")
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	assert_true(kit.model.tool is SelectTool, "the plans get the ordinary select tool back")


func test_clicking_a_column_header_selects_the_circuit() -> void:
	_sym("a", "lamp", "A", 1)
	var layout: UnifilaireLayout = _show()
	var region: UnifilaireLayout.Region = layout.region_of("column", "A")
	kit.click(_world(region.rect.get_center().x, layout.y_bus - 12.0))
	assert_eq(kit.model.uni_selection["kind"], "column")
	assert_eq(kit.model.uni_selection["letter"], "A")


func test_selecting_on_the_unifilaire_does_not_modify_the_project() -> void:
	_sym("a", "lamp", "A", 1)
	var layout: UnifilaireLayout = _show()
	var revision: int = kit.model.revision
	var region: UnifilaireLayout.Region = layout.region_of("column", "A")
	kit.click(_world(region.rect.get_center().x, layout.y_bus - 12.0))
	assert_eq(kit.model.revision, revision)


func test_clicking_a_point_shows_its_first_symbol_on_its_plan() -> void:
	var other: String = kit.model.new_id()
	kit.session.run_one("sheet.add", {"id": other, "kind": "plan", "props": {"name": "Étage"}})
	kit.session.run_one("entity.add", {"sheet": other, "items": [{"id": "up", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [500, 500], "circuit": "B", "index": 1}}]})
	var layout: UnifilaireLayout = _show()
	var region: UnifilaireLayout.Region = layout.region_of("point", "B", 1)
	kit.click(_world(region.rect.get_center().x, region.rect.get_center().y))
	assert_eq(kit.model.active_sheet_id, other, "switched to the étage that holds it")
	assert_eq(kit.model.selection, ["up"])
	assert_true(kit.model.tool is SelectTool)


func test_clicking_nothing_clears_the_selection() -> void:
	_sym("a", "lamp", "A", 1)
	var layout: UnifilaireLayout = _show()
	kit.model.select_uni({"kind": "column", "letter": "A"})
	kit.click(_world(layout.x_end, 20.0))
	assert_eq(kit.model.uni_selection, {})


# --- dragging ---------------------------------------------------------------------------------------


func test_dragging_a_column_header_reorders_the_bus_in_one_step() -> void:
	for letter: String in ["A", "B", "C"]:
		_sym(letter, "lamp", letter, 1)
	var layout: UnifilaireLayout = _show()
	var from: UnifilaireLayout.Region = layout.region_of("column", "A")
	var y: float = layout.y_bus - 12.0
	var steps: int = kit.session.history.undo_depth()
	kit.drag(_world(from.rect.get_center().x, y), _world(layout.slot_x[2] + layout.slot_w[2] * 0.8, y))
	assert_eq(_bus_letters(), ["B", "C", "A"])
	assert_eq(kit.session.history.undo_depth(), steps + 1)
	kit.model.undo()
	assert_false(kit.doc().board.has("bus"), "undo restores the implicit order")


func test_dragging_to_the_front_and_a_tiny_drag_that_changes_nothing() -> void:
	for letter: String in ["A", "B", "C"]:
		_sym(letter, "lamp", letter, 1)
	var layout: UnifilaireLayout = _show()
	var third: UnifilaireLayout.Region = layout.region_of("column", "C")
	var y: float = layout.y_bus - 12.0
	kit.drag(_world(third.rect.get_center().x, y), _world(layout.slot_x[0] + 1.0, y))
	assert_eq(_bus_letters(), ["C", "A", "B"])
	var steps: int = kit.session.history.undo_depth()
	var moved: UnifilaireLayout.Region = UnifilaireLayout.compute(kit.doc(), kit.model.sheet(), UnifilaireBuilder.derive(kit.doc())).region_of("column", "A")
	kit.drag(_world(moved.rect.get_center().x, y), _world(moved.rect.get_center().x + 1.0, y))
	assert_eq(kit.session.history.undo_depth(), steps, "a click with a jitter is not a reorder")
	assert_eq(_bus_letters(), ["C", "A", "B"])


func test_the_drop_mark_shows_only_while_dragging() -> void:
	for letter: String in ["A", "B"]:
		_sym(letter, "lamp", letter, 1)
	var layout: UnifilaireLayout = _show()
	var from: UnifilaireLayout.Region = layout.region_of("column", "A")
	var y: float = layout.y_bus - 12.0
	assert_false(kit.model.render_options().has("drop_at"))
	kit.move(_world(from.rect.get_center().x, y))
	kit.press(_world(from.rect.get_center().x, y))
	kit.move(_world(layout.slot_x[1] + 10.0, y))
	assert_true(kit.model.render_options().has("drop_at"))
	kit.release(_world(layout.slot_x[1] + 10.0, y))
	assert_false(kit.model.render_options().has("drop_at"))


func test_a_device_can_be_dragged_along_the_bus_too() -> void:
	_sym("a", "lamp", "A", 1)
	_sym("b", "lamp", "B", 1)
	kit.model.show_unifilaire()
	kit.model.add_bus_device("diff_40a_30ma_a")
	assert_eq(_bus_letters().size(), 3)
	var layout: UnifilaireLayout = UnifilaireLayout.compute(kit.doc(), kit.model.sheet(), UnifilaireBuilder.derive(kit.doc()))
	var device: UnifilaireLayout.Region = layout.region_of("device", "", 0, str(kit.model.uni_selection["id"]))
	kit.drag(_world(device.rect.get_center().x, layout.y_bus - 6.0), _world(layout.slot_x[0] + 1.0, layout.y_bus - 6.0))
	assert_true(_bus_letters()[0].begins_with("dev:"), "the device is now first")


func test_move_bus_item_semantics() -> void:
	for letter: String in ["A", "B", "C", "D"]:
		_sym(letter, "lamp", letter, 1)
	kit.model.move_bus_item(0, 3)
	assert_eq(_bus_letters(), ["B", "C", "A", "D"], "to the slot before D")
	kit.model.move_bus_item(3, 0)
	assert_eq(_bus_letters(), ["D", "B", "C", "A"])
	var steps: int = kit.session.history.undo_depth()
	kit.model.move_bus_item(1, 1)
	kit.model.move_bus_item(1, 2)
	assert_eq(kit.session.history.undo_depth(), steps, "dropping where it already is changes nothing")
	assert_false(kit.model.move_bus_item(9, 0).ok)


# --- spares, devices, head chain --------------------------------------------------------------------


func test_spare_circuits_take_the_first_free_letter_and_can_be_removed() -> void:
	_sym("a", "lamp", "A", 1)
	assert_eq(kit.model.add_spare_circuit(), "B")
	assert_eq(kit.model.add_spare_circuit(), "C")
	assert_eq(_bus_letters(), ["A", "B", "C"])
	kit.model.set_circuit_field("B", "title", "Garage")
	kit.model.remove_spare_circuit("B")
	assert_eq(_bus_letters(), ["A", "C"])
	assert_false(kit.doc().circuits.has("B"), "what was typed for it goes too")
	kit.model.undo()
	assert_eq(_bus_letters(), ["A", "B", "C"], "one undo brings both back")
	assert_eq(kit.doc().circuits["B"]["title"], "Garage")


func test_only_a_spare_circuit_can_be_removed() -> void:
	_sym("a", "lamp", "A", 1)
	kit.model.show_unifilaire()
	kit.model.remove_spare_circuit("A")
	assert_eq(_bus_letters(), ["A"])


func test_bus_devices_are_added_selected_and_removed() -> void:
	kit.model.add_bus_device("diff_40a_30ma_a")
	assert_eq(kit.model.uni_selection["kind"], "device")
	var id: String = kit.model.uni_selection["id"]
	assert_eq(kit.model.materialized_bus().size(), 1)
	kit.model.remove_bus_device(id)
	assert_eq(kit.model.materialized_bus().size(), 0)
	assert_eq(kit.model.uni_selection, {})


func test_the_head_chain_is_edited_item_by_item() -> void:
	kit.model.add_head_item("meter_kwh_27a")
	kit.model.add_head_item("breaker_c40_3ka")
	var first: String = kit.model.head_items()[0]["id"]
	var second: String = kit.model.head_items()[1]["id"]
	kit.model.move_head_item(second, -1)
	assert_eq(kit.model.head_items()[0]["id"], second)
	kit.model.move_head_item(second, -1)
	assert_eq(kit.model.head_items()[0]["id"], second, "already at the feed end")
	kit.model.remove_head_item(first)
	assert_eq(kit.model.head_items().size(), 1)
	kit.model.undo()
	assert_eq(kit.model.head_items().size(), 2)


func test_the_usual_head_is_only_inserted_on_command() -> void:
	assert_eq(kit.model.head_items().size(), 0, "never added by itself")
	kit.model.insert_usual_head()
	var kinds: Array[String] = []
	for raw: Variant in kit.model.head_items():
		var entry: Dictionary = raw
		kinds.append(Catalog.for_pack("belgium").item(str(entry["catalog"])).kind)
	assert_eq(kinds, ["meter", "cable", "differential", "cable", "breaker"])
	assert_eq(kit.session.history.undo_depth(), 1, "one undo step")


# --- circuit settings and cartouche -----------------------------------------------------------------


func test_circuit_fields_are_set_and_reset() -> void:
	_sym("a", "lamp", "A", 1)
	assert_true(kit.model.set_circuit_field("A", "title", "Salon").ok)
	assert_true(kit.model.set_circuit_field("A", "breaker", "breaker_c40_3ka").ok)
	assert_eq(kit.doc().circuits["A"], {"title": "Salon", "breaker": "breaker_c40_3ka"})
	kit.model.set_circuit_field("A", "breaker", "")
	assert_eq(kit.doc().circuits["A"], {"title": "Salon"}, "empty means the pack default again")
	assert_false(kit.model.set_circuit_field("A", "cable", "meter_kwh_27a").ok, "a meter is not a cable")


func test_the_cartouche_fields_are_set_through_commands() -> void:
	assert_true(kit.model.set_cartouche_field("owner", "Jeanne Exemple").ok)
	assert_eq(kit.doc().cartouche["owner"], "Jeanne Exemple")
	kit.model.undo()
	assert_false(kit.doc().cartouche.has("owner"))
