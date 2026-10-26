class_name AppTheme
extends RefCounted
## The interface look: the Catppuccin Latte palette (light, MIT licence, credited in
## third_party/NOTICE), built in code so no widget sets ad-hoc colours (SRD FR-UI). Plans are
## printed on white paper, so there is no dark theme.

# Catppuccin Latte
const ROSEWATER: Color = Color(220.0 / 255.0, 138.0 / 255.0, 120.0 / 255.0)
const RED: Color = Color(210.0 / 255.0, 15.0 / 255.0, 57.0 / 255.0)
const PEACH: Color = Color(254.0 / 255.0, 100.0 / 255.0, 11.0 / 255.0)
const GREEN: Color = Color(64.0 / 255.0, 160.0 / 255.0, 43.0 / 255.0)
const BLUE: Color = Color(30.0 / 255.0, 102.0 / 255.0, 245.0 / 255.0)
const TEXT: Color = Color(76.0 / 255.0, 79.0 / 255.0, 105.0 / 255.0)
const SUBTEXT0: Color = Color(108.0 / 255.0, 111.0 / 255.0, 133.0 / 255.0)
const OVERLAY0: Color = Color(156.0 / 255.0, 160.0 / 255.0, 176.0 / 255.0)
const SURFACE1: Color = Color(188.0 / 255.0, 192.0 / 255.0, 204.0 / 255.0)
const SURFACE0: Color = Color(204.0 / 255.0, 208.0 / 255.0, 218.0 / 255.0)
const BASE: Color = Color(239.0 / 255.0, 241.0 / 255.0, 245.0 / 255.0)
const MANTLE: Color = Color(230.0 / 255.0, 233.0 / 255.0, 239.0 / 255.0)
const CRUST: Color = Color(220.0 / 255.0, 224.0 / 255.0, 232.0 / 255.0)

# the logo's own colours (FR-UI-4: not general interface colours)
const LOGO_YELLOW: Color = Color(245.0 / 255.0, 217.0 / 255.0, 40.0 / 255.0)
const LOGO_GREEN: Color = Color(49.0 / 255.0, 148.0 / 255.0, 71.0 / 255.0)

const FONT_SIZE: int = 14
const RADIUS: int = 4


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.set_default_font_size(FONT_SIZE)

	for type_name: String in ["Label", "CheckBox", "OptionButton", "Button", "LineEdit", "SpinBox", "ItemList", "PopupMenu", "MenuBar", "TabBar"]:
		theme.set_color("font_color", type_name, TEXT)
	for type_name: String in ["Button", "CheckBox", "OptionButton"]:
		theme.set_color("font_hover_color", type_name, TEXT)
		theme.set_color("font_pressed_color", type_name, TEXT)
		theme.set_color("font_focus_color", type_name, TEXT)
		theme.set_color("font_disabled_color", type_name, OVERLAY0)
		theme.set_color("icon_normal_color", type_name, Color.WHITE)

	# surfaces
	theme.set_stylebox("panel", "PanelContainer", _flat(BASE, SURFACE0, 0, 6))
	theme.set_type_variation("ToolPanel", "PanelContainer")
	theme.set_stylebox("panel", "ToolPanel", _flat(MANTLE, SURFACE0, 0, 4))

	# buttons: quiet by default, the active tool is outlined in the accent colour
	theme.set_stylebox("normal", "Button", _flat(MANTLE, SURFACE1, 1, 6))
	theme.set_stylebox("hover", "Button", _flat(SURFACE0, SURFACE1, 1, 6))
	theme.set_stylebox("pressed", "Button", _flat(BASE, BLUE, 2, 6))
	theme.set_stylebox("hover_pressed", "Button", _flat(BASE, BLUE, 2, 6))
	theme.set_stylebox("disabled", "Button", _flat(MANTLE, SURFACE0, 1, 6))
	theme.set_stylebox("focus", "Button", _empty())
	theme.set_stylebox("normal", "OptionButton", _flat(BASE, SURFACE1, 1, 6))
	theme.set_stylebox("hover", "OptionButton", _flat(SURFACE0, SURFACE1, 1, 6))
	theme.set_stylebox("pressed", "OptionButton", _flat(SURFACE0, BLUE, 1, 6))
	theme.set_stylebox("focus", "OptionButton", _empty())
	# a checkbox row is plain: it must not inherit the framed Button look
	for style_name: String in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(style_name, "CheckBox", _empty())
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("checkbox_checked_color", "CheckBox", BLUE)
	theme.set_color("checkbox_unchecked_color", "CheckBox", SUBTEXT0)

	# fields
	theme.set_stylebox("normal", "LineEdit", _flat(BASE, SURFACE1, 1, 6))
	theme.set_stylebox("focus", "LineEdit", _flat(BASE, BLUE, 2, 6))
	theme.set_stylebox("read_only", "LineEdit", _flat(MANTLE, SURFACE0, 1, 6))
	theme.set_color("caret_color", "LineEdit", BLUE)
	theme.set_color("selection_color", "LineEdit", Color(BLUE.r, BLUE.g, BLUE.b, 0.25))
	theme.set_color("font_placeholder_color", "LineEdit", OVERLAY0)
	theme.set_color("up_icon_modulate", "SpinBox", TEXT)
	theme.set_color("down_icon_modulate", "SpinBox", TEXT)
	theme.set_color("up_hover_icon_modulate", "SpinBox", BLUE)
	theme.set_color("down_hover_icon_modulate", "SpinBox", BLUE)

	# tabs (the étages)
	theme.set_stylebox("tab_selected", "TabBar", _tab(BASE, true))
	theme.set_stylebox("tab_unselected", "TabBar", _tab(MANTLE, false))
	theme.set_stylebox("tab_hovered", "TabBar", _tab(SURFACE0, false))
	theme.set_stylebox("tab_focus", "TabBar", _tab(BASE, true))
	theme.set_stylebox("tabbar_background", "TabBar", _flat(MANTLE, SURFACE0, 0, 0))
	theme.set_color("font_selected_color", "TabBar", TEXT)
	theme.set_color("font_unselected_color", "TabBar", SUBTEXT0)
	theme.set_color("font_hovered_color", "TabBar", TEXT)

	# menus and the command palette
	theme.set_stylebox("panel", "PopupMenu", _flat(BASE, SURFACE1, 1, 4))
	theme.set_stylebox("hover", "PopupMenu", _flat(SURFACE0, SURFACE0, 0, 4))
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", OVERLAY0)
	theme.set_color("font_separator_color", "PopupMenu", SUBTEXT0)
	theme.set_stylebox("separator", "PopupMenu", _line(SURFACE1))
	theme.set_stylebox("normal", "MenuBar", _flat(MANTLE, MANTLE, 0, 4))
	theme.set_stylebox("hover", "MenuBar", _flat(SURFACE0, SURFACE0, 0, 4))
	theme.set_stylebox("pressed", "MenuBar", _flat(SURFACE1, SURFACE1, 0, 4))
	theme.set_stylebox("hover_pressed", "MenuBar", _flat(SURFACE1, SURFACE1, 0, 4))
	theme.set_color("font_hover_color", "MenuBar", TEXT)
	theme.set_color("font_pressed_color", "MenuBar", TEXT)
	theme.set_stylebox("panel", "ItemList", _flat(BASE, SURFACE1, 1, 4))
	theme.set_stylebox("selected", "ItemList", _flat(SURFACE0, SURFACE0, 0, 4))
	theme.set_stylebox("selected_focus", "ItemList", _flat(SURFACE0, BLUE, 1, 4))
	theme.set_color("font_selected_color", "ItemList", TEXT)

	# scrollbars
	theme.set_stylebox("scroll", "VScrollBar", _flat(MANTLE, MANTLE, 0, 0))
	theme.set_stylebox("grabber", "VScrollBar", _flat(SURFACE1, SURFACE1, 0, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _flat(OVERLAY0, OVERLAY0, 0, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _flat(SUBTEXT0, SUBTEXT0, 0, 0))

	# tooltips
	theme.set_stylebox("panel", "TooltipPanel", _flat(TEXT, TEXT, 0, 6))
	theme.set_color("font_color", "TooltipLabel", BASE)
	return theme


static func _flat(bg: Color, border: Color, border_width: int, padding: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(RADIUS if border_width > 0 else 0)
	box.set_content_margin_all(float(padding))
	return box


static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func _line(color: Color) -> StyleBoxLine:
	var line: StyleBoxLine = StyleBoxLine.new()
	line.color = color
	line.thickness = 1
	return line


static func _tab(bg: Color, selected: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(0)
	if selected:
		box.border_color = BLUE
		box.border_width_bottom = 3
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box
