extends Control
## Race results: finishing order, times, Drill Points earned and rank progress.

var main: Node
var data: Dictionary
var _rank_before := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rank_before = Profile.rank_index()
	var practice: bool = data.get("practice", false)
	var room: Dictionary = data.get("room", {})
	var rows: Array = data.get("results", []) if practice else room.get("results", [])
	var my_id := "me" if practice else Net.my_id
	var p := UI.panel(26)
	p.custom_minimum_size = Vector2(820, 0)
	var col := UI.vbox(8)
	var mine: Dictionary = {}
	for r in rows:
		if r.id == my_id:
			mine = r
	var headline := "PRACTICE COMPLETE" if practice else "PARADE DISMISSED"
	if not mine.is_empty() and mine.place == 1:
		headline = "FIRST PLACE! SHABASH!"
		Sfx.say("good")
	col.add_child(UI.label(headline, 42, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	for r in rows:
		col.add_child(_row(r, r.id == my_id, practice))
	col.add_child(UI.spacer(6))
	if practice:
		col.add_child(UI.label("Practice races don't award Drill Points. Race online to rank up!", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	elif not mine.is_empty():
		var s := Profile.stats
		var line := "+%d DP   -   Total %d DP   -   %s" % [mine.dp, int(s.get("dp", 0)), s.get("rank", "Cadet")]
		col.add_child(UI.label(line, 24, UI.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons := UI.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	if practice:
		buttons.add_child(UI.button("RACE AGAIN", func() -> void: main.start_practice(), 240))
		buttons.add_child(UI.button("MENU", func() -> void: main.go("menu"), 200))
	else:
		if room.get("host", "") == Net.my_id:
			buttons.add_child(UI.button("REMATCH", func() -> void: Net.send({"t": "rematch"}), 240))
		else:
			col.add_child(UI.label("Waiting for the host to call a rematch...", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
		buttons.add_child(UI.button("LEAVE ROOM", func() -> void: Net.send({"t": "leave"}), 240))
	col.add_child(buttons)
	p.add_child(col)
	add_child(UI.centered(p))
	Sfx.play("finish")
	Net.profile.connect(_on_profile)
	_on_profile(Profile.stats)


func _row(r: Dictionary, is_me: bool, practice: bool) -> Control:
	var h := UI.hbox(16)
	var place := "DNF" if r.place == null else "#%d" % r.place
	var c := UI.GOLD if is_me else UI.WHITE
	var pl := UI.label(place, 24, c)
	pl.custom_minimum_size = Vector2(70, 0)
	h.add_child(pl)
	var name := UI.label(r.name + ("  (bot)" if r.bot else "") + ("  - " + Course.ROLE_INFO[r.role].name if r.get("role", "cadet") != "cadet" else ""), 24, c)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	h.add_child(UI.label(Course.format_ms(r.ms if r.ms != null else -1.0), 24, c))
	if not practice:
		var dp := UI.label("+%d DP" % r.dp if not r.bot else "", 22, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
		dp.custom_minimum_size = Vector2(110, 0)
		h.add_child(dp)
	return h


func _on_profile(p: Dictionary) -> void:
	var ri := Course.rank_index(int(p.get("dp", 0)))
	if ri > _rank_before:
		_rank_before = ri
		main.toast("PROMOTED to %s! New customizations unlocked." % Course.RANKS[ri].name)
		Sfx.play("whistle")
