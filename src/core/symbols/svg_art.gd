class_name SvgArt
extends RefCounted
## Symbol artwork: the supported subset of SVG (SRD 11.3) turned into flat vector shapes.
##
## Only what every backend (screen, SVG, PDF, PNG) can draw identically is accepted: g, path
## (M L H V C S Q A Z, absolute and relative), line, polyline, polygon, rect, circle, ellipse; the
## attributes fill, stroke, stroke-width, stroke-linecap, stroke-linejoin and fill-opacity; and
## transform on g only (translate, rotate, scale). Anything else is refused with a message, so a
## custom symbol can never half-render. Coordinates stay in the file's own units (y down).

const CURVE_SEGMENTS: int = 16
const QUAD_SEGMENTS: int = 12
const CIRCLE_SEGMENTS: int = 32
const ARC_STEP: float = PI / 18.0

const STYLE_ATTRS: Array[String] = ["fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "fill-opacity"]
const GEOMETRY_ATTRS: Dictionary = {
	"path": ["d"],
	"line": ["x1", "y1", "x2", "y2"],
	"polyline": ["points"],
	"polygon": ["points"],
	"rect": ["x", "y", "width", "height"],
	"circle": ["cx", "cy", "r"],
	"ellipse": ["cx", "cy", "rx", "ry"],
}


class Shape:
	extends RefCounted
	var points: PackedVector2Array = PackedVector2Array()
	var closed: bool = false
	var stroke: bool = false
	var stroke_width: float = 1.0
	## Color, or null for "currentColor" (the colour the renderer chooses).
	var stroke_color: Variant = null
	var fill: bool = false
	var fill_color: Variant = null
	var fill_opacity: float = 1.0
	var linecap: String = "butt"
	var linejoin: String = "miter"


var shapes: Array[Shape] = []
var view_box: Rect2 = Rect2()
## "" when the file was accepted.
var error: String = ""


func ok() -> bool:
	return error.is_empty()


## Bounding box of all shape points (stroke width ignored); Rect2() when there are none.
func bounds() -> Rect2:
	var rect: Rect2 = Rect2()
	var first: bool = true
	for shape: Shape in shapes:
		for p: Vector2 in shape.points:
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


static func parse(text: String) -> SvgArt:
	var art: SvgArt = SvgArt.new()
	var parser: XMLParser = XMLParser.new()
	if text.strip_edges().is_empty() or parser.open_buffer(text.to_utf8_buffer()) != OK:
		return art._fail("not a readable SVG file")
	var stack: Array[Dictionary] = []
	var seen_root: bool = false
	while true:
		var status: int = parser.read()
		if status == ERR_FILE_EOF:
			break
		if status != OK:
			return art._fail("malformed XML")
		var kind: int = parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			var name: String = parser.get_node_name()
			if not seen_root:
				if name != "svg":
					return art._fail("the root element must be <svg>")
				seen_root = true
				var root_error: String = art._read_root(parser)
				if not root_error.is_empty():
					return art._fail(root_error)
				stack.append(art._root_context())
				if parser.is_empty():
					stack.pop_back()
				continue
			var element_error: String = art._element(parser, name, stack)
			if not element_error.is_empty():
				return art._fail(element_error)
			if name == "g" and not parser.is_empty():
				continue
			if name == "g" and parser.is_empty():
				stack.pop_back()
		elif kind == XMLParser.NODE_ELEMENT_END:
			if not stack.is_empty():
				stack.pop_back()
	if not seen_root:
		return art._fail("the root element must be <svg>")
	return art


func _fail(message: String) -> SvgArt:
	error = message
	shapes.clear()
	return self


func _root_context() -> Dictionary:
	return {
		"xf": Transform2D.IDENTITY,
		"fill": "black", "stroke": "none", "stroke-width": 1.0,
		"stroke-linecap": "butt", "stroke-linejoin": "miter", "fill-opacity": 1.0,
	}


func _read_root(parser: XMLParser) -> String:
	var has_box: bool = false
	for i: int in parser.get_attribute_count():
		var attr: String = parser.get_attribute_name(i)
		var value: String = parser.get_attribute_value(i)
		match attr:
			"xmlns", "width", "height", "version":
				pass
			"viewBox":
				var parts: PackedStringArray = value.replace(",", " ").split(" ", false)
				if parts.size() != 4:
					return "viewBox needs four numbers"
				for part: String in parts:
					if not part.is_valid_float():
						return "viewBox needs four numbers"
				view_box = Rect2(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
				has_box = true
			_:
				return "unsupported attribute '%s' on <svg>" % attr
	if not has_box:
		return "the <svg> element needs a viewBox"
	return ""


## Handles one element inside the root. Groups push a context on `stack` (popped at their end tag).
func _element(parser: XMLParser, name: String, stack: Array[Dictionary]) -> String:
	if name == "svg":
		return "nested <svg> elements are not supported"
	if stack.is_empty():
		return "content after the end of <svg>"
	var attrs: Dictionary = {}
	for i: int in parser.get_attribute_count():
		attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
	var parent: Dictionary = stack.back()
	if name == "g":
		for attr: String in attrs.keys():
			if attr != "id" and attr != "transform" and not STYLE_ATTRS.has(attr):
				return "unsupported attribute '%s' on <g>" % attr
		var group: Dictionary = parent.duplicate()
		var style_error: String = _apply_style(attrs, group)
		if not style_error.is_empty():
			return style_error
		if attrs.has("transform"):
			var matrix: Dictionary = _parse_transform(str(attrs["transform"]))
			if not str(matrix["error"]).is_empty():
				return str(matrix["error"])
			var local: Transform2D = matrix["xf"]
			var inherited: Transform2D = parent["xf"]
			group["xf"] = inherited * local
		stack.append(group)
		return ""
	if not GEOMETRY_ATTRS.has(name):
		return "unsupported element <%s>" % name
	var allowed: Array = GEOMETRY_ATTRS[name]
	for attr: String in attrs.keys():
		if attr == "transform":
			return "transform is only allowed on <g> (found on <%s>)" % name
		if attr != "id" and not STYLE_ATTRS.has(attr) and not allowed.has(attr):
			return "unsupported attribute '%s' on <%s>" % [attr, name]
	var style: Dictionary = parent.duplicate()
	var shape_style_error: String = _apply_style(attrs, style)
	if not shape_style_error.is_empty():
		return shape_style_error
	var paths: Dictionary = _geometry(name, attrs)
	if not str(paths["error"]).is_empty():
		return str(paths["error"])
	var xf: Transform2D = parent["xf"]
	var lists: Array = paths["subpaths"]
	for item: Variant in lists:
		var sub: Dictionary = item
		var raw: PackedVector2Array = sub["points"]
		var shape: Shape = _make_shape(style, xf)
		for p: Vector2 in raw:
			shape.points.append(xf * p)
		shape.closed = sub["closed"]
		if shape.points.size() >= 2:
			shapes.append(shape)
	return ""


func _make_shape(style: Dictionary, xf: Transform2D) -> Shape:
	var shape: Shape = Shape.new()
	var fill_value: String = style["fill"]
	var stroke_value: String = style["stroke"]
	shape.fill = fill_value != "none"
	shape.fill_color = _paint_color(fill_value)
	shape.stroke = stroke_value != "none"
	shape.stroke_color = _paint_color(stroke_value)
	var width: float = style["stroke-width"]
	shape.stroke_width = width * (xf.x.length() + xf.y.length()) * 0.5
	shape.fill_opacity = style["fill-opacity"]
	shape.linecap = style["stroke-linecap"]
	shape.linejoin = style["stroke-linejoin"]
	return shape


## null for none, currentColor and the SVG default black; the Color otherwise.
func _paint_color(value: String) -> Variant:
	if value.begins_with("#"):
		return Color(value)
	return null


func _apply_style(attrs: Dictionary, style: Dictionary) -> String:
	for attr: String in STYLE_ATTRS:
		if not attrs.has(attr):
			continue
		var value: String = str(attrs[attr]).strip_edges()
		match attr:
			"fill", "stroke":
				if value == "none" or value == "currentColor" or (value.begins_with("#") and (value.length() == 4 or value.length() == 7) and value.substr(1).is_valid_hex_number()):
					style[attr] = value
				else:
					return "unsupported paint '%s' for %s (use none, currentColor or #rrggbb)" % [value, attr]
			"stroke-width", "fill-opacity":
				if not value.is_valid_float():
					return "%s needs a number, got '%s'" % [attr, value]
				style[attr] = value.to_float()
			"stroke-linecap":
				if not ["butt", "round", "square"].has(value):
					return "unsupported stroke-linecap '%s'" % value
				style[attr] = value
			"stroke-linejoin":
				if not ["miter", "round", "bevel"].has(value):
					return "unsupported stroke-linejoin '%s'" % value
				style[attr] = value
	return ""


## translate, rotate and scale only. Returns {"xf": Transform2D, "error": String}.
func _parse_transform(text: String) -> Dictionary:
	var result: Transform2D = Transform2D.IDENTITY
	var rest: String = text.strip_edges()
	while not rest.is_empty():
		var open: int = rest.find("(")
		var close: int = rest.find(")")
		if open < 0 or close < open:
			return {"xf": Transform2D.IDENTITY, "error": "malformed transform '%s'" % text}
		var op: String = rest.substr(0, open).strip_edges()
		var raw: PackedStringArray = rest.substr(open + 1, close - open - 1).replace(",", " ").split(" ", false)
		var args: PackedFloat64Array = PackedFloat64Array()
		for part: String in raw:
			if not part.is_valid_float():
				return {"xf": Transform2D.IDENTITY, "error": "transform needs numbers, got '%s'" % part}
			args.append(part.to_float())
		var step: Transform2D = Transform2D.IDENTITY
		match op:
			"translate":
				if args.size() < 1 or args.size() > 2:
					return {"xf": Transform2D.IDENTITY, "error": "translate needs 1 or 2 numbers"}
				step = Transform2D(0.0, Vector2(args[0], args[1] if args.size() > 1 else 0.0))
			"scale":
				if args.size() < 1 or args.size() > 2:
					return {"xf": Transform2D.IDENTITY, "error": "scale needs 1 or 2 numbers"}
				step = Transform2D.IDENTITY.scaled(Vector2(args[0], args[1] if args.size() > 1 else args[0]))
			"rotate":
				if args.size() != 1 and args.size() != 3:
					return {"xf": Transform2D.IDENTITY, "error": "rotate needs 1 or 3 numbers"}
				var angle: float = deg_to_rad(args[0])
				step = Transform2D(angle, Vector2.ZERO)
				if args.size() == 3:
					var center: Vector2 = Vector2(args[1], args[2])
					step = Transform2D(0.0, center) * step * Transform2D(0.0, -center)
			_:
				return {"xf": Transform2D.IDENTITY, "error": "unsupported transform '%s' (only translate, rotate and scale)" % op}
		result = result * step
		rest = rest.substr(close + 1).strip_edges()
	return {"xf": result, "error": ""}


# --- element geometry ---------------------------------------------------------------------------


## Returns {"subpaths": [{"points": PackedVector2Array, "closed": bool}], "error": String}.
func _geometry(name: String, attrs: Dictionary) -> Dictionary:
	var subpaths: Array = []
	match name:
		"path":
			if not attrs.has("d"):
				return _geometry_error("<path> needs d")
			return _parse_path(str(attrs["d"]))
		"line":
			var v: Dictionary = _numbers(attrs, ["x1", "y1", "x2", "y2"], name)
			if not str(v["error"]).is_empty():
				return v
			var x1: float = v["x1"]
			var y1: float = v["y1"]
			var x2: float = v["x2"]
			var y2: float = v["y2"]
			subpaths.append({"points": PackedVector2Array([Vector2(x1, y1), Vector2(x2, y2)]), "closed": false})
		"polyline", "polygon":
			if not attrs.has("points"):
				return _geometry_error("<%s> needs points" % name)
			var raw: PackedStringArray = str(attrs["points"]).replace(",", " ").split(" ", false)
			if raw.size() < 4 or raw.size() % 2 != 0:
				return _geometry_error("<%s> points need an even number of values (at least 2 points)" % name)
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in range(0, raw.size(), 2):
				if not raw[i].is_valid_float() or not raw[i + 1].is_valid_float():
					return _geometry_error("<%s> points need numbers" % name)
				pts.append(Vector2(raw[i].to_float(), raw[i + 1].to_float()))
			subpaths.append({"points": pts, "closed": name == "polygon"})
		"rect":
			var r: Dictionary = _numbers(attrs, ["x", "y", "width", "height"], name, ["x", "y"])
			if not str(r["error"]).is_empty():
				return r
			var w: float = r["width"]
			var h: float = r["height"]
			if w <= 0.0 or h <= 0.0:
				return _geometry_error("<rect> needs a positive width and height")
			var x: float = r["x"]
			var y: float = r["y"]
			subpaths.append({"points": PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), "closed": true})
		"circle":
			var c: Dictionary = _numbers(attrs, ["cx", "cy", "r"], name, ["cx", "cy"])
			if not str(c["error"]).is_empty():
				return c
			var radius: float = c["r"]
			if radius <= 0.0:
				return _geometry_error("<circle> needs a positive radius")
			var ccx: float = c["cx"]
			var ccy: float = c["cy"]
			subpaths.append({"points": _ellipse_points(Vector2(ccx, ccy), radius, radius), "closed": true})
		"ellipse":
			var e: Dictionary = _numbers(attrs, ["cx", "cy", "rx", "ry"], name, ["cx", "cy"])
			if not str(e["error"]).is_empty():
				return e
			var rx: float = e["rx"]
			var ry: float = e["ry"]
			if rx <= 0.0 or ry <= 0.0:
				return _geometry_error("<ellipse> needs positive radii")
			var ecx: float = e["cx"]
			var ecy: float = e["cy"]
			subpaths.append({"points": _ellipse_points(Vector2(ecx, ecy), rx, ry), "closed": true})
	return {"subpaths": subpaths, "error": ""}


func _geometry_error(message: String) -> Dictionary:
	return {"subpaths": [], "error": message}


## Reads the named numeric attributes; those in `optional` default to 0.
func _numbers(attrs: Dictionary, names: Array, element: String, optional: Array = []) -> Dictionary:
	var out: Dictionary = {"error": ""}
	for key: Variant in names:
		var attr: String = key
		if not attrs.has(attr):
			if optional.has(attr):
				out[attr] = 0.0
				continue
			out["error"] = "<%s> needs %s" % [element, attr]
			return out
		var value: String = str(attrs[attr]).strip_edges()
		if not value.is_valid_float():
			out["error"] = "<%s> %s needs a number, got '%s'" % [element, attr, value]
			return out
		out[attr] = value.to_float()
	return out


func _ellipse_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in CIRCLE_SEGMENTS:
		var a: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return points


# --- path data -----------------------------------------------------------------------------------

const ARG_COUNT: Dictionary = {
	"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "A": 7, "Z": 0,
}


func _parse_path(data: String) -> Dictionary:
	var subpaths: Array = []
	var current: PackedVector2Array = PackedVector2Array()
	var pos: Vector2 = Vector2.ZERO
	var start: Vector2 = Vector2.ZERO
	var last_control: Vector2 = Vector2.ZERO
	var last_command: String = ""
	var i: int = 0
	var n: int = data.length()
	var command: String = ""
	var has_move: bool = false
	while true:
		i = _skip_separators(data, i)
		if i >= n:
			break
		var ch: String = data[i]
		if ch.to_upper() in ARG_COUNT and ch != "e" and ch != "E":
			command = ch
			i += 1
			if command.to_upper() == "Z":
				if current.size() > 0:
					subpaths.append({"points": current, "closed": true})
					current = PackedVector2Array()
					pos = start
				last_command = "Z"
				continue
		elif command.is_empty() or command.to_upper() == "Z":
			return _geometry_error("path data: expected a command letter near '%s'" % data.substr(i, 6))
		elif not (ch == "-" or ch == "+" or ch == "." or ch.is_valid_int()):
			return _geometry_error("path data: unsupported path command '%s'" % ch)
		var upper: String = command.to_upper()
		var relative: bool = command != upper
		if not ARG_COUNT.has(upper):
			return _geometry_error("path data: unsupported path command '%s'" % command)
		if not has_move and upper != "M":
			return _geometry_error("path data must start with a move command (M)")
		var count: int = ARG_COUNT[upper]
		var args: PackedFloat64Array = PackedFloat64Array()
		for k: int in count:
			var parsed: Dictionary = _read_arg(data, i, upper == "A" and (k == 3 or k == 4))
			if not str(parsed["error"]).is_empty():
				return _geometry_error("path data: command %s: %s" % [upper, parsed["error"]])
			var number: float = parsed["value"]
			args.append(number)
			i = parsed["next"]
		match upper:
			"M":
				if current.size() > 1:
					subpaths.append({"points": current, "closed": false})
				var target: Vector2 = Vector2(args[0], args[1])
				pos = pos + target if relative and has_move else target
				start = pos
				current = PackedVector2Array([pos])
				has_move = true
				# further coordinate pairs after a move are implicit line-tos
				command = "l" if relative else "L"
			"L":
				if current.is_empty():
					current = PackedVector2Array([pos])
				var to: Vector2 = Vector2(args[0], args[1])
				pos = pos + to if relative else to
				current.append(pos)
			"H":
				if current.is_empty():
					current = PackedVector2Array([pos])
				pos = Vector2(pos.x + args[0] if relative else args[0], pos.y)
				current.append(pos)
			"V":
				if current.is_empty():
					current = PackedVector2Array([pos])
				pos = Vector2(pos.x, pos.y + args[0] if relative else args[0])
				current.append(pos)
			"C", "S":
				if current.is_empty():
					current = PackedVector2Array([pos])
				var c1: Vector2
				var c2: Vector2
				var end: Vector2
				if upper == "C":
					c1 = Vector2(args[0], args[1])
					c2 = Vector2(args[2], args[3])
					end = Vector2(args[4], args[5])
					if relative:
						c1 += pos
						c2 += pos
						end += pos
				else:
					c1 = pos
					if last_command == "C" or last_command == "S":
						c1 = pos * 2.0 - last_control
					c2 = Vector2(args[0], args[1])
					end = Vector2(args[2], args[3])
					if relative:
						c2 += pos
						end += pos
				for step: int in range(1, CURVE_SEGMENTS + 1):
					current.append(_cubic(pos, c1, c2, end, float(step) / float(CURVE_SEGMENTS)))
				last_control = c2
				pos = end
			"Q":
				if current.is_empty():
					current = PackedVector2Array([pos])
				var q1: Vector2 = Vector2(args[0], args[1])
				var qe: Vector2 = Vector2(args[2], args[3])
				if relative:
					q1 += pos
					qe += pos
				for step: int in range(1, QUAD_SEGMENTS + 1):
					var t: float = float(step) / float(QUAD_SEGMENTS)
					current.append(pos.lerp(q1, t).lerp(q1.lerp(qe, t), t))
				pos = qe
			"A":
				if current.is_empty():
					current = PackedVector2Array([pos])
				var arc_end: Vector2 = Vector2(args[5], args[6])
				if relative:
					arc_end += pos
				if args[0] <= 0.0 or args[1] <= 0.0:
					return _geometry_error("path data: arc radii must be positive")
				var arc_points: PackedVector2Array = _arc(pos, args[0], args[1], args[2], args[3] != 0.0, args[4] != 0.0, arc_end)
				current.append_array(arc_points)
				pos = arc_end
		last_command = upper
		if upper != "C" and upper != "S":
			last_control = pos
	if current.size() >= 2:
		subpaths.append({"points": current, "closed": false})
	if subpaths.is_empty():
		return _geometry_error("path data draws nothing")
	return {"subpaths": subpaths, "error": ""}


func _skip_separators(data: String, from: int) -> int:
	var i: int = from
	while i < data.length() and (data[i] == " " or data[i] == "," or data[i] == "\t" or data[i] == "\n" or data[i] == "\r"):
		i += 1
	return i


## Reads one number (or one arc flag, a single 0 or 1) at `from`.
func _read_arg(data: String, from: int, is_flag: bool) -> Dictionary:
	var i: int = _skip_separators(data, from)
	if i >= data.length():
		return {"error": "missing number", "value": 0.0, "next": i}
	if is_flag:
		var flag: String = data[i]
		if flag != "0" and flag != "1":
			return {"error": "an arc flag must be 0 or 1, got '%s'" % flag, "value": 0.0, "next": i}
		return {"error": "", "value": float(flag.to_int()), "next": i + 1}
	var j: int = i
	if j < data.length() and (data[j] == "-" or data[j] == "+"):
		j += 1
	var digits: int = 0
	while j < data.length() and data[j].is_valid_int():
		j += 1
		digits += 1
	if j < data.length() and data[j] == ".":
		j += 1
		while j < data.length() and data[j].is_valid_int():
			j += 1
			digits += 1
	if digits == 0:
		return {"error": "expected a number near '%s'" % data.substr(i, 6), "value": 0.0, "next": i}
	if j < data.length() and (data[j] == "e" or data[j] == "E"):
		var k: int = j + 1
		if k < data.length() and (data[k] == "-" or data[k] == "+"):
			k += 1
		var exp_digits: int = 0
		while k < data.length() and data[k].is_valid_int():
			k += 1
			exp_digits += 1
		if exp_digits > 0:
			j = k
	return {"error": "", "value": data.substr(i, j - i).to_float(), "next": j}


func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Flattened elliptical arc from `from` (excluded) to `to` (included), per SVG implementation
## note F.6.5 (endpoint to centre parameterisation).
func _arc(from: Vector2, rx_in: float, ry_in: float, rotation_deg: float, large: bool, sweep: bool, to: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if from == to:
		return out
	var rx: float = absf(rx_in)
	var ry: float = absf(ry_in)
	var phi: float = deg_to_rad(rotation_deg)
	var cos_phi: float = cos(phi)
	var sin_phi: float = sin(phi)
	var d: Vector2 = (from - to) * 0.5
	var x1p: float = cos_phi * d.x + sin_phi * d.y
	var y1p: float = -sin_phi * d.x + cos_phi * d.y
	var lambda: float = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lambda > 1.0:
		var scale: float = sqrt(lambda)
		rx *= scale
		ry *= scale
	var numerator: float = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	var denominator: float = rx * rx * y1p * y1p + ry * ry * x1p * x1p
	var factor: float = 0.0
	if denominator > 0.0:
		factor = sqrt(maxf(0.0, numerator / denominator))
	if large == sweep:
		factor = -factor
	var cxp: float = factor * (rx * y1p / ry)
	var cyp: float = factor * -(ry * x1p / rx)
	var center: Vector2 = Vector2(cos_phi * cxp - sin_phi * cyp, sin_phi * cxp + cos_phi * cyp) + (from + to) * 0.5
	var v1: Vector2 = Vector2((x1p - cxp) / rx, (y1p - cyp) / ry)
	var v2: Vector2 = Vector2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
	var theta1: float = v1.angle()
	var delta: float = fposmod(v2.angle() - theta1, TAU)
	if not sweep and delta > 0.0:
		delta -= TAU
	var steps: int = maxi(2, ceili(absf(delta) / ARC_STEP))
	for s: int in range(1, steps + 1):
		var a: float = theta1 + delta * float(s) / float(steps)
		var x: float = rx * cos(a)
		var y: float = ry * sin(a)
		out.append(Vector2(cos_phi * x - sin_phi * y, sin_phi * x + cos_phi * y) + center)
	out[out.size() - 1] = to
	return out
