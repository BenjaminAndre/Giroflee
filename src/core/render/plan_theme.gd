class_name PlanTheme
extends RefCounted
## Default look of a plan (SRD 12.1: style tokens measured on the author's earlier plans).
## Sizes are in page millimetres unless noted; the renderer converts them with the sheet scale.

const BLACK: Color = Color(0.0, 0.0, 0.0)
const BLUE: Color = Color(13.0 / 255.0, 121.0 / 255.0, 242.0 / 255.0)
const DARK_RED: Color = Color(144.0 / 255.0, 0.0, 0.0)
const GREEN: Color = Color(31.0 / 255.0, 182.0 / 255.0, 114.0 / 255.0)
const GREY_FILL: Color = Color(202.0 / 255.0, 202.0 / 255.0, 202.0 / 255.0, 0.9)
const GHOST: Color = Color(0.72, 0.72, 0.72)
const GHOST_FILL: Color = Color(0.85, 0.85, 0.85, 0.5)
const DOT: Color = Color(154.0 / 255.0, 154.0 / 255.0, 154.0 / 255.0)

const PT_TO_MM: float = 25.4 / 72.0

## Thickness of door and window symbols across the wall (page mm), as in the reference plans.
const OPENING_THICKNESS: float = 8.4
const FRAME_LINE: float = 0.35
## Height of the title block area reserved at the bottom of the page (the cartouche, M4).
const CARTOUCHE_HEIGHT: float = 44.0
## Width of the row-letter band and height of the column-number band of the frame.
const FRAME_BAND: float = 8.6

## Text size factor per role, relative to the project's base font size.
const ROLE_FACTOR: Dictionary = {
	"free": 1.6,
	"room": 1.6,
	"floor": 2.6,
	"symbol": 0.8,
	"other": 1.0,
}


static func role_color(role: String) -> Color:
	match role:
		"free", "room":
			return BLUE
		"floor":
			return DARK_RED
	return BLACK


static func role_factor(role: String) -> float:
	var factor: float = ROLE_FACTOR.get(role, 1.0)
	return factor
