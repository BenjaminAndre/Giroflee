extends GutTest
@warning_ignore_start("unsafe_call_argument")

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _points(entity: Entity) -> Array:
	return entity.props["points"]


# --- wall tool ----------------------------------------------------------------------------

func test_w_selects_the_wall_tool() -> void:
	assert_eq(kit.model.tool_name, "select")
	assert_true(kit.key(KEY_W))
	assert_eq(kit.model.tool_name, "wall")


func test_wall_polyline_snaps_to_the_grid_and_stays_orthogonal() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.click(Vector2(6040, 2230))
	kit.click(Vector2(6130, 5030), false, true)
	var walls: Array[Entity] = kit.entities_of("wall")
	assert_eq(walls.size(), 1, "the double-click finished the wall")
	assert_eq(_points(walls[0]), [[2000, 2000], [6000, 2000], [6000, 5000]], "orthogonal and on the 100 mm grid")


func test_shift_allows_free_angles() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.click(Vector2(5000, 3000), true)
	kit.key(KEY_ENTER)
	assert_eq(_points(kit.entities_of("wall")[0]), [[2000, 2000], [5000, 3000]])


func test_enter_finishes_and_a_single_point_makes_no_wall() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(2000, 2000))
	kit.key(KEY_ENTER)
	assert_eq(kit.entities_of("wall").size(), 0)
	kit.click(Vector2(2000, 2000))
	kit.click(Vector2(4000, 2000))
	kit.key(KEY_ENTER)
	assert_eq(kit.entities_of("wall").size(), 1)
	assert_eq(kit.model.tool_name, "wall", "the tool stays for the next wall")


func test_clicking_the_first_point_closes_the_loop() -> void:
	kit.key(KEY_W)
	for p: Vector2 in [Vector2(1000, 1000), Vector2(5000, 1000), Vector2(5000, 4000), Vector2(1000, 4000), Vector2(1000, 1000)]:
		kit.click(p)
	var walls: Array[Entity] = kit.entities_of("wall")
	assert_eq(walls.size(), 1)
	var points: Array = _points(walls[0])
	assert_eq(points.size(), 5)
	assert_eq(points[0], points[4], "closed ring")


func test_backspace_removes_the_last_point_and_escape_cancels() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(1000, 1000))
	kit.click(Vector2(3000, 1000))
	kit.click(Vector2(3000, 3000))
	kit.key(KEY_BACKSPACE)
	kit.key(KEY_ENTER)
	assert_eq(_points(kit.entities_of("wall")[0]), [[1000, 1000], [3000, 1000]])
	kit.click(Vector2(8000, 8000))
	kit.click(Vector2(9000, 8000))
	kit.key(KEY_ESCAPE)
	assert_eq(kit.entities_of("wall").size(), 1, "escape abandoned the second wall")
	assert_eq(kit.model.tool_name, "wall", "first escape only cancels the gesture")
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.tool_name, "select", "second escape returns to the select tool")


func test_wall_snaps_to_an_existing_vertex() -> void:
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]]})
	kit.key(KEY_W)
	kit.click(Vector2(8020, 2030))
	kit.click(Vector2(8000, 6000))
	kit.key(KEY_ENTER)
	var walls: Array[Entity] = kit.entities_of("wall")
	var second: Array = _points(walls[1] if walls[0].props["points"][0][0] == 2000 else walls[0])
	assert_eq(second[0], [8000, 2000], "snapped onto the vertex, not just the grid")


func test_a_wall_uses_the_project_weight() -> void:
	kit.model.set_config("wall_weight_mm", 2.0)
	kit.key(KEY_W)
	kit.click(Vector2(1000, 1000))
	kit.click(Vector2(3000, 1000))
	kit.key(KEY_ENTER)
	assert_eq(kit.entities_of("wall")[0].props["weight_mm"], 2.0)


func test_one_wall_is_one_undo_step() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(1000, 1000))
	kit.click(Vector2(3000, 1000))
	kit.click(Vector2(3000, 3000), false, true)
	assert_eq(kit.entities_of("wall").size(), 1)
	kit.key(KEY_Z, false, true)
	assert_eq(kit.entities_of("wall").size(), 0)
	kit.key(KEY_Y, false, true)
	assert_eq(kit.entities_of("wall").size(), 1)


func test_undo_while_drawing_cancels_the_gesture_first() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(1000, 1000))
	kit.key(KEY_Z, false, true)
	assert_false(kit.model.tool.is_active())


# --- doors and windows ----------------------------------------------------------------------

func test_a_door_attaches_to_the_wall_and_swings_toward_the_cursor() -> void:
	kit.add("wall", {"points": [[2000, 2000], [8000, 2000]]}, "wall-1")
	kit.key(KEY_D)
	kit.click(Vector2(5000, 2250))
	var doors: Array[Entity] = kit.entities_of("opening")
	assert_eq(doors.size(), 1)
	var door: Entity = doors[0]
	assert_eq(door.props["kind"], "door")
	assert_eq(door.props["host_wall"], "wall-1")
	assert_eq(door.props["pos"], [4550, 2000], "centred on the cursor along the wall: 5000 - 900 / 2")
	assert_eq(door.props["rotation"], 0.0)
	assert_eq(door.props["flip_v"], false, "cursor above the wall: swings up")
	assert_eq(door.props["host_offset_mm"], 2550)


func test_door_swing_side_follows_the_side_of_the_cursor() -> void:
	kit.add("wall", {"points": [[2000, 6000], [8000, 6000]]})
	kit.key(KEY_D)
	kit.click(Vector2(5000, 5800))
	assert_eq(kit.entities_of("opening")[0].props["flip_v"], true, "cursor below: swings down")


func test_a_window_on_a_vertical_wall_is_rotated() -> void:
	kit.add("wall", {"points": [[4000, 1000], [4000, 9000]]})
	kit.key(KEY_F)
	kit.click(Vector2(4100, 5000))
	var window: Entity = kit.entities_of("opening")[0]
	assert_eq(window.props["kind"], "window")
	assert_eq(window.props["rotation"], 90.0)
	assert_eq(window.props["width_mm"], 1200)
	assert_eq(window.props["pos"], [4000, 4400])


func test_free_standing_opening_uses_placement_rotation_and_flips() -> void:
	kit.key(KEY_D)
	kit.key(KEY_H)
	kit.key(KEY_R)
	kit.click(Vector2(10000, 10000))
	var door: Entity = kit.entities_of("opening")[0]
	assert_eq(door.props["flip_h"], true)
	assert_eq(door.props["rotation"], 270.0, "R turns clockwise on screen")
	assert_eq(door.props["host_wall"], "")
	kit.key(KEY_R, true)
	assert_eq(kit.model.place_rotation, 0.0, "Shift+R turns the other way")


func test_opening_tool_stays_active_and_places_repeatedly() -> void:
	kit.key(KEY_F)
	kit.click(Vector2(3000, 3000))
	kit.click(Vector2(6000, 3000))
	assert_eq(kit.entities_of("opening").size(), 2)
	assert_eq(kit.model.tool_name, "window")


# --- stair, block, text ---------------------------------------------------------------------

func test_stair_is_placed_with_the_defaults_and_rotation() -> void:
	kit.key(KEY_E)
	kit.key(KEY_R, true)
	kit.click(Vector2(10000, 4000))
	var stair: Entity = kit.entities_of("stair")[0]
	assert_eq(stair.props["pos"], [10000, 4000])
	assert_eq(stair.props["width_mm"], 900)
	assert_eq(stair.props["steps"], 12)
	assert_eq(stair.props["tread_mm"], 250)
	assert_eq(stair.props["rotation"], 90.0)


func test_block_is_dragged_as_a_rectangle() -> void:
	kit.key(KEY_S)
	kit.drag(Vector2(8000, 5000), Vector2(6000, 3000))
	var block: Entity = kit.entities_of("grey_block")[0]
	assert_eq(block.props["pos"], [6000, 3000], "normalised to the lower-left corner")
	assert_eq(block.props["size"], [2000, 2000])


func test_a_click_without_drag_makes_no_block() -> void:
	kit.key(KEY_S)
	kit.click(Vector2(8000, 5000))
	assert_eq(kit.entities_of("grey_block").size(), 0)


func test_text_tool_requests_an_editor_and_add_text_creates_the_label() -> void:
	watch_signals(kit.model)
	kit.key(KEY_T)
	kit.click(Vector2(5020, 5030))
	assert_signal_emitted(kit.model, "text_requested")
	var params: Array = get_signal_parameters(kit.model, "text_requested")
	assert_eq(params[0], Vector2(5000, 5000))
	assert_eq(params[1], "")
	assert_true(kit.model.add_text(params[0], "Salle à manger", "room").ok)
	var label: Entity = kit.entities_of("text")[0]
	assert_eq(label.props["text"], "Salle à manger")
	assert_eq(label.props["pos"], [5000, 5000])
	assert_eq(kit.model.selection, [label.id])


func test_empty_text_deletes_the_label() -> void:
	var id: String = kit.add("text", {"pos": [0, 0], "text": "x"})
	assert_true(kit.model.set_text(id, "").ok)
	assert_eq(kit.entities_of("text").size(), 0)
