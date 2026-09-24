extends Control
## Directorate leaderboard: state-wise Drill Point totals and top cadets.

var main: Node
var data: Dictionary
var list: VBoxContainer
var tab := "dir"
var title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var col := UI.vbox(12)
	margin.add_child(col)
	var top := UI.hbox(12)
	title = UI.label("DIRECTORATE LEADERBOARD", 34, UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button("STATES", func() -> void: _load("dir")))
	top.add_child(UI.button("TOP CADETS", func() -> void: _load("top")))
	top.add_child(UI.button("MY DTE", func() -> void: _load("mine")))
	top.add_child(UI.button("BACK", func() -> void: main.go("menu")))
	col.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var p := UI.panel(16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list = UI.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(list)
	scroll.add_child(p)
	col.add_child(scroll)
	Net.board.connect(_on_board)
	_load("dir")


func _load(which: String) -> void:
	tab = which
	for c in list.get_children():
		c.queue_free()
	list.add_child(UI.label("Loading..." if Net.online else "Connect to the server to see the leaderboard.", 20, UI.KHAKI_LIGHT))
	Net.send({"t": "board", "dir": Profile.directorate if which == "mine" else ""})


func _on_board(b: Dictionary) -> void:
	for c in list.get_children():
		c.queue_free()
	if tab == "dir":
		title.text = "DIRECTORATE LEADERBOARD"
		var top_dp := 1
		for d in b.directorates:
			top_dp = maxi(top_dp, int(d.dp))
		for i in b.directorates.size():
			var d: Dictionary = b.directorates[i]
			var mine: bool = d.name == Profile.directorate
			var h := UI.hbox(12)
			var rank := UI.label("%d." % (i + 1), 20, UI.GOLD if mine else UI.WHITE)
			rank.custom_minimum_size = Vector2(44, 0)
			h.add_child(rank)
			var n := UI.label(d.name, 20, UI.GOLD if mine else UI.WHITE)
			n.custom_minimum_size = Vector2(420, 0)
			h.add_child(n)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = top_dp
			bar.value = int(d.dp)
			bar.custom_minimum_size = Vector2(0, 18)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(bar)
			h.add_child(UI.label("%d DP  -  %d cadets" % [int(d.dp), int(d.cadets)], 18, UI.KHAKI_LIGHT))
			list.add_child(h)
	else:
		title.text = "TOP CADETS" + (" - " + b.directorate if b.get("directorate") else " - ALL INDIA")
		if b.top.is_empty():
			list.add_child(UI.label("No cadets yet. Be the first on the board!", 20, UI.KHAKI_LIGHT))
		for i in b.top.size():
			var c: Dictionary = b.top[i]
			var mine: bool = c.name == Profile.cadet_name
			var h := UI.hbox(12)
			var rank := UI.label("%d." % (i + 1), 20, UI.GOLD if mine else UI.WHITE)
			rank.custom_minimum_size = Vector2(44, 0)
			h.add_child(rank)
			var n := UI.label("%s  (%s)" % [c.name, c.rank], 20, UI.GOLD if mine else UI.WHITE)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(n)
			h.add_child(UI.label(c.directorate, 16, UI.KHAKI_LIGHT))
			var best := "  best " + Course.format_ms(c.bestMs) if c.get("bestMs") != null else ""
			h.add_child(UI.label("%d DP  -  %d wins%s" % [int(c.dp), int(c.wins), best], 18, UI.KHAKI_LIGHT))
			list.add_child(h)
