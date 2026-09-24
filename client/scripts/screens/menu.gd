extends Control
## Parade ground: rank card, quick join, create / join room, practice and extras.

var main: Node
var data: Dictionary
var code_edit: LineEdit
var roles_box: CheckBox
var online_buttons: Array[Button] = []
var rank_label: Label
var dp_bar: ProgressBar
var dp_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var row := UI.hbox(30)
	margin.add_child(row)

	# left: rank card
	var card := UI.panel()
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cv := UI.vbox(10)
	var preview := preload("res://scripts/screens/cadet_preview.gd").new()
	preview.look = Profile.look
	preview.art_scale = 1.6
	preview.custom_minimum_size = Vector2(0, 200)
	cv.add_child(preview)
	cv.add_child(UI.label(Profile.cadet_name, 34, UI.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	rank_label = UI.label("", 24, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(rank_label)
	var dir := UI.label(Profile.directorate + " Dte", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	dir.autowrap_mode = TextServer.AUTOWRAP_WORD
	cv.add_child(dir)
	dp_bar = ProgressBar.new()
	dp_bar.custom_minimum_size = Vector2(0, 22)
	dp_bar.show_percentage = false
	cv.add_child(dp_bar)
	dp_label = UI.label("", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(dp_label)
	card.add_child(cv)
	row.add_child(card)

	# right: actions
	var col := UI.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label("NCC CADET CHALLENGE", 44, UI.GOLD))
	var quick := UI.button("QUICK JOIN  -  random squad", func() -> void: Net.send({"t": "quick"}))
	col.add_child(quick)
	online_buttons.append(quick)
	var create_row := UI.hbox(12)
	var create := UI.button("CREATE PARADE ROOM", func() -> void: Net.send({"t": "create", "roles": roles_box.button_pressed}))
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(create)
	online_buttons.append(create)
	roles_box = CheckBox.new()
	roles_box.text = "Squad roles"
	roles_box.tooltip_text = "SUO/JUO speed aura, Scout early warnings, Support wall boost"
	create_row.add_child(roles_box)
	col.add_child(create_row)
	var join_row := UI.hbox(12)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "Room code  e.g. K7QM"
	code_edit.max_length = 8
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(code_edit)
	var join := UI.button("JOIN", _join, 150)
	join_row.add_child(join)
	online_buttons.append(join)
	col.add_child(join_row)
	col.add_child(UI.button("PRACTICE DRILL  -  offline vs bots", func() -> void: main.start_practice()))
	var extras := UI.hbox(12)
	for item in [["CUSTOMIZE", "customize"], ["LEADERBOARD", "board"], ["SETTINGS", "settings"]]:
		var target: String = item[1]
		var b := UI.button(item[0], func() -> void: main.go(target))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		extras.add_child(b)
		if target == "board":
			online_buttons.append(b)
	col.add_child(extras)
	if OS.has_feature("web"):
		col.add_child(UI.button("GET THE ANDROID APP", func() -> void: OS.shell_open("download/ncc-cadet-challenge.apk")))
	row.add_child(col)

	Net.online_changed.connect(_refresh_online)
	Net.profile.connect(func(_p: Dictionary) -> void: _refresh_rank())
	Net.welcome.connect(func(_m: Dictionary) -> void: _refresh_rank())
	_refresh_online(Net.online)
	_refresh_rank()
	Sfx.music(false)


func _join() -> void:
	var code := code_edit.text.strip_edges().to_upper().trim_prefix("#")
	if code.length() < 4:
		main.toast("Enter the 4-character room code", UI.RED)
		return
	Net.send({"t": "join", "code": code})


func _refresh_online(online: bool) -> void:
	for b in online_buttons:
		b.disabled = not online


func _refresh_rank() -> void:
	var s := Profile.stats
	var dp := int(s.get("dp", 0))
	var ri := Course.rank_index(dp)
	rank_label.text = Course.RANKS[ri].name.to_upper()
	var lo: int = Course.RANKS[ri].dp
	var hi: int = Course.RANKS[ri + 1].dp if ri + 1 < Course.RANKS.size() else lo
	dp_bar.max_value = maxi(1, hi - lo)
	dp_bar.value = dp - lo if hi > lo else dp_bar.max_value
	var next := ("   Next: %s at %d DP" % [Course.RANKS[ri + 1].name, hi]) if hi > lo else "   Highest rank!"
	dp_label.text = "%d Drill Points%s\nRaces %d  -  Wins %d" % [dp, next, int(s.get("races", 0)), int(s.get("wins", 0))]
