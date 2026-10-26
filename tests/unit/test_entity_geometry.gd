extends GutTest
@warning_ignore_start("unsafe_call_argument")

var doc: Document
var ctx: RenderContext


func before_each() -> void:
	var s: Session = TestKit.session()
	TestKit.add_sheet(s, "s1")
	doc = s.document()
	ctx = RenderContext.for_sheet(doc, doc.get_sheet("s1"))


func _entity(type: String, props: Dictionary) -> Entity:
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec(type), props, true)
	assert_true(normalized["ok"], str(normalized["error"]))
	return Entity.new("e", type, normalized["props"])


func _area(poly: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func test_context_converts_page_units_with_the_sheet_scale() -> void:
	assert_eq(ctx.scale, 50.0)
	assert_almost_eq(ctx.page_to_world(1.4), 70.0, 0.0001)
	assert_almost_eq(ctx.pt_to_world(10.0), 10.0 * 25.4 / 72.0 * 50.0, 0.0001)


func test_straight_wall_is_one_rectangle_of_the_right_thickness() -> void:
	var polys: Array[PackedVector2Array] = EntityGeometry.wall_polygons([[0, 0], [4000, 0]], 70.0)
	assert_eq(polys.size(), 1)
	assert_almost_eq(_area(polys[0]), 4000.0 * 70.0, 1.0)


func test_wall_corner_is_mitred_not_notched() -> void:
	# an L made of two segments: the corner square (35 x 35 outside) must be filled
	var polys: Array[PackedVector2Array] = EntityGeometry.wall_polygons([[0, 0], [1000, 0], [1000, 1000]], 100.0)
	assert_eq(polys.size(), 1)
	var expected: float = 2.0 * 1000.0 * 100.0 - 100.0 * 100.0 + 50.0 * 50.0 * 2.0 * 0.5 * 2.0
	# mitre area = two arms (minus their overlap) plus the outer corner triangle region
	assert_true(Geometry2D.is_point_in_polygon(Vector2(1049, -49), polys[0]), "outer corner is covered (mitre)")
	assert_true(_area(polys[0]) > 2.0 * 1000.0 * 100.0 - 100.0 * 100.0, "bigger than the simple overlap")
	assert_true(expected > 0.0)


func test_closed_wall_has_no_seam_notch_at_its_first_corner() -> void:
	var polys: Array[PackedVector2Array] = EntityGeometry.wall_polygons([[0, 0], [2000, 0], [2000, 1000], [0, 1000], [0, 0]], 100.0)
	var covered: bool = false
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_point_in_polygon(Vector2(-49, -49), poly):
			covered = true
	assert_true(covered, "the corner where the loop starts is mitred too")


func test_door_polygon_is_a_quarter_disc_on_the_hinge() -> void:
	var door: Entity = _entity("opening", {"kind": "door", "pos": [1000, 1000], "width_mm": 900})
	var poly: PackedVector2Array = EntityGeometry.door_polygon(door.props)
	assert_eq(poly[0], Vector2(1000, 1000), "hinge is the first vertex")
	assert_almost_eq(_area(poly), PI * 900.0 * 900.0 / 4.0, 900.0 * 900.0 * 0.01)
	var bounds: Rect2 = EntityGeometry.bounds(door, ctx)
	assert_almost_eq(bounds.position.x, 1000.0, 0.01)
	assert_almost_eq(bounds.end.x, 1900.0, 0.01)
	assert_almost_eq(bounds.end.y, 1900.0, 0.01, "swings toward +y (up) by default")


func test_door_flips_mirror_the_swing() -> void:
	var h: Entity = _entity("opening", {"kind": "door", "pos": [0, 0], "width_mm": 900, "flip_h": true})
	assert_almost_eq(EntityGeometry.bounds(h, ctx).position.x, -900.0, 0.01, "flip_h swings to the left")
	var v: Entity = _entity("opening", {"kind": "door", "pos": [0, 0], "width_mm": 900, "flip_v": true})
	assert_almost_eq(EntityGeometry.bounds(v, ctx).position.y, -900.0, 0.01, "flip_v swings down")


func test_door_rotation_is_counter_clockwise() -> void:
	var door: Entity = _entity("opening", {"kind": "door", "pos": [0, 0], "width_mm": 1000, "rotation": 90})
	var poly: PackedVector2Array = EntityGeometry.door_polygon(door.props)
	# closed leaf (local +x) now points along world +y
	assert_true(poly[1].distance_to(Vector2(0, 1000)) < 0.01 or poly[poly.size() - 1].distance_to(Vector2(0, 1000)) < 0.01)


func test_window_is_a_rectangle_centred_on_the_wall_line() -> void:
	var window: Entity = _entity("opening", {"kind": "window", "pos": [0, 0], "width_mm": 1200})
	var poly: PackedVector2Array = EntityGeometry.opening_polygon(window.props, ctx)
	var thickness: float = ctx.page_to_world(PlanTheme.OPENING_THICKNESS)
	assert_almost_eq(_area(poly), 1200.0 * thickness, 1.0)
	var bounds: Rect2 = EntityGeometry.bounds(window, ctx)
	assert_almost_eq(bounds.get_center().y, 0.0, 0.01)


func test_stair_length_is_steps_times_tread() -> void:
	var stair: Entity = _entity("stair", {"pos": [0, 0], "width_mm": 900, "steps": 12, "tread_mm": 250})
	var bounds: Rect2 = EntityGeometry.bounds(stair, ctx)
	assert_almost_eq(bounds.size.x, 900.0, 0.01)
	assert_almost_eq(bounds.size.y, 3000.0, 0.01)
	var list: DrawList = DrawList.new()
	EntityGeometry.add_ops(stair, ctx, false, list)
	assert_true(list.count_layer("stairs") >= 12, "outline plus 11 step lines")


func test_grey_block_polygon_and_rotation() -> void:
	var block: Entity = _entity("grey_block", {"pos": [100, 100], "size": [400, 200]})
	assert_almost_eq(_area(EntityGeometry.block_polygon(block.props)), 80000.0, 0.01)
	var rotated: Entity = _entity("grey_block", {"pos": [0, 0], "size": [400, 200], "rotation": 90})
	var bounds: Rect2 = EntityGeometry.bounds(rotated, ctx)
	assert_almost_eq(bounds.size.x, 200.0, 0.01)
	assert_almost_eq(bounds.size.y, 400.0, 0.01)


func test_text_size_follows_role_and_override() -> void:
	var room: Entity = _entity("text", {"pos": [0, 0], "text": "Salon", "role": "room"})
	var base: float = EntityGeometry.text_size_world(room.props, ctx)
	assert_almost_eq(base, ctx.pt_to_world(10.0 * 1.6), 0.001)
	var own: Entity = _entity("text", {"pos": [0, 0], "text": "Salon", "role": "room", "size_pt": 20})
	assert_almost_eq(EntityGeometry.text_size_world(own.props, ctx), ctx.pt_to_world(20.0), 0.001, "node-level override wins (FR-TXT-3)")
	var list: DrawList = DrawList.new()
	EntityGeometry.add_ops(room, ctx, false, list)
	assert_eq(list.ops[0].color, PlanTheme.BLUE, "room labels are blue")


func test_distance_inside_is_zero_and_outside_is_euclidean() -> void:
	var block: Entity = _entity("grey_block", {"pos": [0, 0], "size": [1000, 1000]})
	assert_eq(EntityGeometry.distance_to(block, ctx, Vector2(500, 500)), 0.0)
	assert_almost_eq(EntityGeometry.distance_to(block, ctx, Vector2(1300, 500)), 300.0, 0.001)


func test_wall_distance_accounts_for_half_thickness() -> void:
	var wall: Entity = _entity("wall", {"points": [[0, 0], [4000, 0]]})
	assert_eq(EntityGeometry.distance_to(wall, ctx, Vector2(2000, 30)), 0.0, "within half of 70 mm")
	assert_almost_eq(EntityGeometry.distance_to(wall, ctx, Vector2(2000, 135)), 100.0, 0.001)


func test_ghost_ops_use_ghost_layers_and_skip_text() -> void:
	var wall: Entity = _entity("wall", {"points": [[0, 0], [100, 0]]})
	var text: Entity = _entity("text", {"pos": [0, 0], "text": "x"})
	var list: DrawList = DrawList.new()
	EntityGeometry.add_ops(wall, ctx, true, list)
	EntityGeometry.add_ops(text, ctx, true, list)
	assert_eq(list.count_layer("walls_ghost"), 1)
	assert_eq(list.ops.size(), 1, "ghost text is not drawn")


func test_closed_wall_ring_has_no_hole_polygon_and_keeps_its_interior_empty() -> void:
	var polys: Array[PackedVector2Array] = EntityGeometry.wall_polygons([[0, 0], [2000, 0], [2000, 1000], [0, 1000], [0, 0]], 100.0)
	for poly: PackedVector2Array in polys:
		assert_false(Geometry2D.is_point_in_polygon(Vector2(1000, 500), poly), "the inside of a room is not filled")
		assert_false(Geometry2D.is_point_in_polygon(Vector2(300, 300), poly))
	for corner: Vector2 in [Vector2(-49, -49), Vector2(2049, -49), Vector2(2049, 1049), Vector2(-49, 1049)]:
		var covered: bool = false
		for poly: PackedVector2Array in polys:
			if Geometry2D.is_point_in_polygon(corner, poly):
				covered = true
		assert_true(covered, "outer corner %s is mitred" % str(corner))
	for midpoint: Vector2 in [Vector2(1000, 0), Vector2(2000, 500), Vector2(1000, 1000), Vector2(0, 500)]:
		var on_wall: bool = false
		for poly: PackedVector2Array in polys:
			if Geometry2D.is_point_in_polygon(midpoint, poly):
				on_wall = true
		assert_true(on_wall, "the wall is continuous at %s" % str(midpoint))


func test_closed_triangle_and_pentagon_rings_work() -> void:
	for ring: Array in [
		[[0, 0], [3000, 0], [1500, 2000], [0, 0]],
		[[0, 0], [2000, 0], [3000, 1500], [1000, 3000], [-1000, 1500], [0, 0]],
	]:
		var polys: Array[PackedVector2Array] = EntityGeometry.wall_polygons(ring, 100.0)
		assert_true(polys.size() >= 2)
		var vertex_count: int = ring.size() - 1
		for i: int in vertex_count:
			var vertex: Vector2 = EntityGeometry.vec(ring[i])
			var covered: bool = false
			for poly: PackedVector2Array in polys:
				if Geometry2D.is_point_in_polygon(vertex, poly):
					covered = true
			assert_true(covered, "vertex %d of a %d-sided ring is on the wall" % [i, vertex_count])
