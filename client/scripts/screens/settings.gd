extends Control
## Voice / music / tilt settings, server address and identity.

var main: Node
var data: Dictionary
var server_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UI.panel(30)
	p.custom_minimum_size = Vector2(700, 0)
	var col := UI.vbox(12)
	col.add_child(UI.label("SETTINGS", 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_toggle("Drill voice commands (Tez Chal, Tham...)", Profile.voice_on, func(v: bool) -> void: Profile.voice_on = v))
	col.add_child(_toggle("Hindi voice (when the phone has one)", Profile.voice_hindi, func(v: bool) -> void: Profile.voice_hindi = v))
	col.add_child(_toggle("Parade march music", Profile.music_on, func(v: bool) -> void: Profile.music_on = v))
	col.add_child(_toggle("Invert tilt steering", Profile.invert_tilt, func(v: bool) -> void: Profile.invert_tilt = v))
	col.add_child(UI.label("Game server address  (auto = official online server, plays from anywhere)", 18, UI.KHAKI_LIGHT))
	server_edit = LineEdit.new()
	server_edit.text = Profile.server_url
	server_edit.placeholder_text = "auto   or   ws://192.168.1.10:2567"
	col.add_child(server_edit)
	var row := UI.hbox(12)
	var save := UI.button("SAVE", _save)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save)
	var rename := UI.button("CHANGE NAME / DTE", func() -> void: main.go("title"))
	rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rename)
	col.add_child(row)
	col.add_child(UI.button("BACK", func() -> void: main.go("menu")))
	p.add_child(col)
	add_child(UI.centered(p))


func _toggle(text: String, on: bool, apply: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(func(v: bool) -> void:
		apply.call(v)
		Profile.save())
	return c


func _save() -> void:
	var url := server_edit.text.strip_edges()
	if url == "" or url.to_lower() == "auto":
		url = Profile.DEFAULT_SERVER
	elif not (url.begins_with("ws://") or url.begins_with("wss://")):
		url = "ws://" + url
	if url != Profile.server_url:
		Profile.server_url = url
		Profile.save()
		Net.stop()
		Net.start()
	main.toast("Saved")
	main.go("menu")
