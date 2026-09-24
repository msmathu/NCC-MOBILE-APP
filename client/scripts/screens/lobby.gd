extends Control
## Parade room: shows the code, the 7 slots, and the auto-start countdown.
## Host can start early (empty slots become bot cadets) and toggle squad roles.

const Preview := preload("res://scripts/screens/cadet_preview.gd")

var main: Node
var data: Dictionary
var room: Dictionary
var code_label: Label
var status_label: Label
var count_label: Label
var slots: HBoxContainer
var start_btn: Button
var roles_btn: CheckButton
var cheer_row: HBoxContainer
var countdown := 0.0
var _said_attention := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var col := UI.vbox(14)
	margin.add_child(col)
	var top := UI.hbox(20)
	var title := UI.vbox(0)
	title.add_child(UI.label("PARADE ROOM", 22, UI.KHAKI_LIGHT))
	code_label = UI.label("#----", 64, UI.GOLD)
	title.add_child(code_label)
	top.add_child(title)
	var info := UI.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = UI.label("", 24, UI.WHITE)
	info.add_child(status_label)
	info.add_child(UI.label("Share the code with your squad. Race starts automatically at 7/7.", 18, UI.KHAKI_LIGHT))
	top.add_child(info)
	count_label = UI.label("", 90, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	count_label.custom_minimum_size = Vector2(160, 0)
	top.add_child(count_label)
	col.add_child(top)
	slots = UI.hbox(10)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(slots)
	cheer_row = UI.hbox(8)
	cheer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for e in Course.CHEERS:
		var b := Button.new()
		b.text = e
		b.custom_minimum_size = Vector2(60, 54)
		b.pressed.connect(func() -> void: Net.send({"t": "cheer", "e": e}))
		cheer_row.add_child(b)
	col.add_child(cheer_row)
	var bottom := UI.hbox(14)
	bottom.add_child(UI.button("LEAVE", func() -> void: Net.send({"t": "leave"}), 180))
	bottom.add_child(UI.spacer(0, true))
	roles_btn = CheckButton.new()
	roles_btn.text = "Squad roles"
	roles_btn.toggled.connect(func(v: bool) -> void: Net.send({"t": "roles", "on": v}))
	bottom.add_child(roles_btn)
	start_btn = UI.button("START NOW  (fill with bots)", func() -> void: Net.send({"t": "start"}))
	bottom.add_child(start_btn)
	col.add_child(bottom)
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
	if spectating:
		status_label.text += "\nRoom full - you are SPECTATING. Send cheers!"
	elif r.isPublic:
		status_label.text += "   (Quick Join room)"
	start_btn.visible = is_host and r.state == "waiting"
	roles_btn.visible = is_host and r.state == "waiting"
	roles_btn.set_pressed_no_signal(r.rolesMode)
	cheer_row.visible = true
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


func _slot(p: Dictionary, i: int, host: String) -> Control:
	var panel := UI.panel(8)
	panel.custom_minimum_size = Vector2(160, 250)
	var v := UI.vbox(4)
	var preview := Preview.new()
	preview.custom_minimum_size = Vector2(0, 150)
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


func _on_cheer(msg: Dictionary) -> void:
	Sfx.play("cheer")
	main.toast("%s  %s" % [msg.e, msg.from], UI.WHITE)
