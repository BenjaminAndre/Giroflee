class_name EntityMover
extends RefCounted
## Translating entity properties. Used by the `entity.move` command and by drag previews, so
## what the user sees while dragging is exactly what the command will do.


## Copy of `props` shifted by (dx, dy) integer millimetres.
static func shifted_props(type: String, props: Dictionary, dx: int, dy: int) -> Dictionary:
	var moved: Dictionary = props.duplicate(true)
	if type == "wall":
		var points: Array = moved["points"]
		var shifted: Array = []
		for point: Variant in points:
			var p: Array = point
			var px: int = p[0]
			var py: int = p[1]
			shifted.append([px + dx, py + dy])
		moved["points"] = shifted
	else:
		var pos: Array = moved["pos"]
		var x: int = pos[0]
		var y: int = pos[1]
		moved["pos"] = [x + dx, y + dy]
	return moved


## Copy of `props` rotated by exactly 90 degrees about `pivot` (integer mm, so no rounding
## error): counter-clockwise when `ccw`, else clockwise. Walls rotate their points; the other
## entities rotate their position and add the angle to their own `rotation`.
static func rotated_props_90(type: String, props: Dictionary, pivot: Vector2i, ccw: bool) -> Dictionary:
	var out: Dictionary = props.duplicate(true)
	if type == "wall":
		var points: Array = out["points"]
		var turned: Array = []
		for point: Variant in points:
			turned.append(_turn(point, pivot, ccw))
		out["points"] = turned
		return out
	out["pos"] = _turn(out["pos"], pivot, ccw)
	if out.has("rotation"):
		var rotation: float = out["rotation"]
		rotation = fposmod(rotation + (90.0 if ccw else -90.0), 360.0)
		out["rotation"] = rotation
	return out


## Copy of `props` with its own horizontal (or vertical) mirror flag toggled. Entities
## without flags (walls, blocks, texts) are returned unchanged.
static func flipped_props(props: Dictionary, horizontal: bool) -> Dictionary:
	var out: Dictionary = props.duplicate(true)
	var key: String = "flip_h" if horizontal else "flip_v"
	if out.has(key):
		var current: bool = out[key]
		out[key] = not current
	return out


static func can_flip(type: String) -> bool:
	return type == "opening" or type == "stair" or type == "symbol"


static func _turn(point: Variant, pivot: Vector2i, ccw: bool) -> Array:
	var p: Array = point
	var x: int = p[0]
	var y: int = p[1]
	var dx: int = x - pivot.x
	var dy: int = y - pivot.y
	if ccw:
		return [pivot.x - dy, pivot.y + dx]
	return [pivot.x + dy, pivot.y - dx]
