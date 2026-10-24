extends Node
## Autoload: sound effects synthesized at startup, so the MVP ships with no
## audio files. Swap in recorded sounds later by replacing _build_sounds().

const RATE := 22050
const VOICES := 8

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambience: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234
	_build_sounds()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _streams.crowd
	_ambience.volume_db = -20.0
	add_child(_ambience)


## Plays a sound by name. `strength` in 0..1 scales the volume.
func play(name: String, strength := 1.0, pitch := 1.0) -> void:
	if not Settings.sound or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.volume_db = linear_to_db(clampf(strength, 0.05, 1.0))
	p.pitch_scale = pitch
	p.play()


func set_ambience(on: bool) -> void:
	var want := on and Settings.sound and Settings.ambience
	if want and not _ambience.playing:
		_ambience.play()
	elif not want and _ambience.playing:
		_ambience.stop()


func _build_sounds() -> void:
	_streams.hit = _make(0.06, func(t: float, i: int) -> float:
		var env := exp(-t * 70.0)
		return env * (0.6 * sin(TAU * 900.0 * t) + 0.5 * _noise()))
	_streams.wall = _make(0.12, func(t: float, i: int) -> float:
		var env := exp(-t * 35.0)
		return env * (0.8 * sin(TAU * 170.0 * t) + 0.35 * _noise()))
	_streams.post = _make(0.35, func(t: float, i: int) -> float:
		var env := exp(-t * 12.0)
		return env * 0.5 * (sin(TAU * 1450.0 * t) + 0.6 * sin(TAU * 2210.0 * t)))
	_streams.goal = _make(1.3, func(t: float, i: int) -> float:
		var env := minf(t / 0.05, 1.0) * minf((1.3 - t) / 0.25, 1.0)
		var s := 0.0
		for f in [196.0, 247.0, 294.0]:
			s += fposmod(f * t, 1.0) * 2.0 - 1.0
		return env * s * 0.28)
	_streams.whistle = _make(0.5, func(t: float, i: int) -> float:
		var env := minf(t / 0.02, 1.0) * minf((0.5 - t) / 0.08, 1.0)
		var f := 2600.0 + 120.0 * sin(TAU * 32.0 * t)
		return env * 0.45 * sin(TAU * f * t))
	_streams.beep = _make(0.12, func(t: float, i: int) -> float:
		return minf((0.12 - t) / 0.03, 1.0) * 0.4 * sin(TAU * 880.0 * t))
	_streams.drop = _make(0.2, func(t: float, i: int) -> float:
		return minf((0.2 - t) / 0.05, 1.0) * 0.45 * sin(TAU * 1320.0 * t))
	_streams.click = _make(0.03, func(t: float, i: int) -> float:
		return exp(-t * 150.0) * 0.5 * sin(TAU * 1200.0 * t))
	var crowd := _make(3.0, _crowd_sample)
	crowd.loop_mode = AudioStreamWAV.LOOP_FORWARD
	crowd.loop_end = int(3.0 * RATE)
	_streams.crowd = crowd


var _lp := 0.0


func _crowd_sample(t: float, i: int) -> float:
	# Low-passed noise with a slow swell reads as a distant crowd.
	_lp += 0.04 * (_noise() - _lp)
	var swell := 0.75 + 0.25 * sin(TAU * t / 3.0)
	return _lp * 2.2 * swell


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _make(seconds: float, gen: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(gen.call(float(i) / RATE, i), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
