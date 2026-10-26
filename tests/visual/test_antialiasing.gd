extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD FR-RENDER: walls are antialiased at any angle. Opt-in (needs a display and the Vulkan
## "Mobile" renderer; the OpenGL Compatibility renderer has no 2D multisampling):
##   godot --path . -s addons/gut/gut_cmdln.gd -gexit -gconfig= -gdir=res://tests/visual
## Saves PNGs in user://screenshots/ and counts the soft edge pixels along walls at many angles.

var h: UiHarness


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
	h = await UiHarness.create(self)
	h.window.canvas.show_grid = false
	h.model().set_config("hints", false)


func _capture(name: String) -> Image:
	for i: int in 4:
		await get_tree().process_frame
	var image: Image = h.window.get_viewport().get_texture().get_image()
	image.save_png("user://screenshots/%s.png" % name)
	return image


## Pixels that are neither white page nor black wall: the feathering that smooths an edge.
func _soft_pixels(image: Image, rect: Rect2i) -> int:
	var soft: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var v: float = image.get_pixel(x, y).get_luminance()
			if v > 0.1 and v < 0.9:
				soft += 1
	return soft


func _wall_rect(points: Array) -> Rect2i:
	var a: Vector2 = h.at(EntityGeometry.vec(points[0]))
	var b: Vector2 = h.at(EntityGeometry.vec(points[1]))
	var r: Rect2 = Rect2(a, b - a).abs().grow(6.0)
	return Rect2i(Vector2i(r.position), Vector2i(r.size))


func test_diagonal_walls_have_smooth_edges() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a display")
		return
	var items: Array = []
	var angles: Array = [10, 20, 30, 45, 60]
	for i: int in angles.size():
		var a: float = deg_to_rad(float(angles[i]))
		var x0: int = 2000 + i * 3600
		items.append({"id": "w%d" % i, "type": "wall", "props": {"points": [[x0, 9000], [x0 + roundi(3000.0 * cos(a)), 9000 + roundi(3000.0 * sin(a))]]}})
	items.append({"id": "acute", "type": "wall", "props": {"points": [[2000, 4000], [6000, 4600], [2200, 5200]]}})
	items.append({"id": "tri", "type": "wall", "props": {"points": [[9000, 3500], [13000, 3500], [11000, 6800], [9000, 3500]]}})
	h.model().add_entities(items)
	var image: Image = await _capture("antialiasing")
	var method: String = RenderingServer.get_current_rendering_method()
	gut.p("renderer: %s, msaa_2d setting: %s" % [method, str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d"))])
	for i: int in angles.size():
		var item: Dictionary = items[i]
		var item_props: Dictionary = item["props"]
		var points: Array = item_props["points"]
		var soft: int = _soft_pixels(image, _wall_rect(points))
		gut.p("%d degrees: %d soft edge pixels" % [angles[i], soft])
		assert_true(soft > 25, "a %d degree wall has a feathered edge (%d soft pixels)" % [angles[i], soft])
	var corner_a: Vector2 = h.at(Vector2(9000, 6800))
	var corner_b: Vector2 = h.at(Vector2(13000, 3500))
	var triangle: int = _soft_pixels(image, Rect2i(Vector2i(corner_a), Vector2i(corner_b - corner_a)).abs())
	assert_true(triangle > 40, "a closed triangle is smooth too (%d)" % triangle)


func test_the_project_is_configured_for_multisampled_2d() -> void:
	assert_eq(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "mobile")
	assert_eq(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d")), 2, "4x")
