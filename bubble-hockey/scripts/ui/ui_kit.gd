class_name UIKit
extends RefCounted
## Small helpers for building the code-driven UI with one consistent look.

const BG := Color("0f1a2e")
const PANEL := Color("17253f")
const PANEL_EDGE := Color("2a4170")
const TEXT := Color("f4f7fb")
const MUTED := Color("9fb0c8")
const ACCENT := Color("f0c419")
const RED := Color("d93a32")
const BLUE := Color("2f6fd6")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "Button", _box(PANEL, PANEL_EDGE))
	t.set_stylebox("hover", "Button", _box(PANEL.lightened(0.08), ACCENT))
	t.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("disabled", "Button", _box(PANEL.darkened(0.3), PANEL_EDGE))
	t.set_stylebox("normal", "LineEdit", _box(BG, PANEL_EDGE))
	t.set_stylebox("focus", "LineEdit", _box(BG, ACCENT))
	t.set_stylebox("panel", "PanelContainer", _box(Color(PANEL, 0.97), PANEL_EDGE, 24, 32))
	return t


static func _box(fill: Color, edge: Color, radius := 18, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 6
	s.content_margin_right = pad + 6
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func label(text: String, size := 30, color := TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, size := 32) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Sfx.play("click")
		on_press.call())
	return b


static func column(spacing := 18) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", spacing)
	return v


## A centered panel with a fixed width, for menus and overlays.
static func centered_panel(parent: Control, width := 600.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var v := column()
	panel.add_child(v)
	return v


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
