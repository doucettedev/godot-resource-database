@tool
class_name GRDTheme
extends RefCounted

## Compact dark theme helpers for the Resource Database editor UI.

const FONT_SIZE: int = 11
const FONT_SIZE_SMALL: int = 10
const FONT_SIZE_TINY: int = 9
const CONTROL_HEIGHT: int = 26
const CELL_HEIGHT: int = 30
const RADIUS: int = 5

const BG: Color = Color(0.105, 0.115, 0.14)
const BG_ALT: Color = Color(0.13, 0.14, 0.17)
const PANEL: Color = Color(0.15, 0.16, 0.20)
const PANEL_HOVER: Color = Color(0.19, 0.20, 0.25)
const HEADER: Color = Color(0.17, 0.18, 0.23)
const FIELD: Color = Color(0.09, 0.10, 0.13)
const FIELD_FOCUS: Color = Color(0.12, 0.14, 0.18)
const ACCENT: Color = Color(0.35, 0.62, 0.96)
const ACCENT_DARK: Color = Color(0.18, 0.31, 0.48)
const BORDER: Color = Color(0.26, 0.29, 0.36)
const TEXT: Color = Color(0.86, 0.89, 0.94)
const TEXT_MUTED: Color = Color(0.56, 0.60, 0.68)
const TEXT_DIM: Color = Color(0.38, 0.42, 0.50)
const WARNING: Color = Color(1.0, 0.78, 0.32)
const SUCCESS: Color = Color(0.45, 0.86, 0.60)
const ERROR: Color = Color(1.0, 0.38, 0.38)

static var _editor_scale_override: float = 0.0
static var _editor_font_size_override: int = 0


static func set_editor_scale(scale: float) -> void:
	_editor_scale_override = max(scale, 1.0)


static func set_editor_metrics(scale: float, default_font_size: int) -> void:
	set_editor_scale(scale)
	_editor_font_size_override = max(default_font_size, FONT_SIZE)


static func style_label(label: Label, size: int = FONT_SIZE, color: Color = TEXT) -> void:
	label.add_theme_font_size_override("font_size", scaled_font_size(size))
	label.add_theme_color_override("font_color", color)


static func style_rich_text(label: RichTextLabel, size: int = FONT_SIZE) -> void:
	label.add_theme_font_size_override("normal_font_size", scaled_font_size(size))
	label.add_theme_color_override("default_color", TEXT)
	label.add_theme_stylebox_override("normal", panel_style(BG, BORDER, RADIUS, 6, 4))


static func style_button(button: Button, accent: bool = false) -> void:
	button.custom_minimum_size.y = control_height()
	button.add_theme_font_size_override("font_size", font_size())
	button.add_theme_color_override("font_color", Color.WHITE if accent else TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", panel_style(ACCENT_DARK if accent else PANEL, BORDER, RADIUS, 9, 3))
	button.add_theme_stylebox_override("hover", panel_style(ACCENT if accent else PANEL_HOVER, ACCENT, RADIUS, 9, 3))
	button.add_theme_stylebox_override("pressed", panel_style(ACCENT.darkened(0.18) if accent else PANEL.darkened(0.08), ACCENT, RADIUS, 9, 3))
	button.add_theme_stylebox_override("focus", focus_style())


static func style_input(control: Control) -> void:
	control.custom_minimum_size.y = control_height()
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.add_theme_font_size_override("font_size", font_size())
	control.add_theme_color_override("font_color", TEXT)
	control.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	control.add_theme_color_override("caret_color", ACCENT)
	control.add_theme_color_override("selection_color", ACCENT_DARK)
	control.add_theme_stylebox_override("normal", panel_style(FIELD, BORDER, RADIUS, 7, 3))
	control.add_theme_stylebox_override("focus", panel_style(FIELD_FOCUS, ACCENT, RADIUS, 7, 3))
	control.add_theme_stylebox_override("read_only", panel_style(BG_ALT, BORDER.darkened(0.15), RADIUS, 7, 3))


static func style_option(button: OptionButton) -> void:
	style_button(button, false)
	style_popup_menu(button.get_popup())


static func style_spinbox(spin: SpinBox) -> void:
	style_input(spin)
	if spin.has_method("get_line_edit"):
		var line_edit: LineEdit = spin.get_line_edit()
		if line_edit != null:
			style_input(line_edit)


static func style_popup_menu(popup: PopupMenu) -> void:
	if popup == null:
		return
	popup.add_theme_font_size_override("font_size", font_size())
	popup.add_theme_color_override("font_color", TEXT)
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	popup.add_theme_color_override("font_disabled_color", TEXT_DIM)
	popup.add_theme_stylebox_override("panel", panel_style(BG, BORDER, RADIUS, 4, 4))
	popup.add_theme_stylebox_override("hover", panel_style(ACCENT_DARK, ACCENT, RADIUS, 6, 2))
	popup.add_theme_stylebox_override("separator", panel_style(BORDER, BORDER, 0, 0, 0))


static func apply_tree(root: Node, accent_save: bool = true) -> void:
	if root is HBoxContainer or root is VBoxContainer:
		(root as BoxContainer).add_theme_constant_override("separation", scaled_int(4))
	if root is Label:
		style_label(root as Label, FONT_SIZE, TEXT)
	elif root is RichTextLabel:
		style_rich_text(root as RichTextLabel, FONT_SIZE)
	elif root is SpinBox:
		style_spinbox(root as SpinBox)
	elif root is LineEdit or root is TextEdit:
		style_input(root as Control)
	elif root is OptionButton:
		style_option(root as OptionButton)
	elif root is Button:
		var button := root as Button
		style_button(button, accent_save and button.text == "Save")
	elif root is CheckBox:
		var check := root as CheckBox
		check.add_theme_font_size_override("font_size", font_size())
		check.add_theme_color_override("font_color", TEXT)
		check.custom_minimum_size.y = control_height()
	elif root is PanelContainer:
		(root as PanelContainer).add_theme_stylebox_override("panel", panel_style(BG_ALT, BORDER, RADIUS, 5, 3))
	for child in root.get_children():
		apply_tree(child, accent_save)


static func panel_style(bg: Color, border: Color, radius: int = RADIUS, h_margin: int = 6, v_margin: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(scaled_int(1))
	style.set_corner_radius_all(scaled_int(radius))
	style.content_margin_left = scaled_int(h_margin)
	style.content_margin_right = scaled_int(h_margin)
	style.content_margin_top = scaled_int(v_margin)
	style.content_margin_bottom = scaled_int(v_margin)
	return style


static func focus_style() -> StyleBoxFlat:
	var style := panel_style(Color.TRANSPARENT, ACCENT, RADIUS, 2, 2)
	style.set_border_width_all(scaled_int(1))
	return style


static func ui_scale() -> float:
	var scale: float = 1.0
	if _editor_scale_override > 0.0:
		return _editor_scale_override
	if Engine.has_singleton("EditorInterface"):
		var editor_interface: Object = Engine.get_singleton("EditorInterface")
		if editor_interface != null and editor_interface.has_method("get_editor_scale"):
			scale = max(scale, float(editor_interface.call("get_editor_scale")))
	return scale


static func scaled(value: float) -> float:
	return value * ui_scale()


static func scaled_int(value: int) -> int:
	return int(round(float(value) * ui_scale()))


static func scaled_font_size(size: int) -> int:
	if _editor_font_size_override > 0:
		if size <= FONT_SIZE_TINY:
			return max(1, _editor_font_size_override - 3)
		if size <= FONT_SIZE_SMALL:
			return max(1, _editor_font_size_override - 2)
		return _editor_font_size_override
	return scaled_int(size)


static func font_size() -> int:
	return scaled_font_size(FONT_SIZE)


static func font_size_small() -> int:
	return scaled_font_size(FONT_SIZE_SMALL)


static func font_size_tiny() -> int:
	return scaled_font_size(FONT_SIZE_TINY)


static func control_height() -> int:
	return scaled_int(CONTROL_HEIGHT)


static func cell_height() -> int:
	return scaled_int(CELL_HEIGHT)
