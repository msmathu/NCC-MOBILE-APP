extends Node
## Local cadet identity and settings. No account: a random device id is created
## on first launch and stored in user://; the server keys progress by it.

signal changed

const PATH := "user://cadet.cfg"
## "auto" = look up the official server address in server.json on GitHub (see net.gd).
const DEFAULT_SERVER := "auto"
const LOCAL_SERVER := "ws://127.0.0.1:2567"

var device_id := ""
var cadet_name := ""
var directorate := "Delhi"
var server_url := DEFAULT_SERVER
var look := {"uniform": "army", "beret": "maroon", "badge": "none"}
var voice_on := true
var voice_hindi := true
var music_on := true
var invert_tilt := false
## Last profile the server sent (dp, rank, races, wins...). Cached for offline display.
var stats := {"dp": 0, "rank": "Cadet", "rankIndex": 0, "races": 0, "wins": 0, "nextRankDp": 300}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		device_id = cfg.get_value("cadet", "device_id", "")
		cadet_name = cfg.get_value("cadet", "name", "")
		directorate = cfg.get_value("cadet", "directorate", directorate)
		server_url = cfg.get_value("settings", "server_url", server_url)
		if server_url == "" or server_url == LOCAL_SERVER: # migrate older installs to auto
			server_url = DEFAULT_SERVER
		look = cfg.get_value("cadet", "look", look)
		voice_on = cfg.get_value("settings", "voice_on", voice_on)
		voice_hindi = cfg.get_value("settings", "voice_hindi", voice_hindi)
		music_on = cfg.get_value("settings", "music_on", music_on)
		invert_tilt = cfg.get_value("settings", "invert_tilt", invert_tilt)
		stats = cfg.get_value("cadet", "stats", stats)
	if device_id.length() < 16:
		device_id = _new_uuid()
		save()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cadet", "device_id", device_id)
	cfg.set_value("cadet", "name", cadet_name)
	cfg.set_value("cadet", "directorate", directorate)
	cfg.set_value("cadet", "look", look)
	cfg.set_value("cadet", "stats", stats)
	cfg.set_value("settings", "server_url", server_url)
	cfg.set_value("settings", "voice_on", voice_on)
	cfg.set_value("settings", "voice_hindi", voice_hindi)
	cfg.set_value("settings", "music_on", music_on)
	cfg.set_value("settings", "invert_tilt", invert_tilt)
	cfg.save(PATH)
	changed.emit()


func apply_server_profile(p: Dictionary) -> void:
	stats = p
	for k in ["uniform", "beret", "badge"]:
		if p.has(k):
			look[k] = p[k]
	save()


## Address to connect to, or "" when it must first be looked up in server.json
## (`discovered` is the result of that lookup, "" if not done yet).
## Browser: `?server=` link parameter, else the server that served the page;
## pages on static hosts (GitHub Pages) use the lookup.
func effective_server_url(discovered: String) -> String:
	if server_url != DEFAULT_SERVER:
		return server_url
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''")
		if q is String and q != "":
			return q
		var host = JavaScriptBridge.eval("location.hostname")
		if host is String and host != "" and not host.ends_with("github.io"):
			return JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host")
	return discovered


func rank_index() -> int:
	return int(stats.get("rankIndex", 0))


func is_unlocked(kind: String, option: String) -> bool:
	return rank_index() >= int(Course.UNLOCKS[kind].get(option, 99))


func _new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
