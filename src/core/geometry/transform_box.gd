class_name TransformBox
extends RefCounted
## The bounding box with eight resize handles and one rotation handle shown around a selection,
## as in Affinity (SRD FR-HANDLE). Pure geometry in world mm, y up, plus what dragging a handle
## means. The box sits a constant number of screen pixels outside the selection, so its handles
## never land on top of an entity's own vertex handles.

const MARGIN_PX: float = 10.0
const STEM_PX: float = 28.0
## The smallest scale factor: dragging past the opposite side stops here instead of flipping.
const MIN_FACTOR: float = 0.02
const ROTATION_STEP_DEG: float = 15.0

const CORNERS: Array[String] = ["nw", "ne", "se", "sw"]
const EDGES: Array[String] = ["n", "e", "s", "w"]

## The tight bounds of the selection.
var original: Rect2 = Rect2()
## The drawn box (tight bounds grown by the margin).
var box: Rect2 = Rect2()
## [{"id": String, "pos": Vector2}], resize handles first, "rotate" last.
var handles: Array[Dictionary] = []


static func make(bounds: Rect2, zoom: float) -> TransformBox:
	var result: TransformBox = TransformBox.new()
	var margin: float = MARGIN_PX / zoom
	result.original = bounds
	result.box = bounds.grow(margin)
	var b: Rect2 = result.box
	var c: Vector2 = b.get_center()
	var layout: Dictionary = {
		"nw": Vector2(b.position.x, b.end.y), "n": Vector2(c.x, b.end.y), "ne": Vector2(b.end.x, b.end.y),
		"e": Vector2(b.end.x, c.y), "se": Vector2(b.end.x, b.position.y), "s": Vector2(c.x, b.position.y),
		"sw": Vector2(b.position.x, b.position.y), "w": Vector2(b.position.x, c.y),
	}
	for id: String in ["nw", "n", "ne", "e", "se", "s", "sw", "w"]:
		var pos: Vector2 = layout[id]
		result.handles.append({"id": id, "pos": pos})
	result.handles.append({"id": "rotate", "pos": Vector2(c.x, b.end.y + STEM_PX / zoom)})
	return result


func handle_pos(handle_id: String) -> Vector2:
	for handle: Dictionary in handles:
		if handle["id"] == handle_id:
			var pos: Vector2 = handle["pos"]
			return pos
	return Vector2.ZERO


## Id of the handle within `radius` of `p` (the nearest one), or "".
func hit(p: Vector2, radius: float) -> String:
	var best: String = ""
	var best_distance: float = radius
	for handle: Dictionary in handles:
		var pos: Vector2 = handle["pos"]
		var d: float = p.distance_to(pos)
		if d <= best_distance:
			best_distance = d
			best = handle["id"]
	return best


## The point of `rect` (the tight bounds) that handle `handle_id` stands for.
static func moving_point(handle_id: String, rect: Rect2) -> Vector2:
	var c: Vector2 = rect.get_center()
	match handle_id:
		"nw":
			return Vector2(rect.position.x, rect.end.y)
		"ne":
			return Vector2(rect.end.x, rect.end.y)
		"se":
			return Vector2(rect.end.x, rect.position.y)
		"sw":
			return Vector2(rect.position.x, rect.position.y)
		"n":
			return Vector2(c.x, rect.end.y)
		"s":
			return Vector2(c.x, rect.position.y)
		"e":
			return Vector2(rect.end.x, c.y)
		"w":
			return Vector2(rect.position.x, c.y)
	return c


## What dragging resize handle `handle_id` from `grab` to `cursor` means for a selection whose
## tight bounds are `original`: {"anchor": Vector2, "sx": float, "sy": float}. The handle moves
## by (cursor - grab), so grabbing a handle never makes the selection jump.
## Corner = scale from the opposite corner; edge = one axis only; `shift` keeps the proportions;
## `alt` scales from the centre. Factors never go below MIN_FACTOR.
static func drag_scale(handle_id: String, original: Rect2, grab: Vector2, cursor: Vector2, shift: bool, alt: bool) -> Dictionary:
	var center: Vector2 = original.get_center()
	var moving: Vector2 = moving_point(handle_id, original)
	var target: Vector2 = moving + (cursor - grab)
	var is_edge: bool = EDGES.has(handle_id)
	var moves_x: bool = handle_id in ["ne", "se", "sw", "nw", "e", "w"]
	var moves_y: bool = handle_id in ["ne", "se", "sw", "nw", "n", "s"]
	var anchor: Vector2 = Vector2(original.position.x + original.end.x - moving.x, original.position.y + original.end.y - moving.y)
	if is_edge:
		# an edge handle keeps the centre line of the other axis
		if not moves_x:
			anchor.x = center.x
		if not moves_y:
			anchor.y = center.y
	if alt:
		anchor = center
	var sx: float = 1.0
	var sy: float = 1.0
	if moves_x:
		sx = _factor(target.x - anchor.x, moving.x - anchor.x)
	if moves_y:
		sy = _factor(target.y - anchor.y, moving.y - anchor.y)
	if shift:
		var s: float = sx
		if is_edge:
			s = sx if moves_x else sy
		elif absf(sy - 1.0) > absf(sx - 1.0):
			s = sy
		sx = s
		sy = s
	return {"anchor": anchor, "sx": maxf(sx, MIN_FACTOR), "sy": maxf(sy, MIN_FACTOR)}


## Angle in degrees (counter-clockwise positive, in (-180, 180]) swept around `pivot` when the
## cursor goes from `from` to `to`; `shift` snaps it to 15 degree steps.
static func drag_rotation(pivot: Vector2, from: Vector2, to: Vector2, shift: bool) -> float:
	var a0: float = (from - pivot).angle()
	var a1: float = (to - pivot).angle()
	var degrees: float = rad_to_deg(wrapf(a1 - a0, -PI, PI))
	if degrees < -179.9999:
		degrees += 360.0
	if shift:
		degrees = snappedf(degrees, ROTATION_STEP_DEG)
	return degrees


static func _factor(numerator: float, denominator: float) -> float:
	if absf(denominator) < 0.000001:
		return 1.0
	return numerator / denominator
