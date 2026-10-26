class_name IconLibrary
extends RefCounted
## The tool icons: duotone SVG files drawn for Giroflée (assets/icons/, CC0), rasterised at the
## size needed so they stay crisp at any UI scale (SRD FR-TOOLBAR-4). They are authored on a
## 24 x 24 grid in the Latte palette (ink and a blue accent).

const NAMES: PackedStringArray = ["select", "wall", "door", "window", "stair", "block", "text"]
const DIR: String = "res://assets/icons"
const GRID: float = 24.0

static var _cache: Dictionary = {}


static func names() -> PackedStringArray:
	return NAMES


## The icon `icon_name` rendered at `size_px` x `size_px`, or null (with an error) when unknown.
static func texture(icon_name: String, size_px: int) -> Texture2D:
	var key: String = "%s@%d" % [icon_name, size_px]
	if _cache.has(key):
		var cached: Texture2D = _cache[key]
		return cached
	var path: String = "%s/%s.svg" % [DIR, icon_name]
	if not NAMES.has(icon_name) or not FileAccess.file_exists(path):
		push_error("unknown icon '%s'" % icon_name)
		return null
	var image: Image = Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(path), float(size_px) / GRID) != OK:
		push_error("icon '%s' could not be rendered" % icon_name)
		return null
	if image.get_width() != size_px:
		image.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
	var made: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = made
	return made
