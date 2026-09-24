extends Control
## First launch: pick a cadet name and directorate. No password, email or login.

var main: Node
var data: Dictionary
var name_edit: LineEdit
var dir_pick: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := UI.vbox(16)
	col.custom_minimum_size = Vector2(620, 0)
	col.add_child(UI.label("NCC CADET CHALLENGE", 54, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.label("Ekta aur Anushasan  -  Unity & Discipline", 22, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(10))
	var p := UI.panel()
	var form := UI.vbox(12)
	form.add_child(UI.label("Cadet name", 20, UI.KHAKI_LIGHT))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "e.g. Cdt Ravi"
	name_edit.max_length = 16
	name_edit.text = Profile.cadet_name
	name_edit.text_submitted.connect(func(_t: String) -> void: _fall_in())
	form.add_child(name_edit)
	form.add_child(UI.label("NCC Directorate (for the state leaderboard)", 20, UI.KHAKI_LIGHT))
	dir_pick = OptionButton.new()
	for d in Course.DIRECTORATES:
		dir_pick.add_item(d)
	dir_pick.select(maxi(0, Course.DIRECTORATES.find(Profile.directorate)))
	form.add_child(dir_pick)
	form.add_child(UI.spacer(6))
	form.add_child(UI.button("FALL IN!", _fall_in))
	p.add_child(form)
	col.add_child(p)
	col.add_child(UI.label("No sign-up needed. Just a name and you're on parade.", 18, UI.KHAKI, HORIZONTAL_ALIGNMENT_CENTER))
	add_child(UI.centered(col))


func _fall_in() -> void:
	var n := name_edit.text.strip_edges()
	var clean := ""
	for ch in n:
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in " .-_":
			clean += ch
	if clean.strip_edges().length() < 2:
		main.toast("Name must be at least 2 letters", UI.RED)
		return
	Profile.cadet_name = clean.strip_edges()
	Profile.directorate = Course.DIRECTORATES[dir_pick.selected]
	Profile.save()
	Net.stop()
	Net.start()
	main.go("menu")
