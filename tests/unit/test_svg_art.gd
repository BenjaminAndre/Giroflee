extends GutTest
@warning_ignore_start("unsafe_call_argument")
## SRD 11.3: the supported SVG subset, turned into vector shapes that the screen, SVG, PDF and PNG
## backends all draw the same way.

const HEAD: String = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 20 20">'
const FOOT: String = "</svg>"


func _svg(body: String) -> SvgArt:
	return SvgArt.parse(HEAD + body + FOOT)


func _near(a: Vector2, b: Vector2, tol: float = 0.01) -> bool:
	return a.distance_to(b) <= tol


# --- shapes -----------------------------------------------------------------------------------


func test_a_circle_becomes_a_closed_many_sided_polygon_of_the_right_radius() -> void:
	var art: SvgArt = _svg('<circle cx="1" cy="2" r="3" fill="none" stroke="currentColor" stroke-width="0.35"/>')
	assert_true(art.ok(), art.error)
	assert_eq(art.shapes.size(), 1)
	var shape: SvgArt.Shape = art.shapes[0]
	assert_true(shape.closed)
	assert_true(shape.points.size() >= 24)
	for p: Vector2 in shape.points:
		assert_almost_eq(p.distance_to(Vector2(1, 2)), 3.0, 0.02)
	assert_true(shape.stroke and not shape.fill)
	assert_almost_eq(shape.stroke_width, 0.35, 0.0001)
	assert_null(shape.stroke_color, "currentColor means: the colour chosen by the renderer")


func test_ellipse_line_polyline_polygon_and_rect() -> void:
	var art: SvgArt = _svg('<ellipse cx="0" cy="0" rx="4" ry="2" fill="none" stroke="currentColor"/>'
		+ '<line x1="0" y1="0" x2="3" y2="4" stroke="currentColor"/>'
		+ '<polyline points="0,0 1,1 2,0" fill="none" stroke="currentColor"/>'
		+ '<polygon points="0,0 2,0 1,2" fill="currentColor"/>'
		+ '<rect x="-1" y="-1" width="2" height="3" fill="none" stroke="currentColor"/>')
	assert_true(art.ok(), art.error)
	assert_eq(art.shapes.size(), 5)
	assert_true(art.shapes[0].closed)
	assert_eq(art.shapes[1].points, PackedVector2Array([Vector2(0, 0), Vector2(3, 4)]))
	assert_false(art.shapes[1].closed)
	assert_false(art.shapes[2].closed)
	assert_eq(art.shapes[2].points.size(), 3)
	assert_true(art.shapes[3].closed and art.shapes[3].fill)
	assert_eq(art.shapes[4].points, PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 2), Vector2(-1, 2)]))
	assert_true(art.shapes[4].closed)


func test_path_commands_absolute_and_relative() -> void:
	var art: SvgArt = _svg('<path d="M0 0 L4 0 H4 V3 l-4 0 z" fill="none" stroke="currentColor"/>')
	assert_true(art.ok(), art.error)
	var shape: SvgArt.Shape = art.shapes[0]
	assert_true(shape.closed)
	assert_eq(shape.points, PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 0), Vector2(4, 3), Vector2(0, 3)]))
	var rel: SvgArt = _svg('<path d="m1 1 h2 v2 h-2 z" fill="none" stroke="currentColor"/>')
	assert_eq(rel.shapes[0].points, PackedVector2Array([Vector2(1, 1), Vector2(3, 1), Vector2(3, 3), Vector2(1, 3)]))


func test_a_path_with_several_subpaths_makes_several_shapes() -> void:
	var art: SvgArt = _svg('<path d="M0 0 L1 0 M5 5 L6 5 L6 6 Z" fill="none" stroke="currentColor"/>')
	assert_eq(art.shapes.size(), 2)
	assert_false(art.shapes[0].closed)
	assert_true(art.shapes[1].closed)


func test_cubic_and_quadratic_curves_are_flattened_and_hit_their_end_points() -> void:
	var cubic: SvgArt = _svg('<path d="M0 0 C0 4 4 4 4 0" fill="none" stroke="currentColor"/>')
	var points: PackedVector2Array = cubic.shapes[0].points
	assert_true(points.size() >= 8, "flattened into several segments")
	assert_true(_near(points[0], Vector2(0, 0)))
	assert_true(_near(points[points.size() - 1], Vector2(4, 0)))
	var top: float = 0.0
	for p: Vector2 in points:
		top = maxf(top, p.y)
	assert_almost_eq(top, 3.0, 0.05, "the curve peaks at 3 (0.75 of the control height)")
	var quad: SvgArt = _svg('<path d="M0 0 Q2 4 4 0" fill="none" stroke="currentColor"/>')
	var qp: PackedVector2Array = quad.shapes[0].points
	assert_true(_near(qp[qp.size() - 1], Vector2(4, 0)))
	var smooth: SvgArt = _svg('<path d="M0 0 C0 2 2 2 2 0 S4 -2 4 0" fill="none" stroke="currentColor"/>')
	assert_true(smooth.ok(), smooth.error)
	var sp: PackedVector2Array = smooth.shapes[0].points
	assert_true(_near(sp[sp.size() - 1], Vector2(4, 0)))


func test_arcs_follow_the_circle_and_respect_the_flags() -> void:
	var art: SvgArt = _svg('<path d="M-3 0 A3 3 0 0 1 3 0" fill="none" stroke="currentColor"/>')
	assert_true(art.ok(), art.error)
	var points: PackedVector2Array = art.shapes[0].points
	assert_true(points.size() >= 10)
	for p: Vector2 in points:
		assert_almost_eq(p.length(), 3.0, 0.03, "every point is on the radius-3 circle")
	assert_true(_near(points[0], Vector2(-3, 0)) and _near(points[points.size() - 1], Vector2(3, 0)))
	var mid: Vector2 = points[points.size() / 2]
	assert_true(mid.y < -2.5, "sweep flag 1 passes through the top (SVG y points down)")
	var other: SvgArt = _svg('<path d="M-3 0 A3 3 0 0 0 3 0" fill="none" stroke="currentColor"/>')
	var op: PackedVector2Array = other.shapes[0].points
	assert_true(op[op.size() / 2].y > 2.5, "sweep flag 0 goes the other way")


func test_an_arc_with_too_small_a_radius_is_scaled_up_like_a_browser_does() -> void:
	var art: SvgArt = _svg('<path d="M-3 0 A1 1 0 0 1 3 0" fill="none" stroke="currentColor"/>')
	assert_true(art.ok(), art.error)
	var points: PackedVector2Array = art.shapes[0].points
	assert_true(_near(points[points.size() - 1], Vector2(3, 0)))


# --- style, transform -------------------------------------------------------------------------


func test_groups_pass_their_style_and_transform_to_children() -> void:
	var art: SvgArt = _svg('<g stroke="currentColor" stroke-width="0.5" fill="none" transform="translate(2 3) scale(2)">'
		+ '<line x1="0" y1="0" x2="1" y2="0"/></g>')
	assert_true(art.ok(), art.error)
	var shape: SvgArt.Shape = art.shapes[0]
	assert_eq(shape.points, PackedVector2Array([Vector2(2, 3), Vector2(4, 3)]))
	assert_almost_eq(shape.stroke_width, 1.0, 0.0001, "the stroke is scaled with the group")
	assert_true(shape.stroke and not shape.fill)


func test_rotation_and_nested_groups() -> void:
	var art: SvgArt = _svg('<g transform="rotate(90)"><g transform="translate(1 0)"><line x1="0" y1="0" x2="2" y2="0" stroke="currentColor"/></g></g>')
	assert_true(art.ok(), art.error)
	var p: PackedVector2Array = art.shapes[0].points
	assert_true(_near(p[0], Vector2(0, 1)) and _near(p[1], Vector2(0, 3)), "translate then rotate by 90 degrees (y down)")
	var about: SvgArt = _svg('<g transform="rotate(180 1 1)"><line x1="0" y1="1" x2="1" y2="1" stroke="currentColor"/></g>')
	var q: PackedVector2Array = about.shapes[0].points
	assert_true(_near(q[0], Vector2(2, 1)) and _near(q[1], Vector2(1, 1)))


func test_paint_values() -> void:
	var art: SvgArt = _svg('<rect x="0" y="0" width="2" height="2" fill="#319447" stroke="#4c4f69" stroke-width="0.2" fill-opacity="0.5"/>')
	assert_true(art.ok(), art.error)
	var shape: SvgArt.Shape = art.shapes[0]
	assert_eq(shape.fill_color, Color("#319447"))
	assert_eq(shape.stroke_color, Color("#4c4f69"))
	assert_almost_eq(shape.fill_opacity, 0.5, 0.0001)
	var short: SvgArt = _svg('<rect x="0" y="0" width="1" height="1" fill="#fff" stroke="none"/>')
	assert_eq(short.shapes[0].fill_color, Color("#ffffff"), "three-digit hex")
	assert_false(short.shapes[0].stroke)


func test_svg_defaults_fill_black_and_no_stroke() -> void:
	var art: SvgArt = _svg('<rect x="0" y="0" width="1" height="1"/>')
	assert_true(art.shapes[0].fill)
	assert_false(art.shapes[0].stroke)
	assert_null(art.shapes[0].fill_color, "black by default is currentColor for our purposes")


func test_stroke_attributes_are_kept() -> void:
	var art: SvgArt = _svg('<line x1="0" y1="0" x2="1" y2="0" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>')
	assert_eq(art.shapes[0].linecap, "round")
	assert_eq(art.shapes[0].linejoin, "round")


# --- view box and bounds ----------------------------------------------------------------------


func test_view_box_and_bounds() -> void:
	var art: SvgArt = _svg('<line x1="-2" y1="1" x2="3" y2="-4" stroke="currentColor"/>')
	assert_eq(art.view_box, Rect2(-10, -10, 20, 20))
	assert_eq(art.bounds(), Rect2(-2, -4, 5, 5))
	assert_eq(SvgArt.new().bounds(), Rect2())


# --- what is refused ---------------------------------------------------------------------------


func _refused(body: String, fragment: String) -> void:
	var art: SvgArt = _svg(body)
	assert_false(art.ok(), "should be refused: " + body)
	assert_string_contains(art.error, fragment)


func test_unsupported_elements_are_refused_with_a_clear_message() -> void:
	_refused('<text x="0" y="0">A</text>', "text")
	_refused('<image href="a.png"/>', "image")
	_refused('<style>.a{fill:red}</style>', "style")
	_refused('<defs/>', "defs")
	_refused('<use href="#a"/>', "use")
	_refused('<linearGradient id="g"/>', "linearGradient")


func test_unsupported_attributes_are_refused() -> void:
	_refused('<path d="M0 0 L1 1" style="stroke:red"/>', "style")
	_refused('<path d="M0 0 L1 1" class="x"/>', "class")
	_refused('<path d="M0 0 L1 1" filter="url(#f)"/>', "filter")
	_refused('<path d="M0 0 L1 1" opacity="0.5"/>', "opacity")
	_refused('<path d="M0 0 L1 1" stroke-dasharray="1 1"/>', "stroke-dasharray")


func test_transform_is_only_allowed_on_groups() -> void:
	_refused('<path d="M0 0 L1 1" transform="scale(2)"/>', "transform")
	_refused('<g transform="skewX(10)"><line x1="0" y1="0" x2="1" y2="0"/></g>', "skewX")
	_refused('<g transform="matrix(1 0 0 1 0 0)"><line x1="0" y1="0" x2="1" y2="0"/></g>', "matrix")


func test_unsupported_path_commands_and_bad_numbers_are_refused() -> void:
	_refused('<path d="M0 0 T1 1"/>', "T")
	_refused('<path d="M0 0 L1"/>', "L")
	_refused('<path d="M0 0 L a b"/>', "number")
	_refused('<path d="L1 1"/>', "move")
	_refused('<path d="M0 0 A1 1 0 2 1 1 1"/>', "flag")


func test_structural_problems_are_refused() -> void:
	assert_false(SvgArt.parse("not xml at all <<").ok())
	assert_false(SvgArt.parse('<svg xmlns="http://www.w3.org/2000/svg"><line x1="0" y1="0" x2="1" y2="0"/></svg>').ok(), "no viewBox")
	assert_false(SvgArt.parse('<svg viewBox="0 0 1 1"><svg viewBox="0 0 1 1"/></svg>').ok(), "nested svg")
	assert_false(SvgArt.parse('<line x1="0" y1="0" x2="1" y2="0"/>').ok(), "no svg root")
	assert_false(SvgArt.parse("").ok())
	assert_false(_svg('<circle cx="0" cy="0" r="-1"/>').ok(), "negative radius")
	assert_false(_svg('<rect x="0" y="0" width="1"/>').ok(), "missing height")


func test_an_invalid_file_has_no_shapes_so_it_cannot_half_render() -> void:
	var art: SvgArt = _svg('<line x1="0" y1="0" x2="1" y2="0" stroke="currentColor"/><text/>')
	assert_false(art.ok())
	assert_eq(art.shapes.size(), 0)
