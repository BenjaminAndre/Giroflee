extends SceneTree
## Generates the raster branding assets from the SVG sources (assets/branding/):
##   icon.png    256 px mark
##   icon.ico    16, 24, 32, 48, 64, 128 and 256 px (PNG-compressed entries)
##   splash.png  the Giroflée mark above the Godot logo on the Latte background
## Run:  godot --headless --path . -s tools/make_branding.gd
## The generated files are committed; run this again after changing the SVG sources.

const DIR: String = "res://assets/branding"
const BASE: Color = Color(239.0 / 255.0, 241.0 / 255.0, 245.0 / 255.0)
const ICO_SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]
## Up to this size the simplified mark (no fine inner lines) is used.
const SMALL_UP_TO: int = 48


func _init() -> void:
	var logo: String = FileAccess.get_file_as_string("%s/logo.svg" % DIR)
	var small: String = FileAccess.get_file_as_string("%s/logo_small.svg" % DIR)
	var godot: String = FileAccess.get_file_as_string("%s/godot_logo.svg" % DIR)
	if logo.is_empty() or small.is_empty() or godot.is_empty():
		push_error("missing SVG sources in %s" % DIR)
		quit(1)
		return

	var icon: Image = _render(logo, 256)
	icon.save_png(ProjectSettings.globalize_path("%s/icon.png" % DIR))

	var entries: Array[Dictionary] = []
	for size: int in ICO_SIZES:
		var image: Image = _render(small if size <= SMALL_UP_TO else logo, size)
		entries.append({"size": size, "png": image.save_png_to_buffer()})
	_write_ico(ProjectSettings.globalize_path("%s/icon.ico" % DIR), entries)

	_write_splash(logo, godot)
	print("branding assets written")
	quit(0)


## Renders an SVG whose viewBox is 100 units wide at `size` px.
func _render(svg: String, size: int) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(svg, float(size) / 100.0)
	return image


func _write_ico(path: String, entries: Array[Dictionary]) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_16(0)
	file.store_16(1)
	file.store_16(entries.size())
	var offset: int = 6 + 16 * entries.size()
	for entry: Dictionary in entries:
		var size: int = entry["size"]
		var png: PackedByteArray = entry["png"]
		file.store_8(0 if size >= 256 else size)
		file.store_8(0 if size >= 256 else size)
		file.store_8(0)
		file.store_8(0)
		file.store_16(1)
		file.store_16(32)
		file.store_32(png.size())
		file.store_32(offset)
		offset += png.size()
	for entry: Dictionary in entries:
		var png: PackedByteArray = entry["png"]
		file.store_buffer(png)
	file.close()


func _write_splash(logo_svg: String, godot_svg: String) -> void:
	var width: int = 1280
	var height: int = 720
	var splash: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	splash.fill(BASE)
	var mark: Image = _render(logo_svg, 400)
	splash.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), Vector2i((width - mark.get_width()) / 2, 70))
	var godot_image: Image = Image.new()
	godot_image.load_svg_from_string(godot_svg, 1.0)
	var target_width: int = 220
	var target_height: int = roundi(float(godot_image.get_height()) * float(target_width) / float(godot_image.get_width()))
	var scale: float = float(target_width) / float(godot_image.get_width())
	godot_image = Image.new()
	godot_image.load_svg_from_string(godot_svg, scale)
	splash.blend_rect(godot_image, Rect2i(Vector2i.ZERO, godot_image.get_size()), Vector2i((width - godot_image.get_width()) / 2, 540))
	splash.save_png(ProjectSettings.globalize_path("%s/splash.png" % DIR))
	if target_height <= 0:
		push_warning("unexpected Godot logo size")
