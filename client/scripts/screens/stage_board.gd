extends PanelContainer
## Live scoreboard shown while waiting for the squad to finish Level 2 / 3
## (and to spectators): each cadet's score for the level plus camp points so far.

var stage := "range"
var list: VBoxContainer
var title: Label
var timer: Label
var ms_left := 0.0


func _ready() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.12, 0.06, 0.94)
	s.border_color = UI.GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	s.set_content_margin_all(22)
	add_theme_stylebox_override("panel", s)
	custom_minimum_size = Vector2(620, 0)
	var col := UI.vbox(8)
	title = UI.label("", 30, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(title)
	timer = UI.label("", 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(timer)
	list = UI.vbox(4)
	col.add_child(list)
	add_child(col)
	Net.room.connect(refresh)
	refresh(Net.last_room)


func refresh(room: Dictionary) -> void:
	if room.is_empty() or room.get("state") != "racing":
		return
	title.text = "LEVEL 2 - RANGE CARDS" if stage == "range" else "LEVEL 3 - MAP READING"
	ms_left = room.get("stageMsLeft", 0)
	for c in list.get_children():
		c.queue_free()
	var key := stage + "Score"
	var players: Array = room.players.duplicate()
	players.sort_custom(func(a, b): return int(b.points) > int(a.points))
	for p in players:
		var h := UI.hbox(12)
		var me: bool = p.id == Net.my_id
		var c := UI.GOLD if me else UI.WHITE
		var n := UI.label(p.name + (" (bot)" if p.bot else ""), 20, c)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var sc = p.get(key)
		h.add_child(UI.label(("%d / %d" % [sc, Course.STAGE_MAX[stage]]) if sc != null else ("..." if not p.stageDone else "-"), 20, UI.GREEN_OK if sc != null else UI.KHAKI, HORIZONTAL_ALIGNMENT_RIGHT))
		var pts := UI.label("%d pts" % int(p.points), 18, UI.KHAKI_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
		pts.custom_minimum_size = Vector2(90, 0)
		h.add_child(pts)
		list.add_child(h)


func _process(d: float) -> void:
	ms_left = maxf(0.0, ms_left - d * 1000.0)
	timer.text = "Waiting for the squad...  %ds left" % ceili(ms_left / 1000.0) if ms_left > 0 else "Tallying scores..."
