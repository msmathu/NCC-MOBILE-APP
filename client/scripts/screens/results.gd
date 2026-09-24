extends Control
## Camp results: finishing order with each level's result (L1 course place/time,
## L2 range score, L3 map score), camp points, Drill Points and rank progress.

var main: Node
var data: Dictionary
var _rank_before := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rank_before = Profile.rank_index()
	var practice: bool = data.get("practice", false)
	var which: String = data.get("which", "camp")
	var room: Dictionary = data.get("room", {})
	var rows: Array = data.get("results", []) if practice else room.get("results", [])
	var my_id := "me" if practice else Net.my_id
	var p := UI.panel(22)
	p.custom_minimum_size = Vector2(1000, 0)
	var col := UI.vbox(6)
	var mine: Dictionary = {}
	for r in rows:
		if r.id == my_id:
			mine = r
	var titles := {"camp": "CAMP COMPETITION RESULTS", "course": "LEVEL 1 - OBSTACLE COURSE",
		"range": "LEVEL 2 - TARGET PRACTICE", "map": "LEVEL 3 - MAP READING"}
	var headline: String = titles.get(which, "RESULTS")
	if not mine.is_empty() and mine.place == 1:
		headline = "BEST CADET OF THE CAMP! SHABASH!" if which == "camp" else "FIRST PLACE! SHABASH!"
		Sfx.say("good")
	col.add_child(UI.label(headline, 36, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var show := {
		"course": which in ["camp", "course"], "range": which in ["camp", "range"],
		"map": which in ["camp", "map"], "points": which == "camp", "dp": not practice,
	}
	col.add_child(_row({}, false, show, true))
	for r in rows:
		col.add_child(_row(r, r.id == my_id, show, false))
	col.add_child(UI.spacer(4))
	if practice:
		if which == "range" and not mine.is_empty():
			col.add_child(UI.label("Your range card: %d / 50  -  %s" % [int(mine.rangeScore), Course.qualification(int(mine.rangeScore))], 22, UI.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UI.label("Practice doesn't award Drill Points. Play online to rank up!", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	elif not mine.is_empty():
		var s := Profile.stats
		var line := "+%d DP   -   Total %d DP   -   %s" % [mine.dp, int(s.get("dp", 0)), s.get("rank", "Cadet")]
		if mine.get("rangeScore") != null:
			line += "   -   Range: " + Course.qualification(int(mine.rangeScore))
		col.add_child(UI.label(line, 20, UI.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons := UI.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	if practice:
		buttons.add_child(UI.button("PLAY AGAIN", func() -> void: main.start_practice(which), 240))
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


func _cell(text: String, w: float, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER, sz := 21) -> Label:
	var l := UI.label(text, sz, c, align)
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _row(r: Dictionary, is_me: bool, show: Dictionary, header: bool) -> Control:
	var h := UI.hbox(10)
	var c := UI.KHAKI if header else (UI.GOLD if is_me else UI.WHITE)
	var sz := 16 if header else 21
	h.add_child(_cell("#" if header else "#%d" % r.place, 56, c, HORIZONTAL_ALIGNMENT_LEFT, sz))
	var name: String = "CADET" if header else r.name + ("  (bot)" if r.bot else "")
	if not header and r.get("role", "cadet") != "cadet":
		name += "  - " + Course.ROLE_INFO[r.role].name
	var n := _cell(name, 0, c, HORIZONTAL_ALIGNMENT_LEFT, sz)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	if show.course:
		var t := "L1 COURSE"
		if not header:
			t = "DNF" if r.get("coursePlace") == null else "%s (#%d)" % [Course.format_ms(r.ms if r.ms != null else -1.0), int(r.coursePlace)]
		h.add_child(_cell(t, 190, c, HORIZONTAL_ALIGNMENT_CENTER, sz))
	if show.range:
		h.add_child(_cell("L2 RANGE" if header else _score(r.get("rangeScore")), 110, c, HORIZONTAL_ALIGNMENT_CENTER, sz))
	if show.map:
		h.add_child(_cell("L3 MAP" if header else _score(r.get("mapScore")), 110, c, HORIZONTAL_ALIGNMENT_CENTER, sz))
	if show.points:
		h.add_child(_cell("POINTS" if header else str(int(r.get("points", 0))), 90, c, HORIZONTAL_ALIGNMENT_CENTER, sz))
	if show.dp:
		h.add_child(_cell("DP" if header else ("" if r.bot else "+%d" % r.dp), 80, UI.KHAKI_LIGHT if not header else c, HORIZONTAL_ALIGNMENT_RIGHT, sz))
	return h


func _score(v) -> String:
	return "-" if v == null else "%d/50" % int(v)


func _on_profile(p: Dictionary) -> void:
	var ri := Course.rank_index(int(p.get("dp", 0)))
	if ri > _rank_before:
		_rank_before = ri
		main.toast("PROMOTED to %s! New customizations unlocked." % Course.RANKS[ri].name)
		Sfx.play("whistle")
