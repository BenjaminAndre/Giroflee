extends GutTest
@warning_ignore_start("unsafe_call_argument")
## M2b: Latte theme tokens (FR-UI), icon set (FR-TOOLBAR-4), logo and application icon (FR-BRAND).


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


## WCAG relative luminance (linearised channels), unlike Color.get_luminance().
func _relative_luminance(c: Color) -> float:
	var channels: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		channels.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _close(a: Color, b: Color, tol: float = 0.12) -> bool:test_the_windows_export_embeds_the_icon
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


func _count_near(image: Image, target: Color, tol: float = 0.12) -> int:
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var px: Color = image.get_pixel(x, y)
			if px.a > 0.9 and _close(px, target, tol):
				count += 1
	return count


# --- theme ----------------------------------------------------------------------------------------


func test_latte_tokens_match_the_palette() -> void:
	assert_eq(_hex(AppTheme.BASE), "#eff1f5")
	assert_eq(_hex(AppTheme.MANTLE), "#e6e9ef")
	assert_eq(_hex(AppTheme.CRUST), "#dce0e8")
	assert_eq(_hex(AppTheme.SURFACE0), "#ccd0da")
	assert_eq(_hex(AppTheme.SURFACE1), "#bcc0cc")
	assert_eq(_hex(AppTheme.TEXT), "#4c4f69")
	assert_eq(_hex(AppTheme.SUBTEXT0), "#6c6f85")
	assert_eq(_hex(AppTheme.OVERLAY0), "#9ca0b0")
	assert_eq(_hex(AppTheme.BLUE), "#1e66f5")
	assert_eq(_hex(AppTheme.RED), "#d20f39")
	assert_eq(_hex(AppTheme.PEACH), "#fe640b")
	assert_eq(_hex(AppTheme.GREEN), "#40a02b")


func test_the_whole_interface_is_light() -> void:
	for colour: Color in [AppTheme.BASE, AppTheme.MANTLE, AppTheme.CRUST]:
		assert_true(_relative_luminance(colour) > 0.7, "surfaces are light")
	assert_true(_relative_luminance(AppTheme.TEXT) < 0.15, "text is dark on light")


func test_text_has_enough_contrast_on_every_surface() -> void:
	for surface: Color in [AppTheme.BASE, AppTheme.MANTLE, AppTheme.SURFACE0]:
		var lighter: float = maxf(_relative_luminance(surface), _relative_luminance(AppTheme.TEXT)) + 0.05
		var darker: float = minf(_relative_luminance(surface), _relative_luminance(AppTheme.TEXT)) + 0.05
		assert_true(lighter / darker >= 4.5, "WCAG AA contrast of text on %s" % _hex(surface))


func test_the_theme_styles_the_widgets_the_app_uses() -> void:
	var theme: Theme = AppTheme.build()
	for type_name: String in ["Label", "Button", "PanelContainer", "LineEdit", "TabBar", "PopupMenu", "MenuBar", "CheckBox", "OptionButton", "ItemList"]:
		var themed: bool = theme.get_stylebox_list(type_name).size() > 0 or theme.get_color_list(type_name).size() > 0
		assert_true(themed, "%s is themed" % type_name)
	var button_pressed: StyleBoxFlat = theme.get_stylebox("pressed", "Button") as StyleBoxFlat
	assert_eq(button_pressed.border_color, AppTheme.BLUE, "the active tool is outlined in the accent colour")
	assert_eq(theme.get_color("font_color", "Button"), AppTheme.TEXT)


func test_the_logo_colours_are_not_general_interface_colours() -> void:
	var theme: Theme = AppTheme.build()
	for type_name: String in ["Button", "PanelContainer", "TabBar", "LineEdit"]:
		for style_name: String in theme.get_stylebox_list(type_name):
			var style: StyleBox = theme.get_stylebox(style_name, type_name)
			if style is StyleBoxFlat:
				var flat: StyleBoxFlat = style
				assert_false(_close(flat.bg_color, AppTheme.LOGO_YELLOW, 0.05), "%s/%s" % [type_name, style_name])
				assert_false(_close(flat.bg_color, AppTheme.LOGO_GREEN, 0.05), "%s/%s" % [type_name, style_name])


# --- icons ----------------------------------------------------------------------------------------


func test_every_tool_has_an_icon_at_any_size() -> void:
	for icon_name: String in ["select", "wall", "door", "window", "stair", "block", "text"]:
		assert_true(IconLibrary.names().has(icon_name), icon_name)
		for size: int in [16, 24, 40]:
			var texture: Texture2D = IconLibrary.texture(icon_name, size)
			assert_not_null(texture, "%s at %d px" % [icon_name, size])
			assert_eq(texture.get_width(), size)
			assert_eq(texture.get_height(), size)


func test_icons_are_duotone_in_theme_colours() -> void:
	for icon_name: String in ["select", "wall", "door", "window", "stair", "block", "text"]:
		var image: Image = IconLibrary.texture(icon_name, 48).get_image()
		assert_true(_count_near(image, AppTheme.TEXT, 0.08) > 30, "%s has ink pixels" % icon_name)
	var with_accent: int = 0
	for icon_name: String in ["wall", "door", "window", "stair", "block"]:
		var image: Image = IconLibrary.texture(icon_name, 48).get_image()
		if _count_near(image, AppTheme.BLUE, 0.1) > 10:
			with_accent += 1
	assert_true(with_accent >= 3, "several icons carry the accent colour")


func test_icons_are_crisp_not_upscaled() -> void:
	var small: Image = IconLibrary.texture("wall", 16).get_image()
	var large: Image = IconLibrary.texture("wall", 64).get_image()
	assert_eq(small.get_width(), 16)
	assert_eq(large.get_width(), 64, "re-rendered from the vector at the requested size")


func test_unknown_icons_are_reported_not_crashing() -> void:
	assert_null(IconLibrary.texture("does-not-exist", 24))
	assert_push_error("unknown icon")


func test_icons_are_cached() -> void:
	assert_same(IconLibrary.texture("wall", 24), IconLibrary.texture("wall", 24))


# --- logo / application icon -----------------------------------------------------------------------


func _render(path: String, size: int) -> Image:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "%s exists" % path)
	var image: Image = Image.new()
	var scale: float = float(size) / 100.0
	assert_eq(image.load_svg_from_string(text, scale), OK)
	return image


func test_the_logo_files_exist() -> void:
	for path: String in [
		"res://assets/branding/logo.svg", "res://assets/branding/logo_small.svg",
		"res://assets/branding/icon.png", "res://assets/branding/icon.ico", "res://assets/branding/splash.png",
	]:
		assert_true(FileAccess.file_exists(path), path)


func test_the_logo_is_a_two_tone_flower_with_the_conductor_colours() -> void:
	var image: Image = _render("res://assets/branding/logo.svg", 256)
	var yellow: int = _count_near(image, AppTheme.LOGO_YELLOW, 0.06)
	var green: int = _count_near(image, AppTheme.LOGO_GREEN, 0.06)
	var outline: int = _count_near(image, AppTheme.TEXT, 0.06)
	assert_true(yellow > 4000, "two yellow petals (%d px)" % yellow)
	assert_true(green > 4000, "two green petals (%d px)" % green)
	assert_true(outline > 2000, "the outline in the Latte text colour (%d px)" % outline)
	assert_true(absf(float(yellow) / float(green) - 1.0) < 0.25, "the two colours cover similar areas")
	assert_eq(image.get_pixel(2, 2).a, 0.0, "transparent background")


func test_the_petals_alternate_around_the_centre() -> void:
	var image: Image = _render("res://assets/branding/logo.svg", 200)
	var yellow_quadrants: Array[bool] = []
	# points inside each petal, off the fine inner lines that run along the petal axes
	for corner: Vector2i in [Vector2i(72, 52), Vector2i(128, 52), Vector2i(72, 148), Vector2i(128, 148)]:
		yellow_quadrants.append(_close(image.get_pixel(corner.x, corner.y), AppTheme.LOGO_YELLOW, 0.08))
	assert_eq(yellow_quadrants, [true, false, false, true], "yellow top-left and bottom-right, green on the other diagonal")


func test_the_small_variant_stays_readable_at_32_pixels() -> void:
	var image: Image = _render("res://assets/branding/logo_small.svg", 32)
	assert_eq(image.get_width(), 32)
	assert_true(_count_near(image, AppTheme.LOGO_YELLOW, 0.08) >= 60, "yellow survives at 32 px")
	assert_true(_count_near(image, AppTheme.LOGO_GREEN, 0.08) >= 60, "green survives at 32 px")
	assert_true(_count_near(image, AppTheme.TEXT, 0.08) >= 40, "the outline survives at 32 px")
	var opaque: int = 0
	for y: int in 32:
		for x: int in 32:
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_true(opaque > 32 * 32 * 0.4, "the silhouette fills the icon")


func test_the_small_variant_has_no_fine_inner_lines() -> void:
	var small: String = FileAccess.get_file_as_string("res://assets/branding/logo_small.svg")
	var full: String = FileAccess.get_file_as_string("res://assets/branding/logo.svg")
	assert_true(small.length() < full.length(), "simplified")
	assert_false(small.contains("id=\"veins\""))
	assert_true(full.contains("id=\"veins\""))


func test_the_icon_png_is_square_and_transparent() -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/branding/icon.png"))
	assert_not_null(image)
	assert_eq(image.get_width(), image.get_height())
	assert_true(image.get_width() >= 256)
	assert_eq(image.get_pixel(1, 1).a, 0.0)


func test_the_ico_file_holds_the_standard_sizes() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/branding/icon.ico")
	assert_true(bytes.size() > 1000)
	assert_eq(bytes.decode_u16(0), 0, "reserved")
	assert_eq(bytes.decode_u16(2), 1, "type: icon")
	var count: int = bytes.decode_u16(4)
	assert_true(count >= 6)
	var sizes: Array[int] = []
	for i: int in count:
		var entry: int = 6 + i * 16
		var width: int = bytes[entry]
		sizes.append(256 if width == 0 else width)
		var data_size: int = bytes.decode_u32(entry + 8)
		var offset: int = bytes.decode_u32(entry + 12)
		assert_true(offset + data_size <= bytes.size(), "entry %d lies inside the file" % i)
		assert_eq(bytes[offset], 0x89, "PNG signature inside the entry")
		assert_eq(bytes[offset + 1], 0x50)
	for expected: int in [16, 32, 48, 256]:
		assert_true(sizes.has(expected), "%d px is present" % expected)


func test_the_splash_shows_the_logo_next_to_the_godot_logo_on_a_light_background() -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/branding/splash.png"))
	assert_not_null(image)
	assert_true(image.get_width() >= 800)
	assert_true(_close(image.get_pixel(5, 5), AppTheme.BASE, 0.03), "Latte base background")
	assert_true(_count_near(image, AppTheme.LOGO_YELLOW, 0.08) > 2000, "the Giroflée mark")
	assert_true(_count_near(image, AppTheme.LOGO_GREEN, 0.08) > 2000)
	assert_true(_count_near(image, Color("#478cbf"), 0.08) > 300, "the Godot logo (CC BY 4.0, credited in NOTICE)")


func test_the_project_uses_the_logo_as_icon_and_splash() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/config/icon")), "res://assets/branding/logo.svg")
	assert_eq(str(ProjectSettings.get_setting("application/boot_splash/image")), "res://assets/branding/splash.png")
	assert_true(bool(ProjectSettings.get_setting("application/boot_splash/show_image")))
	var splash_bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_true(_close(splash_bg, AppTheme.BASE, 0.03))


func test_third_party_notice_credits_the_godot_logo_and_catppuccin() -> void:
	var notice: String = FileAccess.get_file_as_string("res://third_party/NOTICE")
	assert_string_contains(notice, "Catppuccin")
	assert_string_contains(notice, "Godot logo")
	assert_string_contains(notice, "CC BY 4.0")


func test_the_window_background_is_light_too() -> void:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	assert_true(_close(clear, AppTheme.MANTLE, 0.01), "no dark strip behind the menus and tabs")


func test_checkboxes_are_plain_rows_not_framed_buttons() -> void:
	var theme: Theme = AppTheme.build()
	for style_name: String in ["normal", "pressed", "hover"]:
		assert_true(theme.get_stylebox(style_name, "CheckBox") is StyleBoxEmpty, "CheckBox/%s" % style_name)
