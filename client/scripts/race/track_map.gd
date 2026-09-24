extends Control
## Top-of-screen course strip: three level bands, obstacle ticks and a marker
## for every cadet. Your own marker is gold and larger.

var racers: Array = []
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(0, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(24, 26, size.x - 48, 12)
	draw_rect(bar.grow(4), Color(0, 0, 0, 0.45))
	var cols := [Color("8a9a5b"), Color("7a6a45"), Color("c49a5a")]
	var bounds := [0.0, Course.obstacle_x(5) - Course.OBSTACLE_SPACING * 0.5, Course.obstacle_x(10) - Course.OBSTACLE_SPACING * 0.5, Course.FINISH_X]
	for i in 3:
		var a: float = bounds[i] / Course.FINISH_X
		var b: float = bounds[i + 1] / Course.FINISH_X
		draw_rect(Rect2(bar.position.x + bar.size.x * a, bar.position.y, bar.size.x * (b - a), bar.size.y), cols[i])
		draw_string(font, Vector2(bar.position.x + bar.size.x * a + 4, bar.position.y - 6), "L%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
	for i in Course.OBSTACLE_COUNT:
		var k := Course.obstacle_x(i) / Course.FINISH_X
		draw_line(Vector2(bar.position.x + bar.size.x * k, bar.position.y), Vector2(bar.position.x + bar.size.x * k, bar.end.y), Color(0, 0, 0, 0.5), 2)
	draw_rect(Rect2(bar.end.x - 6, bar.position.y - 6, 6, bar.size.y + 12), Color.WHITE)
	var mine: Dictionary = {}
	for rc in racers:
		if rc.me:
			mine = rc
			continue
		_marker(bar, rc, 9.0)
	if not mine.is_empty():
		_marker(bar, mine, 13.0)


func _marker(bar: Rect2, rc: Dictionary, r: float) -> void:
	var k := clampf(rc.x / Course.FINISH_X, 0.0, 1.0)
	var at := Vector2(bar.position.x + bar.size.x * k, bar.get_center().y)
	draw_circle(at, r + 2, Color.BLACK if not rc.me else Color.WHITE)
	draw_circle(at, r, rc.color)
	var initial: String = rc.name.substr(0, 1).to_upper() if not rc.name.begins_with("Cdt ") else rc.name.substr(4, 1)
	draw_string(font, at + Vector2(-5, 5), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
