extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session
var sheet: Sheet
var ctx: RenderContext


func before_each() -> void:
	s = TestKit.session()
	TestKit.add_sheet(s, "s1")
	TestKit.add_wall(s, "s1", "w", [[0, 0], [4000, 0], [4000, 3000]])
	sheet = s.document().get_sheet("s1")
	ctx = RenderContext.for_sheet(s.document(), sheet)


# --- EntityMover --------------------------------------------------------------------------

func test_mover_shifts_walls_and_positions() -> void:
	var wall: Dictionary = EntityMover.shifted_props("wall", {"points": [[0, 0], [10, 5]], "weight_mm": 1.4}, 3, -2)
	assert_eq(wall["points"], [[3, -2], [13, 3]])
	assert_eq(wall["weight_mm"], 1.4)
	var symbol: Dictionary = EntityMover.shifted_props("symbol", {"pos": [1, 1]}, 10, 10)
	assert_eq(symbol["pos"], [11, 11])


func test_mover_does_not_mutate_its_input() -> void:
	var props: Dictionary = {"pos": [1, 1]}
	EntityMover.shifted_props("text", props, 5, 5)
	assert_eq(props["pos"], [1, 1])


# --- SnapEngine ---------------------------------------------------------------------------

func test_snaps_to_the_grid_by_default() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(1230, 480), 50.0)
	assert_eq(r.pos, Vector2(1200, 500), "grid step is 100 mm")
	assert_eq(r.kind, SnapEngine.GRID)


func test_object_points_win_over_the_grid_within_the_tolerance() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(3980, 30), 60.0)
	assert_eq(r.pos, Vector2(4000, 0))
	assert_eq(r.kind, SnapEngine.VERTEX)
	assert_eq(r.source_id, "w")


func test_midpoints_are_snap_targets() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(2010, 20), 60.0)
	assert_eq(r.pos, Vector2(2000, 0))
	assert_eq(r.kind, SnapEngine.MIDPOINT)


func test_outside_the_tolerance_the_grid_is_used() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(3500, 40), 30.0)
	assert_eq(r.kind, SnapEngine.GRID)


func test_excluded_entities_are_not_snap_targets() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(3990, 10), 60.0, {"exclude": ["w"]})
	assert_eq(r.kind, SnapEngine.GRID)


func test_snapping_can_be_disabled() -> void:
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(1234.6, 480.2), 60.0, {"grid": false, "objects": false})
	assert_eq(r.pos, Vector2(1235, 480), "rounded to whole millimetres only")
	assert_eq(r.kind, SnapEngine.NONE)


func test_grid_step_follows_the_sheet_setting() -> void:
	s.run_one("sheet.update", {"id": "s1", "props": {"grid_step_mm": 250}})
	var r: SnapEngine.Result = SnapEngine.snap(sheet, Vector2(1100, 1100), 10.0)
	assert_eq(r.pos, Vector2(1000, 1000))


func test_orthogonal_picks_the_dominant_axis() -> void:
	assert_eq(SnapEngine.orthogonal(Vector2(0, 0), Vector2(1000, 120)), Vector2(1000, 0))
	assert_eq(SnapEngine.orthogonal(Vector2(0, 0), Vector2(-90, 700)), Vector2(0, 700))


# --- WallLocator --------------------------------------------------------------------------

func test_locate_finds_the_nearest_segment_with_direction_and_side() -> void:
	var hit: WallLocator.Hit = WallLocator.locate(sheet, Vector2(1500, 200), 400.0)
	assert_not_null(hit)
	assert_eq(hit.wall_id, "w")
	assert_eq(hit.point, Vector2(1500, 0))
	assert_almost_eq(hit.angle_deg, 0.0, 0.001)
	assert_eq(hit.side, 1, "above the wall = left of +x")
	assert_almost_eq(hit.offset_mm, 1500.0, 0.001)
	var below: WallLocator.Hit = WallLocator.locate(sheet, Vector2(1500, -200), 400.0)
	assert_eq(below.side, -1)


func test_locate_on_the_second_segment_adds_the_first_segments_length() -> void:
	var hit: WallLocator.Hit = WallLocator.locate(sheet, Vector2(4100, 1000), 400.0)
	assert_eq(hit.point, Vector2(4000, 1000))
	assert_almost_eq(hit.angle_deg, 90.0, 0.001)
	assert_almost_eq(hit.offset_mm, 5000.0, 0.001)


func test_locate_respects_the_tolerance() -> void:
	assert_null(WallLocator.locate(sheet, Vector2(1500, 900), 400.0))


# --- HitTest ------------------------------------------------------------------------------

func test_pick_prefers_walls_over_blocks_and_text_over_walls() -> void:
	TestKit.add_entity(s, "s1", "block", "grey_block", {"pos": [-500, -500], "size": [2000, 2000]})
	assert_eq(HitTest.pick(sheet, ctx, Vector2(500, 0), 20.0), "w", "wall above the block")
	assert_eq(HitTest.pick(sheet, ctx, Vector2(500, 800), 20.0), "block")
	TestKit.add_entity(s, "s1", "label", "text", {"pos": [400, -50], "text": "Salon"})
	assert_eq(HitTest.pick(sheet, ctx, Vector2(450, 0), 20.0), "label", "text is on top")


func test_pick_returns_empty_when_nothing_is_near() -> void:
	assert_eq(HitTest.pick(sheet, ctx, Vector2(2000, 2000), 20.0), "")


func test_pick_tolerance_is_in_world_mm() -> void:
	assert_eq(HitTest.pick(sheet, ctx, Vector2(2000, 150), 20.0), "")
	assert_eq(HitTest.pick(sheet, ctx, Vector2(2000, 150), 200.0), "w")


func test_pick_can_exclude_entities() -> void:
	assert_eq(HitTest.pick(sheet, ctx, Vector2(2000, 0), 20.0, ["w"]), "")


func test_box_selection_touches_bounds() -> void:
	TestKit.add_entity(s, "s1", "far", "grey_block", {"pos": [9000, 9000], "size": [100, 100]})
	var hit: Array[String] = HitTest.in_rect(sheet, ctx, Rect2(3900, 1000, 300, 300))
	assert_eq(hit, ["w"], "touches the wall's second segment")
	var all: Array[String] = HitTest.in_rect(sheet, ctx, Rect2(-100, -100, 20000, 20000))
	assert_eq(all, ["far", "w"])


func test_box_selection_accepts_a_rect_dragged_in_any_direction() -> void:
	var flipped: Array[String] = HitTest.in_rect(sheet, ctx, Rect2(4200, 1300, -300, -300))
	assert_eq(flipped, ["w"])


# --- remove unhosts openings ----------------------------------------------------------------

func test_removing_a_wall_frees_its_hosted_openings() -> void:
	TestKit.add_entity(s, "s1", "door", "opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900, "host_wall": "w", "host_offset_mm": 1000})
	assert_true(s.run_one("entity.remove", {"sheet": "s1", "ids": ["w"]}).ok)
	var door: Dictionary = TestKit.entity_props(s.document(), "door")
	assert_eq(door["host_wall"], "")
	assert_eq(door["host_offset_mm"], 0)
	assert_eq(door["pos"], [1000, 0], "stays where it is")
	assert_true(s.undo())
	assert_eq(TestKit.entity_props(s.document(), "door")["host_wall"], "w", "undo restores the link")


func test_rotation_by_90_is_exact_and_reversible() -> void:
	var wall: Dictionary = {"points": [[1000, 1000], [3000, 1000], [3000, 2500]], "weight_mm": 1.4}
	var pivot: Vector2i = Vector2i(2000, 1500)
	var ccw: Dictionary = EntityMover.rotated_props_90("wall", wall, pivot, true)
	assert_eq(ccw["points"], [[2500, 500], [2500, 2500], [1000, 2500]])
	var back: Dictionary = EntityMover.rotated_props_90("wall", ccw, pivot, false)
	assert_eq(back["points"], wall["points"])
	var cw: Dictionary = EntityMover.rotated_props_90("wall", wall, pivot, false)
	assert_eq(cw["points"][0], [1500, 2500])


func test_rotating_a_positioned_entity_updates_its_angle_modulo_360() -> void:
	var props: Dictionary = {"pos": [1000, 0], "rotation": 270.0}
	var ccw: Dictionary = EntityMover.rotated_props_90("grey_block", props, Vector2i(0, 0), true)
	assert_eq(ccw["pos"], [0, 1000])
	assert_eq(ccw["rotation"], 0.0, "270 + 90 wraps to 0")
	var cw: Dictionary = EntityMover.rotated_props_90("grey_block", {"pos": [0, 0], "rotation": 0.0}, Vector2i(0, 0), false)
	assert_eq(cw["rotation"], 270.0, "0 - 90 wraps to 270")


func test_flipped_props_toggles_only_flags_that_exist() -> void:
	var door: Dictionary = {"flip_h": false, "flip_v": true}
	assert_eq(EntityMover.flipped_props(door, true)["flip_h"], true)
	assert_eq(EntityMover.flipped_props(door, false)["flip_v"], false)
	assert_eq(EntityMover.flipped_props({"points": []}, true), {"points": []}, "walls have no flags")
	assert_true(EntityMover.can_flip("opening") and EntityMover.can_flip("stair") and EntityMover.can_flip("symbol"))
	assert_false(EntityMover.can_flip("wall") or EntityMover.can_flip("text") or EntityMover.can_flip("grey_block"))


func test_clipboard_round_trip_helpers() -> void:
	var text: String = Clipboard.serialize(sheet, ["w"])
	assert_true(text.begins_with("{"))
	var parsed: Dictionary = Clipboard.parse(text)
	assert_true(parsed["ok"])
	assert_eq(parsed["origin"], [0, 0])
	var items: Array = parsed["items"]
	assert_eq(items.size(), 1)
	assert_eq(Clipboard.serialize(sheet, []), "", "nothing selected: nothing to copy")
	assert_false(Clipboard.parse("{\"format\": \"other\"}")["ok"])
	assert_false(Clipboard.parse("")["ok"])
	var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(500, 500), IdGenerator.new(3))
	var new_ids: Array = built["new_ids"]
	assert_eq(new_ids.size(), 1)
	assert_ne(new_ids[0], "w")
	var built_items: Array = built["items"]
	var first_props: Dictionary = built_items[0]["props"]
	assert_eq(first_props["points"][0], [500, 500])


func test_pasted_symbols_get_index_zero_until_m3() -> void:
	TestKit.add_symbol(s, "s1", "sym", [100, 100], "A", 3)
	var parsed: Dictionary = Clipboard.parse(Clipboard.serialize(sheet, ["sym"]))
	var built: Dictionary = Clipboard.to_add_items(parsed, Vector2i(0, 0), IdGenerator.new(3))
	var built_items: Array = built["items"]
	var props: Dictionary = built_items[0]["props"]
	assert_eq(props["index"], 0)
	assert_eq(props["circuit"], "A", "the circuit is kept")
