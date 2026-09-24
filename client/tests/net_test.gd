extends Node
## End-to-end check against a running server (npm start in server/):
## sign in, create a room, start with bots, receive the race start and snapshots.
##   godot --headless --path client res://tests/net_test.tscn

var got := {}


func _ready() -> void:
	Profile.server_url = "ws://127.0.0.1:2567"
	Profile.cadet_name = "Net Test"
	Net.welcome.connect(func(m: Dictionary) -> void:
		got.welcome = m.profile.rank
		Net.send({"t": "create", "roles": true}))
	Net.room.connect(func(r: Dictionary) -> void:
		got["room_" + r.state] = r.players.size()
		if r.state == "waiting" and not got.has("started"):
			got.started = r.code
			Net.send({"t": "start"}))
	Net.go.connect(func() -> void: got.go = true)
	Net.snap.connect(func(s: Dictionary) -> void: got.snaps = got.get("snaps", 0) + 1)
	Net.start()
	await get_tree().create_timer(14.0).timeout
	print("NET TEST: ", got)
	var ok: bool = got.has("welcome") and got.has("go") and got.get("snaps", 0) > 5 and got.get("room_racing", 0) == 7
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
