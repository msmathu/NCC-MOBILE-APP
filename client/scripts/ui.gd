class_name UI
## Palette, theme and small widget builders shared by every screen.

const OLIVE := Color("4b5320")
const OLIVE_DARK := Color("2f3515")
const KHAKI := Color("c3b091")
const KHAKI_LIGHT := Color("e6dcc3")
const NAVY := Color("1f2a44")
const SKY := Color("7ec8e3")
const GOLD := Color("d4a017")
const RED := Color("c0392b")
const WHITE := Color("f7f3e8")
const GREEN_OK := Color("2ecc71")

## Marker colours for the 7 cadets on the track map.
const LANE_COLORS := [Color("d4a017"), Color("e74c3c"), Color("3498db"), Color("2ecc71"), Color("9b59b6"), Color("e67e22"), Color("1abc9c")]


static func make_theme() -> Theme:
	_add_emoji_fallback()
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))

	var btn := _box(OLIVE, GOLD, 3, 12)
	var hover := _box(OLIVE.lightened(0.12), GOLD, 3, 12)
	var pressed := _box(OLIVE_DARK, GOLD.darkened(0.2), 3, 12)
	var disabled := _box(Color(0.3, 0.3, 0.3, 0.8), Color(0.45, 0.45, 0.45), 2, 12)
	for s in [btn, hover, pressed, disabled]:
		s.content_margin_left = 22
		s.content_margin_right = 22
		s.content_margin_top = 12
		s.content_margin_bottom = 12
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", GOLD.lightened(0.4))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.7, 0.7, 0.7))
	t.set_font_size("font_size", "Button", 26)

	var field := _box(Color(0.1, 0.12, 0.05, 0.85), KHAKI, 2, 8)
	field.content_margin_left = 14
	field.content_margin_right = 14
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _box(Color(0.1, 0.12, 0.05, 0.95), GOLD, 3, 8))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_font_size("font_size", "LineEdit", 26)
	t.set_stylebox("normal", "OptionButton", btn)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_font_size("font_size", "CheckButton", 22)
	t.set_font_size("font_size", "CheckBox", 22)

	t.set_stylebox("panel", "PanelContainer", _box(Color(0.12, 0.15, 0.08, 0.88), KHAKI.darkened(0.2), 2, 16))
	t.set_stylebox("panel", "Panel", _box(Color(0.12, 0.15, 0.08, 0.88), KHAKI.darkened(0.2), 2, 16))
	var bar_bg := _box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 6)
	var bar_fg := _box(GOLD, Color(0, 0, 0, 0), 0, 6)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	t.set_font_size("font_size", "ProgressBar", 16)
	return t


## Browsers give Godot no system-font fallback, so emoji (cheers, locks, ticks)
## would render as boxes. Bundled Noto Emoji (SIL OFL) fills the gaps everywhere.
static func _add_emoji_fallback() -> void:
	var base := ThemeDB.fallback_font
	var emoji: Font = load("res://fonts/NotoEmoji.ttf")
	if base and emoji and not base.fallbacks.has(emoji):
		var list := base.fallbacks.duplicate()
		list.append(emoji)
		base.fallbacks = list


static func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


static func label(text: String, size := 24, color := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if size >= 30:
		l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, on_press: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.pressed.connect(func() -> void:
		Sfx.play("tap")
		on_press.call())
	return b


static func vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(pad := 24) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(Color(0.12, 0.15, 0.08, 0.9), KHAKI.darkened(0.2), 2, 16)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", s)
	return p


static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func spacer(h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func toast(parent: Node, text: String, color := GOLD) -> void:
	var l := label(text, 26, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.position.y -= 90
	l.add_theme_constant_override("outline_size", 8)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
