class_name ObstacleGame
extends Control
## Base for the obstacle mini-games shown over the race. The race feeds it
## normalised gestures (press / release / swipe / tilt); the game reports
## `progress` (0..1, used to animate the cadet) and emits `cleared` when done.

signal cleared(clean: bool)

const PANEL := Color(0.08, 0.1, 0.05, 0.72)
const GOLD := Color("d4a017")
const GREEN := Color("2ecc71")
const BAD := Color("e74c3c")

var index := 0
var progress := 0.0
var scout := false ## Scout role: wider timing windows
var boost := 1.0 ## co-op / support multiplier (High Wall)
var time_limit := 16.0 ## after this an instructor waves the cadet through
var elapsed := 0.0
var faults := 0
var done := false
var flash := 0.0
var flash_color := GREEN
var font: Font


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if done:
		return
	elapsed += delta
	flash = maxf(0.0, flash - delta * 3.0)
	tick(delta)
	if not done and elapsed > time_limit:
		finish(false)
	queue_redraw()


## Area at the bottom-centre where games draw their widgets.
func area() -> Rect2:
	var w := minf(size.x - 80.0, 900.0)
	return Rect2((size.x - w) * 0.5, size.y - 250.0, w, 200.0)


func finish(clean: bool) -> void:
	if done:
		return
	done = true
	progress = 1.0
	cleared.emit(clean)


func good(p := 1.0) -> void:
	flash = 1.0
	flash_color = GREEN
	Sfx.play("good", p)


func fault() -> void:
	faults += 1
	flash = 1.0
	flash_color = BAD
	Sfx.play("bad")
	Input.vibrate_handheld(80)


## Window multiplier: scouts get 35% wider windows.
func win(w: float) -> float:
	return w * (1.35 if scout else 1.0)


func _draw() -> void:
	var a := area()
	draw_rect(a.grow(10), PANEL)
	if flash > 0.0:
		draw_rect(a.grow(10), Color(flash_color, flash * 0.35))
		draw_rect(a.grow(10), Color(flash_color, flash), false, 4)
	# time-limit strip
	var left := clampf(1.0 - elapsed / time_limit, 0.0, 1.0)
	draw_rect(Rect2(a.position + Vector2(0, -16), Vector2(a.size.x * left, 5)), Color(1, 1, 1, 0.35))
	paint(a)


func text(at: Vector2, t: String, sz := 22, c := Color.WHITE, center := true) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x if center else 0.0
	draw_string_outline(font, at - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.7))
	draw_string(font, at - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)


func arrow(center: Vector2, dir: Vector2, length: float, c: Color, w := 12.0) -> void:
	var tip := center + dir * length * 0.5
	var tail := center - dir * length * 0.5
	draw_line(tail, tip - dir * w, c, w)
	var side := dir.orthogonal() * w * 1.4
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * w * 2.2 + side, tip - dir * w * 2.2 - side]), c)


# ---- overridables -------------------------------------------------------------

func tick(_delta: float) -> void:
	pass


func paint(_a: Rect2) -> void:
	pass


## screen-space press; `left` is true when on the left half of the screen
func on_press(_pos: Vector2, _left: bool) -> void:
	pass


func on_release(_pos: Vector2) -> void:
	pass


## dir is one of 8 unit directions (x right, y down)
func on_swipe(_dir: Vector2) -> void:
	pass


## -1..1 from the accelerometer (0 when unavailable)
func on_tilt(_v: float) -> void:
	pass


## true while any finger / key is held
var holding := false
## -1 / 0 / 1 depending on which side is held
var hold_side := 0
