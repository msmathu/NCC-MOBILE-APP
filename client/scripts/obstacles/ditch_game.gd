extends ObstacleGame
## Obstacle 12 - Double Ditch Jump: hold to charge, release inside the gold zone.
## A slightly short jump can be saved by tapping mid-air (air-time stretch).

const ZONE_LO := 0.68
const ZONE_HI := 0.9
var jumps := 0
var charging := false
var power := 0.0
var t := 0.0
var air := 0.0 ## >0 while airborne on a short jump, waiting for the stretch tap
var _was_holding := false


func tick(d: float) -> void:
	if air > 0.0:
		air -= d
		if air <= 0.0:
			fault() # fell short into the ditch
		return
	if holding and not _was_holding:
		charging = true
		t = 0.0
	_was_holding = holding
	if charging:
		if holding:
			t += d * 1.1
			power = 1.0 - absf(fmod(t, 2.0) - 1.0)
		else:
			charging = false
			_release()


func _release() -> void:
	var lo := ZONE_LO - (0.05 if scout else 0.0)
	var hi := ZONE_HI + (0.04 if scout else 0.0)
	if power >= lo and power <= hi:
		_landed()
	elif power >= 0.5 and power < lo:
		air = 0.55
		Sfx.play("tap", 0.6)
	else:
		fault()


func _landed() -> void:
	jumps += 1
	progress = jumps / 2.0
	good(1.0 + jumps * 0.15)
	Sfx.play("thud")
	if jumps >= 2:
		finish(faults == 0)


func on_press(_pos: Vector2, _left: bool) -> void:
	if air > 0.0:
		air = 0.0
		_landed()


func paint(a: Rect2) -> void:
	var c := a.get_center()
	var bar := Rect2(c.x - 40, a.position.y + 20, 80, a.size.y - 70)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var lo := ZONE_LO - (0.05 if scout else 0.0)
	var hi := ZONE_HI + (0.04 if scout else 0.0)
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * hi, bar.size.x, bar.size.y * (hi - lo)), Color(GOLD, 0.8))
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * power, bar.size.x, bar.size.y * power), Color(1, 1, 1, 0.6))
	draw_rect(bar, Color.WHITE, false, 3)
	for i in 2:
		draw_circle(Vector2(c.x + 110 + i * 34, a.position.y + 40), 12, GREEN if i < jumps else Color(1, 1, 1, 0.3))
	if air > 0.0:
		text(Vector2(c.x, a.end.y - 14), "SHORT! TAP NOW to stretch!", 26, GOLD)
	else:
		text(Vector2(c.x, a.end.y - 14), "HOLD to charge, RELEASE in gold", 22)
