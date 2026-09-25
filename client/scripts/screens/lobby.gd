extends Control
## Parade room: shows the code, the 7 slots, and the start countdown.
## - 7/7 cadets: starts automatically.
## - 2+ cadets: bots fill the empty slots automatically after a short timer.
## - Host: START NOW fills with bots at once. Other cadets: VOTE START (majority).
## All buttons sit in one bottom bar so they stay on screen at any window size.

const Preview := preload("res://scripts/screens/cadet_preview.gd")

var main: Node
var data: Dictionary
var room: Dictionary
var code_label: Label
var status_label: Label
var hint_label: Label
var count_label: Label
var slots: HBoxContainer
var start_btn: Button
var roles_btn: CheckButton
var countdown := 0.0
var autofill := 0.0
var _said_attention := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_bottom", 36) # room for the online counter
	add_child(margin)
	var col := UI.vbox(12)
	margin.add_child(col)

	var top := UI.hbox(20)
	var title := UI.vbox(0)
	title.add_child(UI.label("PARADE ROOM", 20, UI.KHAKI_LIGHT))
	code_label = UI.label("#----", 56, UI.GOLD)
	title.add_child(code_label)
	top.add_child(title)
	var info := UI.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = UI.label("", 24, UI.WHITE)
	info.add_child(status_label)
	hint_label = UI.label("", 18, UI.KHAKI_LIGHT)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(hint_label)
	top.add_child(info)
	count_label = UI.label("", 80, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	count_label.custom_minimum_size = Vector2(130, 0)
	top.add_child(count_label)
	col.add_child(top)

	slots = UI.hbox(10)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(slots)
	col.add_child(UI.spacer(0, true))

	var bar := UI.hbox(8)
	bar.add_child(UI.button("LEAVE", func() -> void: Net.send({"t": "leave"}), 130))
	for e in Course.CHEERS:
		var b := Button.new()
		b.text = e
		b.custom_minimum_size = Vector2(50, 50)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void: Net.send({"t": "cheer", "e": e}))
		bar.add_child(b)
	bar.add_child(UI.spacer(0, true))
	roles_btn = CheckButton.new()
	roles_btn.text = "Squad roles"
	roles_btn.toggled.connect(func(v: bool) -> void: Net.send({"t": "roles", "on": v}))
	bar.add_child(roles_btn)
	start_btn = UI.button("START NOW", func() -> void: Net.send({"t": "start"}), 250)
	bar.add_child(start_btn)
	col.add_child(bar)

	Net.room.connect(_on_room)
	Net.cheer.connect(_on_cheer)
	_on_room(data.room)


func _on_room(r: Dictionary) -> void:
	room = r
	if r.state != "waiting" and r.state != "countdown":
		return
	code_label.text = "#" + r.code
	var is_host: bool = r.host == Net.my_id
	var spectating: bool = r.get("spectating", false)
	var n: int = r.players.size()
	status_label.text = "%d / %d cadets fallen in%s" % [n, r.size, ("   -   %d watching" % r.spectators) if r.spectators > 0 else ""]
	if r.isPublic:
		status_label.text += "   (Quick Join room)"
	autofill = r.get("autoFillMs", 0) / 1000.0
	var waiting: bool = r.state == "waiting"
	start_btn.visible = waiting and not spectating
	roles_btn.visible = waiting and is_host
	roles_btn.set_pressed_no_signal(r.rolesMode)
	if waiting and not spectating:
		var humans := 0
		for p in r.players:
			if not p.bot and p.connected:
				humans += 1
		var votes: Array = r.get("startVotes", [])
		var need := humans / 2 + 1
		if is_host:
			start_btn.text = "START NOW  (+ bots)"
			start_btn.disabled = false
		elif votes.has(Net.my_id):
			start_btn.text = "VOTED  %d/%d" % [votes.size(), need]
			start_btn.disabled = true
		else:
			start_btn.text = "VOTE START  %d/%d" % [votes.size(), need]
			start_btn.disabled = false
	for c in slots.get_children():
		c.queue_free()
	for i in r.size:
		slots.add_child(_slot(r.players[i] if i < n else {}, i, r.host))
	if r.state == "countdown":
		countdown = r.countdownMs / 1000.0
		if not _said_attention:
			_said_attention = true
			Sfx.say("attention")
			Sfx.play("whistle")
	else:
		countdown = 0.0
		_said_attention = false
	_refresh_hint()


func _refresh_hint() -> void:
	if room.is_empty():
		return
	if room.get("spectating", false):
		hint_label.text = "Room is full - you are SPECTATING. Send cheers!"
	elif room.state == "countdown":
		hint_label.text = "Fall in! The camp is starting."
	elif autofill > 0.0:
		hint_label.text = "Bots fill the empty places in %ds - or press %s." % [ceili(autofill), "START NOW" if room.host == Net.my_id else "VOTE START"]
	else:
		hint_label.text = "Share code #%s with your squad. Starts at 7/7, or with 2+ cadets bots fill in after 45s." % room.code


func _slot(p: Dictionary, i: int, host: String) -> Control:
	var panel := UI.panel(8)
	panel.custom_minimum_size = Vector2(150, 190)
	var v := UI.vbox(2)
	var preview := Preview.new()
	preview.custom_minimum_size = Vector2(0, 120)
	if not p.is_empty():
		preview.look = {"uniform": p.uniform, "beret": p.beret, "badge": p.badge}
		preview.pose = "run" if p.id == Net.my_id else "idle"
	v.add_child(preview)
	if p.is_empty():
		v.add_child(UI.label("waiting...", 18, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var name: String = p.name
		if p.id == host:
			name = "⭐ " + name
		var l := UI.label(name, 18, UI.GOLD if p.id == Net.my_id else UI.LANE_COLORS[i], HORIZONTAL_ALIGNMENT_CENTER)
		l.clip_text = true
		v.add_child(l)
		var sub := "BOT" if p.bot else (p.directorate as String).get_slice(" ", 0)
		if not p.connected:
			sub = "reconnecting..."
		elif (room.get("startVotes", []) as Array).has(p.id):
			sub += "  - voted start"
		v.add_child(UI.label(sub, 14, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER))
	panel.add_child(v)
	return panel


func _process(d: float) -> void:
	if countdown > 0.0:
		var before := ceili(countdown)
		countdown = maxf(0.0, countdown - d)
		count_label.text = str(ceili(countdown))
		if ceili(countdown) != before and countdown <= 3.0:
			Sfx.play("tap", 1.5)
	else:
		count_label.text = ""
	if autofill > 0.0:
		var before := ceili(autofill)
		autofill = maxf(0.0, autofill - d)
		if ceili(autofill) != before:
			_refresh_hint()


func _on_cheer(msg: Dictionary) -> void:
	Sfx.play("cheer")
	main.toast("%s  %s" % [msg.e, msg.from], UI.WHITE)
