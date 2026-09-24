extends Node
## All audio is synthesised at startup (no audio assets to license):
## a parade-march drum loop, UI/obstacle effects, and drill commands spoken
## through the device's built-in text-to-speech (Hindi voice when available).

const RATE := 22050

const COMMANDS := {
	"attention": ["Savdhan!", "सावधान!", "Attention!"],
	"go": ["Quick March!", "तेज़ चल!", "Quick March!"],
	"faster": ["Tez Chal!", "तेज़ चल!", "Double time!"],
	"halt": ["Tham!", "थम!", "Halt!"],
	"good": ["Shabash!", "शाबाश!", "Well done!"],
	"level2": ["Section Two!", "सेक्शन दो, तेज़ चल!", "Section two, quick march!"],
	"level3": ["Section Three!", "सेक्शन तीन, तेज़ चल!", "Section three, quick march!"],
}

var _music: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _sounds := {}
var _hindi_voice := ""
var _english_voice := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.stream = _march_loop()
	_music.volume_db = -9.0
	add_child(_music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_sounds = {
		"tap": _tone([880.0], 0.05, 0.25, "square"),
		"good": _tone([660.0, 880.0, 1320.0], 0.08, 0.35, "triangle"),
		"bad": _tone([220.0, 160.0], 0.12, 0.4, "square"),
		"whistle": _whistle(),
		"step": _noise_hit(0.05, 0.3),
		"thud": _kick(0.18, 0.7),
		"cheer": _tone([1046.0, 1318.0, 1568.0, 2093.0], 0.05, 0.25, "triangle"),
		"finish": _tone([523.0, 659.0, 784.0, 1046.0, 784.0, 1046.0], 0.12, 0.4, "square"),
	}


func music(on: bool) -> void:
	if on and Profile.music_on:
		if not _music.playing:
			_music.play()
	else:
		_music.stop()


func play(name: String, pitch := 1.0) -> void:
	var s = _sounds.get(name)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.play()
			return


## Speaks a drill command. Returns the on-screen text for the HUD banner.
func say(key: String) -> String:
	var c: Array = COMMANDS.get(key, [key, key, key])
	if Profile.voice_on and ProjectSettings.get_setting("audio/general/text_to_speech", false):
		if _english_voice == "" and _hindi_voice == "":
			_pick_voices() # Android TTS starts asynchronously, so voices appear after launch
		var hindi := Profile.voice_hindi and _hindi_voice != ""
		var voice := _hindi_voice if hindi else _english_voice
		if voice != "":
			DisplayServer.tts_stop()
			DisplayServer.tts_speak(c[1] if hindi else c[2], voice, 90, 1.0, 1.1)
	return c[0]


## Reads free text aloud in English (map-reading clues from the instructor).
func speak(text: String) -> void:
	if not Profile.voice_on or not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return
	if _english_voice == "":
		_pick_voices()
	if _english_voice != "":
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, _english_voice, 90, 1.0, 1.0)


func _pick_voices() -> void:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return
	if OS.get_name() == "Android" and Engine.get_process_frames() < 30:
		return # TTS engine not ready yet
	var hi := DisplayServer.tts_get_voices_for_language("hi")
	if hi.size() > 0:
		_hindi_voice = hi[0]
	var en := DisplayServer.tts_get_voices_for_language("en")
	if en.size() > 0:
		_english_voice = en[0]


# ---- synthesis ---------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"triangle":
			return 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
	return sin(phase * TAU)


func _tone(notes: Array, note_len: float, vol: float, kind: String) -> AudioStreamWAV:
	var n := int(note_len * RATE)
	var out := PackedFloat32Array()
	out.resize(n * notes.size())
	for j in notes.size():
		var phase := 0.0
		for i in n:
			phase += notes[j] / RATE
			var env := minf(1.0, i / 200.0) * (1.0 - float(i) / n)
			out[j * n + i] = _osc(kind, phase) * env * vol
	return _wav(out)


func _whistle() -> AudioStreamWAV:
	var n := int(0.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 2600.0 + 180.0 * sin(t * TAU * 28.0) # pea whistle trill
		phase += f / RATE
		var env := minf(1.0, t * 40.0) * minf(1.0, (0.6 - t) * 12.0)
		out[i] = (sin(phase * TAU) * 0.8 + randf_range(-0.15, 0.15)) * env * 0.35
	return _wav(out)


func _noise_hit(length: float, vol: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = randf_range(-1.0, 1.0) * pow(1.0 - float(i) / n, 3.0) * vol
	return _wav(out)


func _kick(length: float, vol: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += lerpf(140.0, 45.0, k) / RATE
		out[i] = sin(phase * TAU) * pow(1.0 - k, 2.0) * vol
	return _wav(out)


## Two bars of 4/4 at 116 BPM: bass drum on 1 & 3, snare on 2 & 4 with a roll
## at the end of bar two, and a short bugle phrase on top.
func _march_loop() -> AudioStreamWAV:
	var beat := 60.0 / 116.0
	_buf = PackedFloat32Array()
	_buf.resize(int(beat * 8.0 * RATE))
	for b in 8:
		var t := b * beat
		if b % 2 == 0:
			_drum(t, true, 0.55)
		else:
			_drum(t, false, 0.32)
		_drum(t + beat * 0.5, false, 0.12)
	for r in 6: # roll into the loop point
		_drum(beat * 7.0 + r * beat / 6.0, false, 0.14 + r * 0.03)
	# Bugle phrase (harmonic series notes of a C bugle): G C E G  E C.
	var bugle := [[0.0, 392.0, 0.5], [0.5, 523.0, 0.5], [1.0, 659.0, 0.5], [1.5, 784.0, 1.0], [2.5, 659.0, 0.5], [3.0, 523.0, 1.0]]
	for note in bugle:
		var start := int(note[0] * beat * RATE)
		var n := int(note[2] * beat * RATE * 0.92)
		var phase := 0.0
		for i in n:
			phase += note[1] / RATE
			var env := minf(1.0, i / 600.0) * minf(1.0, float(n - i) / 900.0)
			var s := sin(phase * TAU) * 0.6 + sin(phase * TAU * 2.0) * 0.25 + sin(phase * TAU * 3.0) * 0.12
			_buf[start + i] += s * env * 0.12
	return _wav(_buf, true)


var _buf := PackedFloat32Array()


func _drum(at: float, kick: bool, vol: float) -> void:
	var start := int(at * RATE)
	var n := int((0.22 if kick else 0.12) * RATE)
	var phase := 0.0
	for i in n:
		if start + i >= _buf.size():
			break
		var k := float(i) / n
		var v := 0.0
		if kick:
			phase += lerpf(110.0, 42.0, k) / RATE
			v = sin(phase * TAU) * pow(1.0 - k, 2.0)
		else:
			v = (randf_range(-1.0, 1.0) * 0.8 + sin(i * TAU * 190.0 / RATE) * 0.3) * pow(1.0 - k, 4.0)
		_buf[start + i] += v * vol
