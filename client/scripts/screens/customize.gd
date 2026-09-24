extends Control
## Uniforms, berets and badges. Options unlock as the cadet ranks up.

const Preview := preload("res://scripts/screens/cadet_preview.gd")

var main: Node
var data: Dictionary
var look: Dictionary
var preview: Control
var rows := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look = Profile.look.duplicate()
	var p := UI.panel(26)
	var h := UI.hbox(30)
	preview = Preview.new()
	preview.look = look
	preview.art_scale = 2.4
	preview.pose = "run"
	preview.custom_minimum_size = Vector2(300, 400)
	h.add_child(preview)
	var col := UI.vbox(12)
	col.add_child(UI.label("QUARTERMASTER STORES", 36, UI.GOLD))
	col.add_child(UI.label("Rank: " + Course.RANKS[Profile.rank_index()].name, 20, UI.KHAKI_LIGHT))
	for kind in ["uniform", "beret", "badge"]:
		col.add_child(UI.label(kind.to_upper(), 20, UI.KHAKI_LIGHT))
		var row := UI.hbox(8)
		rows[kind] = row
		col.add_child(row)
	var gear := CheckBox.new()
	gear.text = "Preview full tactical gear (Level 3)"
	gear.toggled.connect(func(v: bool) -> void: preview.gear = v)
	col.add_child(gear)
	var buttons := UI.hbox(12)
	buttons.add_child(UI.button("SAVE", _save, 180))
	buttons.add_child(UI.button("BACK", func() -> void: main.go("menu"), 180))
	col.add_child(buttons)
	h.add_child(col)
	p.add_child(h)
	add_child(UI.centered(p))
	_refresh()


func _refresh() -> void:
	for kind in rows:
		var row: HBoxContainer = rows[kind]
		for c in row.get_children():
			c.queue_free()
		for option in Course.UNLOCKS[kind]:
			var need: int = Course.UNLOCKS[kind][option]
			var b := Button.new()
			b.custom_minimum_size = Vector2(0, 54)
			b.add_theme_font_size_override("font_size", 18)
			var unlocked := Profile.is_unlocked(kind, option)
			b.text = Course.LABELS[option] if unlocked else "🔒 " + Course.RANKS[need].name
			b.disabled = not unlocked
			if look[kind] == option:
				b.add_theme_color_override("font_color", UI.GOLD)
				b.text = "✔ " + b.text
			b.pressed.connect(func() -> void:
				look[kind] = option
				Sfx.play("tap")
				_refresh())
			row.add_child(b)
	preview.look = look


func _save() -> void:
	Profile.look = look.duplicate()
	Profile.save()
	if Net.online:
		Net.send({"t": "look", "uniform": look.uniform, "beret": look.beret, "badge": look.badge})
	main.toast("Uniform updated. Looking sharp, cadet!")
	main.go("menu")
