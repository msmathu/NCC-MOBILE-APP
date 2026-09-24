extends Node
## WebSocket link to the game server (JSON messages). Reconnects automatically
## and resumes the same room slot with the session token after a drop.

signal online_changed(online: bool)
signal welcome(data: Dictionary)
signal room(data: Dictionary)
signal snap(data: Dictionary)
signal go
signal finished(data: Dictionary)
signal cheer(data: Dictionary)
signal profile(data: Dictionary)
signal board(data: Dictionary)
signal error(msg: String)
signal left
signal stage(data: Dictionary)
signal stage_done(data: Dictionary)

var online := false
var my_id := ""
var last_room: Dictionary = {}
var ping_ms := 0

var _ws: WebSocketPeer
var _token := ""
var _want := false
var _retry_at := 0.0
var _retry_delay := 1.0
var _ping_at := 0.0
var _was_open := false
var _http: HTTPRequest
var _discovered := ""

## Current public server address, maintained by server/scripts/go-public.mjs.
const CONFIG_URL := "https://raw.githubusercontent.com/msmathu/NCC-WEBSITE-APP-/main/server.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start() -> void:
	_want = true
	_open()


## Drops the connection and the session token, so the next start() is a fresh
## sign-in (used after changing name or server).
func stop() -> void:
	_want = false
	_token = ""
	_discovered = ""
	last_room = {}
	if _ws:
		_ws.close()
	_ws = null
	_set_online(false)


func send(msg: Dictionary) -> void:
	if online and _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func in_room() -> bool:
	return online and not last_room.is_empty()


func _open() -> void:
	var url := Profile.effective_server_url(_discovered)
	if url == "":
		_retry_at = Time.get_ticks_msec() / 1000.0 + 0.5
		_discover()
		return
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_was_open = false
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		_forget_discovery()
		_schedule_retry()


## Reads the public server address from server.json in the GitHub repo, so the
## host can move (new tunnel URL, new VM) without rebuilding the app.
func _discover() -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 8.0
		add_child(_http)
		_http.request_completed.connect(_on_discovered)
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if _http.request("%s?t=%d" % [CONFIG_URL, Time.get_unix_time_from_system()]) != OK:
		_on_discovered(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_discovered(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_discovered = Profile.LOCAL_SERVER
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var cfg = JSON.parse_string(body.get_string_from_utf8())
		if cfg is Dictionary and str(cfg.get("server", "")).begins_with("ws"):
			_discovered = cfg.server
	if _want:
		_retry_at = 0.0 # connect on the next frame


## After a failed connection, look the address up again next time (it may have moved).
func _forget_discovery() -> void:
	_discovered = ""


func _schedule_retry() -> void:
	_retry_at = Time.get_ticks_msec() / 1000.0 + _retry_delay
	_retry_delay = minf(_retry_delay * 1.6, 8.0)


func _set_online(v: bool) -> void:
	if online != v:
		online = v
		online_changed.emit(v)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _ws == null:
		if _want and now >= _retry_at:
			_open()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_retry_delay = 1.0
				_ws.send_text(JSON.stringify({
					"t": "hello", "deviceId": Profile.device_id, "name": Profile.cadet_name,
					"directorate": Profile.directorate, "token": _token,
				}))
			while _ws.get_available_packet_count() > 0:
				_dispatch(_ws.get_packet().get_string_from_utf8())
			if online and now >= _ping_at:
				_ping_at = now + 5.0
				send({"t": "ping", "c": Time.get_ticks_msec()})
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			if not _was_open or not online:
				_forget_discovery()
			_set_online(false)
			if _want:
				_schedule_retry()


func _notification(what: int) -> void:
	# Coming back from background: reconnect immediately instead of waiting for backoff.
	if what == NOTIFICATION_APPLICATION_RESUMED and _want and _ws == null:
		_retry_at = 0.0


func _dispatch(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("t", "")):
		"welcome":
			my_id = msg.id
			_token = msg.token
			if msg.get("profile"):
				Profile.apply_server_profile(msg.profile)
			if not msg.get("resumed", false):
				last_room = {}
			_set_online(true)
			welcome.emit(msg)
		"room":
			last_room = msg
			room.emit(msg)
		"snap":
			snap.emit(msg)
		"go":
			go.emit()
		"finished":
			finished.emit(msg)
		"cheer":
			cheer.emit(msg)
		"profile":
			Profile.apply_server_profile(msg.profile)
			profile.emit(msg.profile)
		"board":
			board.emit(msg)
		"stage":
			stage.emit(msg)
		"stagedone":
			stage_done.emit(msg)
		"left":
			last_room = {}
			left.emit()
		"pong":
			ping_ms = Time.get_ticks_msec() - int(msg.get("c", 0))
		"error":
			error.emit(str(msg.get("msg", "Error")))
