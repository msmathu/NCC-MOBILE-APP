extends Control
## Small animated cadet used in the lobby slots and the customization screen.

var look: Dictionary = {}
var pose := "idle"
var art_scale := 1.0
var gear := false
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(d: float) -> void:
	t += d
	queue_redraw()


func _draw() -> void:
	if look.is_empty():
		draw_arc(Vector2(size.x * 0.5, size.y * 0.55), 26 * art_scale, 0, TAU, 24, Color(1, 1, 1, 0.25), 3)
		return
	CadetArt.draw(self, Vector2(size.x * 0.5, size.y - 6), look, t * 7.0, pose, gear, 1.0, art_scale)
