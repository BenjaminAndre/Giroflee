class_name ViewTransform
extends RefCounted
## Mapping between world millimetres (y up) and screen pixels (y down) for one sheet's view.
## Pure maths, so pan and zoom are unit-tested without a window.

const MIN_ZOOM: float = 0.004
const MAX_ZOOM: float = 6.0

## World point shown at the centre of the viewport.
var center: Vector2 = Vector2.ZERO
## Pixels per world millimetre.
var zoom: float = 0.1
var viewport: Vector2 = Vector2(1000.0, 700.0)
## False until the user pans or zooms; until then the view follows the viewport size (so the
## page is fitted once the window has its real size).
var user_adjusted: bool = false


func world_to_screen(world: Vector2) -> Vector2:
	return Vector2(
		(world.x - center.x) * zoom + viewport.x * 0.5,
		viewport.y * 0.5 - (world.y - center.y) * zoom)


func screen_to_world(screen: Vector2) -> Vector2:
	return Vector2(
		(screen.x - viewport.x * 0.5) / zoom + center.x,
		(viewport.y * 0.5 - screen.y) / zoom + center.y)


## Drags the content by `delta` screen pixels (the content follows the mouse).
func pan_by_screen(delta: Vector2) -> void:
	user_adjusted = true
	center += Vector2(-delta.x, delta.y) / zoom


## Multiplies the zoom by `factor`, keeping the world point under `screen_point` fixed.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	user_adjusted = true
	var anchor: Vector2 = screen_to_world(screen_point)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var shifted: Vector2 = screen_to_world(screen_point)
	center += anchor - shifted


func visible_world_rect() -> Rect2:
	var a: Vector2 = screen_to_world(Vector2(0.0, viewport.y))
	var b: Vector2 = screen_to_world(Vector2(viewport.x, 0.0))
	return Rect2(a, b - a)


## Shows `rect` entirely, with `margin_px` around it.
func fit_rect(rect: Rect2, margin_px: float = 24.0) -> void:
	center = rect.get_center()
	var avail: Vector2 = Vector2(maxf(viewport.x - margin_px * 2.0, 10.0), maxf(viewport.y - margin_px * 2.0, 10.0))
	var zx: float = avail.x / maxf(rect.size.x, 1.0)
	var zy: float = avail.y / maxf(rect.size.y, 1.0)
	zoom = clampf(minf(zx, zy), MIN_ZOOM, MAX_ZOOM)


func duplicate_view() -> ViewTransform:
	var copy: ViewTransform = ViewTransform.new()
	copy.center = center
	copy.zoom = zoom
	copy.viewport = viewport
	copy.user_adjusted = user_adjusted
	return copy
