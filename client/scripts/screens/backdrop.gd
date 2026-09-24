extends Control
## Menu background: parade ground at dusk with a squad marking time.

var t := 0.0
const LOOKS := [
	{"uniform": "army", "beret": "maroon"}, {"uniform": "navy", "beret": "black"},
	{"uniform": "air", "beret": "blue"}, {"uniform": "army", "beret": "green"}, {"uniform": "navy", "beret": "maroon"},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(d: float) -> void:
	t += d
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ground := h * 0.78
	var top := Color("2f3515")
	var bottom := Color("7d8b4a")
	for i in 12:
		var k := i / 12.0
		draw_rect(Rect2(0, ground * k, w, ground / 12.0 + 1), top.lerp(bottom, k))
	draw_rect(Rect2(0, ground, w, h - ground), Color("4b5320"))
	draw_rect(Rect2(0, ground, w, 6), Color("c3b091"))
	# squad marking time along the bottom
	var n := LOOKS.size()
	for i in n:
		var x := w * 0.08 + i * 70.0
		CadetArt.draw(self, Vector2(x, ground + 2), LOOKS[i], t * 6.0 + i * 0.4, "run", false, 0.35, 0.9)
	for i in n:
		var x := w * 0.92 - i * 70.0
		CadetArt.draw(self, Vector2(x, ground + 2), LOOKS[(i + 2) % n], t * 6.0 + i * 0.4, "run", false, 0.35, 0.9)
