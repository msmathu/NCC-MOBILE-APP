extends Node
## App shell: owns the theme, backdrop and current screen, and routes between
## screens when the server's room state changes. Menu UI lives on its own
## CanvasLayer so the race camera never moves it.

const Backdrop := preload("res://scripts/screens/backdrop.gd")
const SCREENS := {
	"title": preload("res://scripts/screens/title.gd"),
	"menu": preload("res://scripts/screens/menu.gd"),
	"lobby": preload("res://scripts/screens/lobby.gd"),
	"results": preload("res://scripts/screens/results.gd"),
	"customize": preload("res://scripts/screens/customize.gd"),
	"board": preload("res://scripts/screens/leaderboard.gd"),
	"settings": preload("res://scripts/screens/settings.gd"),
	"range": preload("res://scripts/screens/range.gd"),
	"mapread": preload("res://scripts/screens/mapread.gd"),
}
const Race := preload("res://scripts/race/race.gd")

var current: Node
var current_name := ""
var root: Control
var backdrop: Control
var status: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	root = Control.new()
	root.theme = UI.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	backdrop = Backdrop.new()
	root.add_child(backdrop)
	status = UI.label("", 16, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status.offset_left = -320
	status.offset_top = -30
	status.offset_right = -12
	status.offset_bottom = -6
	root.add_child(status)
	Net.room.connect(_on_room)
	Net.left.connect(func() -> void: go("menu"))
	Net.error.connect(func(msg: String) -> void: UI.toast(root, msg, UI.RED))
	Net.online_changed.connect(_on_online)
	_on_online(false)
	_start_screenshots()
	var practice_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--practice"):
			practice_arg = a.trim_prefix("--practice").trim_prefix("=")
			if practice_arg == "":
				practice_arg = "camp"
	if practice_arg != "":
		if Profile.cadet_name == "":
			Profile.cadet_name = "Cadet Test"
		start_practice(practice_arg)
		return
	if OS.get_cmdline_user_args().has("--auto-online"): # debug: create a room and start with bots
		if Profile.cadet_name == "":
			Profile.cadet_name = "Cadet Test"
		Net.welcome.connect(func(_m: Dictionary) -> void: Net.send({"t": "create"}), CONNECT_ONE_SHOT)
		Net.room.connect(func(r: Dictionary) -> void:
			if r.state == "waiting" and r.host == Net.my_id:
				Net.send({"t": "start"}))
	if Profile.cadet_name == "":
		go("title")
	else:
		Net.start()
		go("menu")


func go(name: String, data := {}) -> void:
	if current:
		current.queue_free()
	current_name = name
	var node: Node
	if name == "race":
		node = Race.new()
		node.setup(data.mode, data.room)
		if data.mode == "practice":
			node.practice_over.connect(_practice_course_done)
		backdrop.visible = false
		status.visible = false
		add_child(node)
	else:
		node = SCREENS[name].new()
		node.set("main", self)
		node.set("data", data)
		if name in ["range", "mapread"] and data.get("mode") == "practice":
			node.level_done.connect(_practice_stage_done.bind("range" if name == "range" else "map"))
		backdrop.visible = name not in ["range", "mapread"]
		status.visible = true
		root.add_child(node)
		root.move_child(status, -1)
	current = node


## Debug: `-- --shots=<dir>` saves a screenshot every 2.5s (used for visual checks).
func _start_screenshots() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.trim_prefix("--shots=")
	if dir == "":
		return
	AudioServer.set_bus_mute(0, true)
	Profile.voice_on = false
	var timer := Timer.new()
	timer.wait_time = 2.5
	timer.autostart = true
	var n := [0]
	timer.timeout.connect(func() -> void:
		n[0] += 1
		get_viewport().get_texture().get_image().save_png("%s/shot_%03d.png" % [dir, n[0]]))
	add_child(timer)


func toast(msg: String, color := UI.GOLD) -> void:
	UI.toast(root, msg, color)


## Offline practice vs 6 bots. `which`: "camp" (all 3 levels), "course", "range" or "map".
var practice := {}


func start_practice(which := "camp") -> void:
	var players := [{"id": "me", "name": Profile.cadet_name, "uniform": Profile.look.uniform,
		"beret": Profile.look.beret, "badge": Profile.look.badge, "role": "cadet", "bot": false}]
	var names := ["Cdt Arjun", "Cdt Priya", "Cdt Rohan", "Cdt Meera", "Cdt Kabir", "Cdt Ananya"]
	var uniforms := ["army", "navy", "air"]
	var berets := ["maroon", "black", "blue", "green"]
	for i in 6:
		var skill := randf_range(0.82, 1.1)
		players.append({"id": "bot%d" % i, "name": names[i], "bot": true, "uniform": uniforms[i % 3], "skill": skill,
			"beret": berets[i % 4], "badge": "none", "role": "cadet", "plan": Course.plan_bot(skill)})
	practice = {"which": which, "players": players, "scores": {}}
	for p in players:
		practice.scores[p.id] = {"coursePlace": null, "ms": null, "rangeScore": null, "mapScore": null, "points": 0}
	match which:
		"range":
			go("range", {"mode": "practice", "seed": randi()})
		"map":
			go("mapread", {"mode": "practice", "seed": randi()})
		_:
			go("race", {"mode": "practice", "room": {"players": players, "me": "me"}})


func _practice_course_done(rows: Array) -> void:
	for row in rows:
		var s: Dictionary = practice.scores[row.id]
		s.coursePlace = row.place
		s.ms = row.ms
		s.points += Course.STAGE_POINTS[row.place - 1]
	if practice.which == "course":
		_practice_results()
	else:
		go("range", {"mode": "practice", "seed": randi()})


func _practice_stage_done(score: int, stage: String) -> void:
	var key := stage + "Score"
	practice.scores["me"][key] = score
	for p in practice.players:
		if p.bot:
			practice.scores[p.id][key] = Course.bot_stage_score(p.skill, stage)
	var ids: Array = practice.scores.keys()
	ids.sort_custom(func(a, b): return practice.scores[a][key] > practice.scores[b][key])
	for i in ids.size():
		practice.scores[ids[i]].points += Course.STAGE_POINTS[i]
	if practice.which == "camp" and stage == "range":
		go("mapread", {"mode": "practice", "seed": randi()})
	else:
		_practice_results()


func _practice_results() -> void:
	var rows := []
	for p in practice.players:
		var s: Dictionary = practice.scores[p.id]
		rows.append({"id": p.id, "name": p.name, "bot": p.bot, "role": "cadet", "dp": 0, "ms": s.ms,
			"coursePlace": s.coursePlace, "rangeScore": s.rangeScore, "mapScore": s.mapScore, "points": s.points})
	var key: String = {"course": "points", "range": "rangeScore", "map": "mapScore"}.get(practice.which, "points")
	rows.sort_custom(func(a, b): return a[key] > b[key] if a[key] != b[key] else (a.coursePlace if a.coursePlace != null else 99) < (b.coursePlace if b.coursePlace != null else 99))
	for i in rows.size():
		rows[i].place = i + 1
	go("results", {"practice": true, "which": practice.which, "results": rows})


const STAGE_SCREENS := {"course": "race", "range": "range", "map": "mapread"}


func _on_room(room: Dictionary) -> void:
	match room.state:
		"waiting", "countdown":
			if current_name != "lobby":
				go("lobby", {"room": room})
		"racing":
			var target: String = STAGE_SCREENS.get(room.get("stage", "course"), "race")
			if current_name != target:
				var m := "spectate" if room.get("spectating", false) else "online"
				go(target, {"mode": m, "room": room, "seed": room.get("stageSeed", 0)})
		"results":
			if current_name != "results":
				go("results", {"room": room})


func _on_online(online: bool) -> void:
	status.text = ("Online  %dms" % Net.ping_ms) if online else "Offline - practice available"
	status.add_theme_color_override("font_color", Color("2ecc71") if online else UI.KHAKI)


func _process(_d: float) -> void:
	if Net.online and Engine.get_process_frames() % 60 == 0:
		status.text = "Online  %dms" % Net.ping_ms


func _notification(what: int) -> void:
	# Android back button: leave the room / return to the menu.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and current_name not in ["menu", "title"]:
		if Net.in_room():
			Net.send({"t": "leave"})
		else:
			go("menu")
