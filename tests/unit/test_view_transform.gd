extends GutTest
@warning_ignore_start("unsafe_call_argument")

var view: ViewTransform


func before_each() -> void:
	view = ViewTransform.new()
	view.viewport = Vector2(800, 600)
	view.zoom = 0.5
	view.center = Vector2(1000, 2000)


func _assert_near(a: Vector2, b: Vector2, msg: String = "") -> void:
	assert_true(a.distance_to(b) < 0.001, "%s: %s vs %s" % [msg, str(a), str(b)])


func test_centre_maps_to_the_middle_of_the_viewport() -> void:
	_assert_near(view.world_to_screen(view.center), Vector2(400, 300))


func test_y_is_flipped_between_world_and_screen() -> void:
	var up: Vector2 = view.world_to_screen(view.center + Vector2(0, 100))
	assert_true(up.y < 300.0, "world up is screen up (smaller y)")
	var right: Vector2 = view.world_to_screen(view.center + Vector2(100, 0))
	assert_true(right.x > 400.0)
	assert_eq(up.y, 300.0 - 100.0 * 0.5)


func test_round_trip() -> void:
	for p: Vector2 in [Vector2(0, 0), Vector2(-5000, 7000), Vector2(123.5, 456.25)]:
		_assert_near(view.screen_to_world(view.world_to_screen(p)), p, "round trip")


func test_pan_follows_the_mouse() -> void:
	var before: Vector2 = Vector2(1200, 1900)
	var screen_before: Vector2 = view.world_to_screen(before)
	view.pan_by_screen(Vector2(30, -20))
	_assert_near(view.world_to_screen(before), screen_before + Vector2(30, -20), "content moved with the drag")


func test_zoom_keeps_the_point_under_the_cursor_fixed() -> void:
	var cursor: Vector2 = Vector2(200, 150)
	var world: Vector2 = view.screen_to_world(cursor)
	view.zoom_at(cursor, 2.0)
	assert_almost_eq(view.zoom, 1.0, 0.0001)
	_assert_near(view.screen_to_world(cursor), world, "anchor stayed under the cursor")
	view.zoom_at(cursor, 0.25)
	_assert_near(view.screen_to_world(cursor), world, "still fixed after zooming out")


func test_zoom_is_clamped() -> void:
	view.zoom_at(Vector2(400, 300), 1.0e9)
	assert_eq(view.zoom, ViewTransform.MAX_ZOOM)
	view.zoom_at(Vector2(400, 300), 1.0e-9)
	assert_eq(view.zoom, ViewTransform.MIN_ZOOM)


func test_visible_rect_matches_the_viewport() -> void:
	var rect: Rect2 = view.visible_world_rect()
	assert_almost_eq(rect.size.x, 800.0 / 0.5, 0.001)
	assert_almost_eq(rect.size.y, 600.0 / 0.5, 0.001)
	_assert_near(rect.get_center(), view.center, "centred")


func test_fit_rect_shows_the_whole_rect() -> void:
	var target: Rect2 = Rect2(0, 0, 21000, 14850)
	view.fit_rect(target, 20.0)
	var visible: Rect2 = view.visible_world_rect()
	assert_true(visible.encloses(target), "page fully visible")
	_assert_near(view.center, target.get_center())


func test_duplicate_is_independent() -> void:
	var copy: ViewTransform = view.duplicate_view()
	copy.zoom = 3.0
	assert_eq(view.zoom, 0.5)


func test_views_follow_the_viewport_until_the_user_adjusts_them() -> void:
	var page: Rect2 = Rect2(0, 0, 21000, 14850)
	var v: ViewTransform = ViewTransform.new()
	v.viewport = Vector2(0, 0)
	v.fit_rect(page)
	assert_false(v.user_adjusted)
	v.pan_by_screen(Vector2(5, 5))
	assert_true(v.user_adjusted)
	var w: ViewTransform = ViewTransform.new()
	w.zoom_at(Vector2(10, 10), 1.5)
	assert_true(w.user_adjusted)
	assert_true(w.duplicate_view().user_adjusted)
