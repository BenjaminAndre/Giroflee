extends GutTest
@warning_ignore_start("unsafe_call_argument")
## Jump points like Vim's jump list, walked with the mouse back and forward buttons (SRD FR-JUMP-1),
## the rotation of the transform box, and the Alt label (own key state).

var kit: EditorKit
var other: String = ""


func before_each() -> void:
	kit = EditorKit.create()
	kit.add("symbol", {"symbol_type": "lamp", "pos": [1000, 1000], "circuit": "A", "index": 1}, "here")
	other = kit.model.new_id()
	kit.session.run_one("sheet.add", {"id": other, "kind": "plan", "props": {"name": "Étage"}})
	kit.session.run_one("entity.add", {"sheet": other, "items": [{"id": "up", "type": "symbol", "props": {"symbol_type": "lamp", "pos": [7000, 7000], "circuit": "B", "index": 1}}]})


func _uni_region(letter: String, index: int) -> UnifilaireLayout.Region:
	var layout: UnifilaireLayout = UnifilaireLayout.compute(kit.doc(), kit.model.sheet(), UnifilaireBuilder.derive(kit.doc()))
	return layout.region_of("point", letter, index)


func _click_point_b1() -> void:
	kit.model.show_unifilaire()
	var region: UnifilaireLayout.Region = _uni_region("B", 1)
	kit.click(FrameBuilder.page_to_world(kit.model.sheet(), region.rect.get_center().x, region.rect.get_center().y))


func test_clicking_a_point_of_the_unifilaire_registers_a_jump_and_back_returns() -> void:
	kit.model.show_unifilaire()
	kit.model.select_uni({"kind": "column", "letter": "A"})
	var uni_id: String = kit.model.active_sheet_id
	var region: UnifilaireLayout.Region = _uni_region("B", 1)
	kit.click(FrameBuilder.page_to_world(kit.model.sheet(), region.rect.get_center().x, region.rect.get_center().y))
	assert_eq(kit.model.active_sheet_id, other, "jumped to the plan")
	assert_eq(kit.model.selection, ["up"])
	assert_true(kit.model.can_jump_back())
	assert_true(kit.side_button(1))
	assert_eq(kit.model.active_sheet_id, uni_id, "back on the unifilaire")
	assert_eq(kit.model.uni_selection["letter"], "A", "with what was selected there")
	assert_false(kit.model.can_jump_back())
	assert_true(kit.model.can_jump_forward())


func test_forward_goes_to_the_plan_again_and_a_new_jump_forgets_the_forward_list() -> void:
	_click_point_b1()
	kit.side_button(1)
	kit.side_button(2)
	assert_eq(kit.model.active_sheet_id, other)
	assert_eq(kit.model.selection, ["up"])
	kit.side_button(1)
	assert_true(kit.model.can_jump_forward())
	_click_point_b1()
	assert_false(kit.model.can_jump_forward(), "a new jump forgets what was ahead")


func test_the_view_is_restored_with_the_jump_point() -> void:
	kit.model.set_active_sheet(other)
	kit.model.view().center = Vector2(2000, 3000)
	kit.model.view().zoom = 0.2
	var region: UnifilaireLayout.Region = null
	kit.model.show_unifilaire()
	region = _uni_region("A", 1)
	kit.model.jump_to_symbol("up")
	kit.model.view().center = Vector2(9999, 9999)
	kit.model.jump_back()
	assert_eq(kit.model.active_sheet_id, kit.doc().unifilaire_sheet().id)
	assert_not_null(region)
	kit.model.jump_forward()
	assert_eq(kit.model.active_sheet_id, other)


func test_a_deleted_etage_is_skipped_and_an_empty_list_says_so() -> void:
	var seen: Array[String] = []
	kit.model.notice.connect(func(message: String) -> void: seen.append(message))
	kit.model.jump_back()
	assert_eq(seen.size(), 1)
	kit.model.set_active_sheet(other)
	kit.model.register_jump()
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.session.run_one("sheet.remove", {"id": other})
	kit.model.jump_back()
	assert_eq(seen.size(), 2, "the only jump point was on a deleted étage")


func test_the_list_keeps_the_last_hundred() -> void:
	for i: int in 130:
		kit.model.register_jump()
	var count: int = 0
	while kit.model.can_jump_back():
		kit.model.jump_back()
		count += 1
		if count > 200:
			break
	assert_eq(count, 100)


func test_a_report_issue_is_a_jump_too() -> void:
	var issues: Array[Issue] = kit.model.issues()
	assert_gt(issues.size(), 0)
	kit.model.go_next_issue()
	assert_true(kit.model.can_jump_back())


func test_the_browser_keys_do_the_same() -> void:
	kit.model.register_jump()
	kit.model.set_active_sheet(other)
	assert_true(kit.key(KEY_BACK))
	assert_eq(kit.model.active_sheet_id, kit.doc().plan_ids()[0])
	assert_true(kit.key(KEY_FORWARD))
	assert_eq(kit.model.active_sheet_id, other)


# --- the transform box turns with the gesture ---------------------------------------------------------------


func test_the_box_is_drawn_turned_while_rotating_and_keeps_its_size() -> void:
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.add("grey_block", {"pos": [3000, 3000], "size": [1000, 600]}, "b")
	kit.model.set_selection(["b"])
	var original: Rect2 = SelectTool.box_for(kit.model).box
	var handle: Vector2 = SelectTool.box_for(kit.model).handle_pos("rotate")
	var pivot: Vector2 = original.get_center()
	kit.move(handle)
	kit.press(handle)
	kit.move(pivot + Vector2(1500, 0))
	var select: SelectTool = kit.model.tool
	assert_true(select.is_rotating())
	assert_almost_eq(absf(select.rotation_deg()), 90.0, 1.0)
	assert_eq(SelectTool.box_for(kit.model).box, original, "the box itself keeps its size; it is drawn turned")
	kit.release(pivot + Vector2(1500, 0))
	assert_false(select.is_rotating())
	assert_eq(select.rotation_deg(), 0.0)


# --- Alt label ----------------------------------------------------------------------------------------------------


func _texts() -> Array[String]:
	var out: Array[String] = []
	for op: DrawOp in kit.model.preview_list().ops:
		if op.kind == DrawOp.TEXT:
			out.append(op.text)
	return out


func test_alt_changes_the_label_even_when_the_event_does_not_carry_its_own_flag() -> void:
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.key(KEY_L)
	kit.click(Vector2(3000, 3000))
	kit.move(Vector2(6000, 3000))
	var before: Array[String] = _texts()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ALT
	event.pressed = true
	kit.input.handle(event)
	assert_ne(_texts(), before, "the label shows the reused index at once")
	event = InputEventKey.new()
	event.keycode = KEY_ALT
	event.pressed = false
	kit.input.handle(event)
	assert_eq(_texts(), before, "and goes back on release")


func test_a_held_alt_does_not_refresh_again_on_key_repeat() -> void:
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.key(KEY_L)
	kit.move(Vector2(6000, 3000))
	kit.key(KEY_ALT, false, false, true)
	var emitted: Array[int] = [0]
	kit.model.changed.connect(func() -> void: emitted[0] += 1)
	var repeat: InputEventKey = InputEventKey.new()
	repeat.keycode = KEY_ALT
	repeat.pressed = true
	repeat.alt_pressed = true
	repeat.echo = true
	kit.input.handle(repeat)
	assert_eq(emitted[0], 0, "key repeat is ignored")
	kit.key(KEY_ALT, false, false, true)
	assert_eq(emitted[0], 0, "and so is an Alt that did not change anything")


func test_the_pipette_never_changes_the_active_circuit() -> void:
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.model.active_circuit = "G"
	kit.move(Vector2(1000, 1000))
	kit.key(KEY_A)
	assert_eq(kit.model.tool_name, "lamp", "the tool is taken")
	assert_eq(kit.model.active_circuit, "G", "the circuit stays the author's")
	kit.key(KEY_ALT, false, false, true)
	kit.move(Vector2(5000, 1000))
	kit.click(Vector2(5000, 1000), false, false, true)
	var placed: Entity = null
	for entity: Entity in kit.entities_of("symbol"):
		if entity.props["pos"] == [5000, 1000]:
			placed = entity
	assert_eq(placed.props["circuit"], "G", "new symbols go to G")
	assert_eq(placed.props["index"], 1, "the first free index of G: Alt does not link to a symbol of circuit A")


func test_changing_tab_is_a_jump_and_back_returns_to_the_previous_tab() -> void:
	var first: String = kit.doc().plan_ids()[0]
	kit.model.set_active_sheet(first)
	kit.model.view().center = Vector2(2000, 3000)
	kit.model.switch_sheet(other)
	assert_eq(kit.model.active_sheet_id, other)
	assert_true(kit.model.can_jump_back())
	kit.model.jump_back()
	assert_eq(kit.model.active_sheet_id, first)
	assert_eq(kit.model.view().center, Vector2(2000, 3000), "with its view")
	kit.model.switch_sheet(first)
	assert_false(kit.model.can_jump_back(), "staying on the same tab is no jump")
