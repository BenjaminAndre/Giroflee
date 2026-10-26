extends GutTest
@warning_ignore_start("unsafe_call_argument")
## M2b: Affinity-style resize and rotation handles (FR-HANDLE).

var kit: EditorKit
var ctx: RenderContext


func before_each() -> void:
	kit = EditorKit.create()
	ctx = kit.model.ctx()


func _entity(type: String, props: Dictionary) -> Entity:
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec(type), props, true)
	assert_true(normalized["ok"], str(normalized["error"]))
	return Entity.new("e", type, normalized["props"])


func _near(a: Vector2, b: Vector2, tol: float = 0.01) -> bool:
	return a.distance_to(b) <= tol


# --- TransformBox: handle geometry -------------------------------------------------------------


func test_the_box_has_eight_resize_handles_and_a_rotation_handle() -> void:
	var box: TransformBox = TransformBox.make(Rect2(1000, 2000, 4000, 1000), 0.1)
	var ids: Array[String] = []
	for handle: Dictionary in box.handles:
		ids.append(handle["id"])
	ids.sort()
	assert_eq(ids, ["e", "n", "ne", "nw", "rotate", "s", "se", "sw", "w"])


func test_the_box_sits_outside_the_entities_by_a_screen_margin() -> void:
	var tight: Rect2 = Rect2(1000, 2000, 4000, 1000)
	var box: TransformBox = TransformBox.make(tight, 0.1)
	assert_eq(box.original, tight)
	assert_almost_eq(box.box.position.x, 1000.0 - 100.0, 0.01, "10 px at 0.1 px/mm is 100 mm")
	assert_almost_eq(box.box.end.y, 3000.0 + 100.0, 0.01)
	var zoomed: TransformBox = TransformBox.make(tight, 1.0)
	assert_almost_eq(zoomed.box.position.x, 1000.0 - 10.0, 0.01, "the margin is constant on screen")


func test_handle_positions_follow_the_y_up_convention() -> void:
	var box: TransformBox = TransformBox.make(Rect2(0, 0, 1000, 1000), 1.0)
	assert_true(_near(box.handle_pos("ne"), Vector2(1010, 1010)), "north is +y")
	assert_true(_near(box.handle_pos("sw"), Vector2(-10, -10)))
	assert_true(_near(box.handle_pos("n"), Vector2(500, 1010)))
	assert_true(_near(box.handle_pos("e"), Vector2(1010, 500)))
	assert_true(box.handle_pos("rotate").y > 1010.0, "the rotation handle is above the top edge")
	assert_almost_eq(box.handle_pos("rotate").x, 500.0, 0.01)


func test_hit_finds_the_nearest_handle_within_the_radius() -> void:
	var box: TransformBox = TransformBox.make(Rect2(0, 0, 1000, 1000), 1.0)
	assert_eq(box.hit(Vector2(1012, 1008), 8.0), "ne")
	assert_eq(box.hit(Vector2(500, 500), 8.0), "", "the inside of the box is not a handle")
	assert_eq(box.hit(box.handle_pos("rotate") + Vector2(3, 3), 8.0), "rotate")


func test_a_tiny_selection_still_gets_usable_handles() -> void:
	var box: TransformBox = TransformBox.make(Rect2(500, 500, 0, 0), 0.1)
	assert_true(box.box.size.x >= 100.0, "even a point-sized selection has a box")


# --- TransformBox: what dragging a handle means --------------------------------------------------


func test_corner_drag_scales_from_the_opposite_corner() -> void:
	var original: Rect2 = Rect2(1000, 1000, 2000, 1000)
	var grab: Vector2 = Vector2(3000, 1000)
	var result: Dictionary = TransformBox.drag_scale("se", original, grab, grab + Vector2(1000, -500), false, false)
	assert_eq(result["anchor"], Vector2(1000, 2000), "the north-west corner stays")
	assert_almost_eq(float(result["sx"]), 1.5, 0.0001)
	assert_almost_eq(float(result["sy"]), 1.5, 0.0001)


func test_edge_drag_scales_one_axis_only() -> void:
	var original: Rect2 = Rect2(1000, 1000, 2000, 1000)
	var east: Dictionary = TransformBox.drag_scale("e", original, Vector2(3000, 1500), Vector2(4000, 1700), false, false)
	assert_almost_eq(float(east["sx"]), 1.5, 0.0001)
	assert_eq(float(east["sy"]), 1.0, "the vertical movement is ignored")
	assert_eq(float(east["anchor"].x), 1000.0)
	var north: Dictionary = TransformBox.drag_scale("n", original, Vector2(2000, 2000), Vector2(2300, 2500), false, false)
	assert_eq(float(north["sx"]), 1.0)
	assert_almost_eq(float(north["sy"]), 1.5, 0.0001)
	assert_eq(float(north["anchor"].y), 1000.0, "the south edge stays")


func test_shift_keeps_the_proportions() -> void:
	var original: Rect2 = Rect2(0, 0, 2000, 1000)
	var grab: Vector2 = Vector2(2000, 0)
	var result: Dictionary = TransformBox.drag_scale("se", original, grab, grab + Vector2(2000, -100), true, false)
	assert_almost_eq(float(result["sx"]), 2.0, 0.0001)
	assert_almost_eq(float(result["sy"]), 2.0, 0.0001, "both factors follow the larger drag")


func test_shift_on_an_edge_scales_both_axes_about_the_opposite_edge() -> void:
	var original: Rect2 = Rect2(0, 0, 2000, 1000)
	var result: Dictionary = TransformBox.drag_scale("e", original, Vector2(2000, 500), Vector2(3000, 500), true, false)
	assert_almost_eq(float(result["sx"]), 1.5, 0.0001)
	assert_almost_eq(float(result["sy"]), 1.5, 0.0001)
	assert_eq(result["anchor"], Vector2(0, 500), "the middle of the opposite edge")


func test_alt_scales_from_the_centre() -> void:
	var original: Rect2 = Rect2(0, 0, 2000, 1000)
	var grab: Vector2 = Vector2(2000, 0)
	var result: Dictionary = TransformBox.drag_scale("se", original, grab, grab + Vector2(1000, -500), false, true)
	assert_eq(result["anchor"], Vector2(1000, 500), "the centre of the box stays")
	assert_almost_eq(float(result["sx"]), 2.0, 0.0001, "half-width 1000 becomes 2000")
	assert_almost_eq(float(result["sy"]), 2.0, 0.0001)


func test_scale_never_collapses_or_flips() -> void:
	var original: Rect2 = Rect2(0, 0, 2000, 1000)
	var result: Dictionary = TransformBox.drag_scale("se", original, Vector2(2000, 0), Vector2(-500, 900), false, false)
	assert_true(float(result["sx"]) >= 0.02 and float(result["sy"]) >= 0.02, "dragging past the anchor stops at a tiny positive size")


func test_rotation_is_the_angle_swept_around_the_pivot() -> void:
	var pivot: Vector2 = Vector2(0, 0)
	assert_almost_eq(TransformBox.drag_rotation(pivot, Vector2(0, 1000), Vector2(-1000, 0), false), 90.0, 0.001, "north to west is counter-clockwise +90")
	assert_almost_eq(TransformBox.drag_rotation(pivot, Vector2(0, 1000), Vector2(1000, 0), false), -90.0, 0.001)
	assert_almost_eq(TransformBox.drag_rotation(pivot, Vector2(0, 1000), Vector2(0, -1000), false), 180.0, 0.001)


func test_shift_snaps_the_rotation_to_15_degree_steps() -> void:
	var from: Vector2 = Vector2(0, 1000)
	var to: Vector2 = Vector2(1000, 1000 * tan(deg_to_rad(90.0 - 43.0)))
	var free: float = TransformBox.drag_rotation(Vector2.ZERO, from, to, false)
	var snapped_angle: float = TransformBox.drag_rotation(Vector2.ZERO, from, to, true)
	assert_ne(free, snapped_angle)
	assert_almost_eq(fposmod(snapped_angle, 15.0), 0.0, 0.0001)
	assert_almost_eq(snapped_angle, -45.0, 0.0001)


# --- SelectionTransform: what each entity does ----------------------------------------------------


func test_scaling_a_wall_scales_its_points() -> void:
	var wall: Entity = _entity("wall", {"points": [[0, 0], [1000, 0], [1000, 500]]})
	var result: Dictionary = SelectionTransform.scale([wall], ctx, Vector2(0, 0), 2.0, 3.0)
	var props: Dictionary = result["e"]
	assert_eq(props["points"], [[0, 0], [2000, 0], [2000, 1500]])
	assert_eq(props["weight_mm"], 1.4, "line weight is a page weight and does not scale")


func test_scaling_a_grey_block_scales_position_and_size() -> void:
	var block: Entity = _entity("grey_block", {"pos": [100, 100], "size": [200, 100]})
	var props: Dictionary = SelectionTransform.scale([block], ctx, Vector2(0, 0), 2.0, 3.0)["e"]
	assert_eq(props["pos"], [200, 300])
	assert_eq(props["size"], [400, 300])


func test_scaling_a_rotated_block_maps_the_factors_to_its_own_axes() -> void:
	var block: Entity = _entity("grey_block", {"pos": [0, 0], "size": [200, 100], "rotation": 90})
	var props: Dictionary = SelectionTransform.scale([block], ctx, Vector2(0, 0), 2.0, 1.0)["e"]
	assert_eq(props["size"], [200, 200], "its width runs along world y: only the height doubles")


func test_scaling_an_opening_scales_its_width_and_keeps_its_thickness() -> void:
	var door: Entity = _entity("opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900})
	var props: Dictionary = SelectionTransform.scale([door], ctx, Vector2(0, 0), 2.0, 1.0)["e"]
	assert_eq(props["width_mm"], 1800)
	assert_eq(props["pos"], [2000, 0])


func test_scaling_a_stair_scales_width_and_tread_but_keeps_the_step_count() -> void:
	var stair: Entity = _entity("stair", {"pos": [0, 0], "width_mm": 900, "steps": 12, "tread_mm": 250})
	var props: Dictionary = SelectionTransform.scale([stair], ctx, Vector2(0, 0), 2.0, 1.2)["e"]
	assert_eq(props["width_mm"], 1800)
	assert_eq(props["tread_mm"], 300)
	assert_eq(props["steps"], 12)


func test_scaling_a_text_scales_its_font_size() -> void:
	var text: Entity = _entity("text", {"pos": [100, 100], "text": "Salon", "role": "free"})
	var props: Dictionary = SelectionTransform.scale([text], ctx, Vector2(0, 0), 2.0, 2.0)["e"]
	assert_almost_eq(float(props["size_pt"]), 32.0, 0.01, "16 pt (10 pt base x 1.6 for a free label) doubled")
	assert_eq(props["pos"], [200, 200])
	var own: Entity = _entity("text", {"pos": [0, 0], "text": "x", "size_pt": 20})
	assert_almost_eq(float(SelectionTransform.scale([own], ctx, Vector2.ZERO, 0.5, 0.5)["e"]["size_pt"]), 10.0, 0.01)


func test_scaling_a_symbol_moves_it_without_resizing_it() -> void:
	var symbol: Entity = _entity("symbol", {"symbol_type": "lamp", "pos": [500, 500], "circuit": "A", "index": 1})
	var props: Dictionary = SelectionTransform.scale([symbol], ctx, Vector2(0, 0), 2.0, 2.0)["e"]
	assert_eq(props["pos"], [1000, 1000])
	assert_eq(props["count"], 1)
	assert_false(props.has("size"))


func test_followers_move_but_are_not_resized() -> void:
	var door: Entity = _entity("opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900, "host_wall": "w"})
	var props: Dictionary = SelectionTransform.scale([door], ctx, Vector2(0, 0), 2.0, 2.0, ["e"])["e"]
	assert_eq(props["pos"], [2000, 0])
	assert_eq(props["width_mm"], 900, "a hosted opening keeps its width when its wall is scaled")


func test_rotating_a_wall_rotates_its_points_about_the_pivot() -> void:
	var wall: Entity = _entity("wall", {"points": [[1000, 0], [2000, 0]]})
	var quarter: Dictionary = SelectionTransform.rotate([wall], Vector2(0, 0), 90.0)["e"]
	assert_eq(quarter["points"], [[0, 1000], [0, 2000]])
	var third: Dictionary = SelectionTransform.rotate([wall], Vector2(0, 0), 30.0)["e"]
	assert_eq(third["points"][0], [866, 500])


func test_rotating_other_entities_adds_the_angle_and_moves_the_position() -> void:
	var door: Entity = _entity("opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900, "rotation": 10})
	var props: Dictionary = SelectionTransform.rotate([door], Vector2(0, 0), 90.0)["e"]
	assert_eq(props["pos"], [0, 1000])
	assert_almost_eq(float(props["rotation"]), 100.0, 0.01)
	var back: Dictionary = SelectionTransform.rotate([Entity.new("e", "opening", props)], Vector2(0, 0), -90.0)["e"]
	assert_eq(back["pos"], [1000, 0])
	assert_almost_eq(float(back["rotation"]), 10.0, 0.01)


func test_rotation_wraps_into_0_to_360() -> void:
	var block: Entity = _entity("grey_block", {"pos": [0, 0], "size": [10, 10], "rotation": 350})
	var props: Dictionary = SelectionTransform.rotate([block], Vector2(0, 0), 30.0)["e"]
	assert_almost_eq(float(props["rotation"]), 20.0, 0.01)


func test_hosted_openings_are_added_to_a_transform_as_followers() -> void:
	var s: Session = kit.session
	var wall_id: String = kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	var door_id: String = kit.add("opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900, "host_wall": wall_id, "host_offset_mm": 1000})
	var free_id: String = kit.add("opening", {"kind": "window", "pos": [3000, 0], "width_mm": 1200})
	var expanded: Dictionary = SelectionTransform.with_followers(kit.sheet(), [wall_id])
	var expanded_ids: Array = expanded["ids"]
	assert_eq(expanded_ids, [wall_id, door_id])
	assert_eq(expanded["followers"], [door_id])
	assert_false(expanded_ids.has(free_id))
	assert_not_null(s)


# --- SelectTool: dragging the handles --------------------------------------------------------------


func _select_block() -> String:
	var id: String = kit.add("grey_block", {"pos": [4000, 4000], "size": [2000, 1000]}, "blk")
	kit.model.set_selection([id])
	return id


func _handle(handle_id: String) -> Vector2:
	return SelectTool.box_for(kit.model).handle_pos(handle_id)


func test_a_selection_shows_a_transform_box() -> void:
	assert_null(SelectTool.box_for(kit.model), "nothing selected, no box")
	_select_block()
	var box: TransformBox = SelectTool.box_for(kit.model)
	assert_not_null(box)
	assert_eq(box.original, Rect2(4000, 4000, 2000, 1000))


func test_dragging_a_corner_handle_resizes_a_block_in_one_undo_step() -> void:
	var id: String = _select_block()
	kit.session.history.clear()
	var from: Vector2 = _handle("ne")
	kit.drag(from, from + Vector2(1000, 500))
	var props: Dictionary = kit.doc().find_entity(id).props
	assert_eq(props["pos"], [4000, 4000], "the south-west corner stayed")
	assert_eq(props["size"], [3000, 1500])
	assert_eq(kit.session.history.undo_depth(), 1)
	assert_eq(kit.model.selection, [id], "dragging a handle does not change the selection")
	kit.key(KEY_Z, false, true)
	assert_eq(kit.doc().find_entity(id).props["size"], [2000, 1000])


func test_every_corner_resizes_from_its_opposite() -> void:
	var id: String = _select_block()
	var from: Vector2 = _handle("sw")
	kit.drag(from, from + Vector2(-1000, -500))
	var props: Dictionary = kit.doc().find_entity(id).props
	assert_eq(props["pos"], [3000, 3500])
	assert_eq(props["size"], [3000, 1500])


func test_an_edge_handle_resizes_along_one_axis() -> void:
	var id: String = _select_block()
	var from: Vector2 = _handle("e")
	kit.drag(from, from + Vector2(1000, 700))
	var props: Dictionary = kit.doc().find_entity(id).props
	assert_eq(props["size"], [3000, 1000], "the vertical component of the drag is ignored")
	assert_eq(props["pos"], [4000, 4000])


func test_shift_resizes_proportionally_and_alt_from_the_centre() -> void:
	var id: String = _select_block()
	var from: Vector2 = _handle("ne")
	kit.drag(from, from + Vector2(2000, 100), true)
	assert_eq(kit.doc().find_entity(id).props["size"], [4000, 2000], "Shift: both axes by the larger factor")
	kit.key(KEY_Z, false, true)
	# Alt-drag from the centre, driven through the tool directly (the kit has no Alt-drag helper)
	var tool: SelectTool = kit.model.tool as SelectTool
	var input: ToolInput = ToolInput.make(from, kit.model.tolerance())
	tool.press(kit.model, input)
	var moved: ToolInput = ToolInput.make(from + Vector2(1000, 500), kit.model.tolerance())
	moved.alt = true
	tool.move(kit.model, moved)
	tool.release(kit.model, moved)
	var props: Dictionary = kit.doc().find_entity(id).props
	assert_eq(props["size"], [4000, 2000], "Alt: grows on both sides")
	assert_eq(props["pos"], [3000, 3500], "and the centre stays")


func test_the_resize_is_previewed_live_and_escape_cancels_it() -> void:
	var id: String = _select_block()
	var from: Vector2 = _handle("ne")
	kit.move(from)
	kit.press(from)
	kit.move(from + Vector2(1000, 500))
	var overrides: Dictionary = kit.model.tool.overrides(kit.model)
	assert_true(overrides.has(id))
	assert_eq(kit.doc().find_entity(id).props["size"], [2000, 1000], "nothing committed during the drag")
	kit.key(KEY_ESCAPE)
	kit.release(from + Vector2(1000, 500))
	assert_eq(kit.doc().find_entity(id).props["size"], [2000, 1000])


func test_the_rotation_handle_rotates_about_the_centre() -> void:
	var id: String = _select_block()
	var centre: Vector2 = kit.model.selection_bounds().get_center()
	var from: Vector2 = _handle("rotate")
	kit.drag(from, centre + Vector2(3000, 0))
	var props: Dictionary = kit.doc().find_entity(id).props
	assert_almost_eq(float(props["rotation"]), 270.0, 1.0, "north to east is a clockwise quarter turn")
	var bounds: Rect2 = EntityGeometry.bounds(kit.doc().find_entity(id), kit.model.ctx())
	assert_true(_near(bounds.get_center(), centre, 1.5), "rotated about the centre of the selection")
	assert_almost_eq(bounds.size.x, 1000.0, 2.0)
	assert_almost_eq(bounds.size.y, 2000.0, 2.0)


func test_shift_snaps_the_rotation_handle() -> void:
	var id: String = _select_block()
	var centre: Vector2 = kit.model.selection_bounds().get_center()
	var from: Vector2 = _handle("rotate")
	var target: Vector2 = centre + Vector2(3000, 3000 * tan(deg_to_rad(47.0)) * 0.0 + 3200)
	kit.drag(from, target, true)
	var angle: float = kit.doc().find_entity(id).props["rotation"]
	assert_almost_eq(fposmod(angle, 15.0), 0.0, 0.001, "a multiple of 15 degrees")


func test_resizing_several_entities_scales_them_together() -> void:
	kit.add("grey_block", {"pos": [1000, 1000], "size": [1000, 1000]}, "a")
	kit.add("grey_block", {"pos": [3000, 1000], "size": [1000, 1000]}, "b")
	kit.model.set_selection(["a", "b"])
	var from: Vector2 = _handle("ne")
	kit.drag(from, from + Vector2(3000, 1000))
	var a: Dictionary = kit.doc().find_entity("a").props
	var b: Dictionary = kit.doc().find_entity("b").props
	assert_eq(a["pos"], [1000, 1000])
	assert_eq(a["size"], [2000, 2000])
	assert_eq(b["pos"], [5000, 1000], "the selection scaled as one group (sx = 2)")
	assert_eq(b["size"], [2000, 2000])


func test_scaling_a_wall_carries_its_hosted_door() -> void:
	var wall: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	var door: String = kit.add("opening", {"kind": "door", "pos": [3500, 2000], "width_mm": 900, "host_wall": wall, "host_offset_mm": 1500})
	kit.model.set_selection([wall])
	var from: Vector2 = _handle("e")
	kit.drag(from, from + Vector2(4000, 0))
	assert_eq(kit.doc().find_entity(wall).props["points"], [[2000, 2000], [10000, 2000]])
	var moved: Dictionary = kit.doc().find_entity(door).props
	assert_eq(moved["pos"], [5000, 2000], "the door followed its wall's scaling")
	assert_eq(moved["width_mm"], 900, "and kept its width")


func test_rotating_a_wall_rotates_its_hosted_door_too() -> void:
	var wall: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	var door: String = kit.add("opening", {"kind": "door", "pos": [3500, 2000], "width_mm": 900, "host_wall": wall, "host_offset_mm": 1500})
	kit.model.set_selection([wall])
	var centre: Vector2 = kit.model.selection_bounds().get_center()
	var from: Vector2 = _handle("rotate")
	kit.drag(from, centre + Vector2(-3000, 0))
	assert_almost_eq(float(kit.doc().find_entity(door).props["rotation"]), 90.0, 1.0)


func test_a_single_wall_keeps_its_vertex_handles_and_they_win_over_the_box() -> void:
	var wall: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000], [6000, 5000]]})
	kit.model.set_selection([wall])
	assert_eq(SelectTool.handles_for(kit.model).size(), 3, "vertex handles remain")
	kit.drag(Vector2(6000, 2000), Vector2(7000, 2000))
	assert_eq(kit.doc().find_entity(wall).props["points"], [[2000, 2000], [7000, 2000], [6000, 5000]])


func test_grey_blocks_no_longer_have_their_own_corner_handles() -> void:
	_select_block()
	assert_eq(SelectTool.handles_for(kit.model).size(), 0, "the transform box replaces them")


func test_a_rotated_block_can_be_resized_through_the_box() -> void:
	var id: String = kit.add("grey_block", {"pos": [4000, 4000], "size": [2000, 1000], "rotation": 90}, "rot")
	kit.model.set_selection([id])
	assert_not_null(SelectTool.box_for(kit.model), "rotated blocks get a box too")
	var from: Vector2 = _handle("e")
	kit.drag(from, from + Vector2(500, 0))
	assert_ne(kit.doc().find_entity(id).props["size"], [2000, 1000], "the width changed")


func test_hovering_a_handle_is_reported_for_the_cursor() -> void:
	_select_block()
	kit.move(_handle("nw"))
	assert_eq(kit.model.hover_handle, "nw")
	kit.move(Vector2(1000, 1000))
	assert_eq(kit.model.hover_handle, "")
	kit.move(_handle("rotate"))
	assert_eq(kit.model.hover_handle, "rotate")


func test_dimmed_handles_are_not_offered_for_other_tools() -> void:
	_select_block()
	kit.key(KEY_W)
	kit.move(_handle("ne"))
	assert_eq(kit.model.hover_handle, "", "only the select tool exposes handles")
