extends Reference

# Standard MIDI File reader (format 0, 1 and 2, running status, tempo changes, SMPTE time, RIFF "RMID" wrapper).
# The file is treated as untrusted: every read is bounds checked, and size / track / note counts are capped, so a
# damaged or hostile file gives an error message and nothing else.
#
#   var r = MidiFile.new().parse(bytes)
#   r["ok"]        true when the file has notes
#   r["error"]     the reason when it doesn't
#   r["duration"]  seconds (end of the last note)
#   r["tracks"]    [{name, program, channel_count, notes, drums}]  (every track of the file, notes may be 0)
#   r["notes"]     [[start_s, end_s, pitch, velocity, track, channel], ...] sorted by start time

const MAX_BYTES = 3000000
const MAX_TRACKS = 128
const MAX_NOTES = 150000
const MAX_SECONDS = 36000.0

const GM = ["Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano", "Electric Piano 1",
	"Electric Piano 2", "Harpsichord", "Clavinet", "Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba",
	"Xylophone", "Tubular Bells", "Dulcimer", "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
	"Reed Organ", "Accordion", "Harmonica", "Tango Accordion", "Nylon Guitar", "Steel Guitar", "Jazz Guitar",
	"Clean Guitar", "Muted Guitar", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics", "Acoustic Bass",
	"Finger Bass", "Pick Bass", "Fretless Bass", "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2", "Violin",
	"Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
	"String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2", "Choir Aahs", "Voice Oohs",
	"Synth Voice", "Orchestra Hit", "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass Section",
	"Synth Brass 1", "Synth Brass 2", "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", "English Horn",
	"Bassoon", "Clarinet", "Piccolo", "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle",
	"Ocarina", "Square Lead", "Saw Lead", "Calliope Lead", "Chiff Lead", "Charang Lead", "Voice Lead", "Fifths Lead",
	"Bass + Lead", "New Age Pad", "Warm Pad", "Polysynth Pad", "Choir Pad", "Bowed Pad", "Metallic Pad", "Halo Pad",
	"Sweep Pad", "Rain FX", "Soundtrack FX", "Crystal FX", "Atmosphere FX", "Brightness FX", "Goblins FX", "Echoes FX",
	"Sci-fi FX", "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bagpipe", "Fiddle", "Shanai", "Tinkle Bell", "Agogo",
	"Steel Drums", "Woodblock", "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal", "Guitar Fret Noise",
	"Breath Noise", "Seashore", "Bird Tweet", "Telephone Ring", "Helicopter", "Applause", "Gunshot"]

# tempo tables (filled by parse): tick, seconds at that tick, microseconds per quarter note from that tick on
var _tt = [0]
var _ts = [0.0]
var _tu = [500000]
var _tpq = 480
var _smpte_tick = 0.0   # seconds per tick for SMPTE time, 0 for the usual tempo-based time


static func program_name(p):
	if p >= 0 and p < GM.size():
		return GM[p]
	return ""


func _tag(b, p):
	if p + 4 > b.size():
		return ""
	return char(b[p]) + char(b[p + 1]) + char(b[p + 2]) + char(b[p + 3])


func _u16(b, p):
	return (b[p] << 8) | b[p + 1]


func _u32(b, p):
	return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]


func _fail(res, text):
	res["ok"] = false
	res["error"] = text
	res["notes"] = []
	return res


func parse(bytes):
	var res = {"ok": false, "error": "", "format": 1, "division": 480, "duration": 0.0, "note_count": 0, "tracks": [], "notes": []}
	var n = bytes.size()
	if n > MAX_BYTES:
		return _fail(res, "The file is bigger than 3 MB")
	if n < 14:
		return _fail(res, "Too small to be a MIDI file")
	var start = 0
	if _tag(bytes, 0) == "RIFF" and n >= 20 and _tag(bytes, 8) == "RMID":
		var q = 12
		start = -1
		while q + 8 <= n:
			var cid = _tag(bytes, q)
			var cl = _u32(bytes, q + 4)
			if cid == "data":
				start = q + 8
				break
			q += 8 + cl + (cl & 1)
		if start < 0:
			return _fail(res, "Not a MIDI file")
	if _tag(bytes, start) != "MThd":
		return _fail(res, "Not a MIDI file")
	if start + 14 > n:
		return _fail(res, "Damaged MIDI header")
	var hlen = _u32(bytes, start + 4)
	if hlen < 6 or start + 8 + hlen > n:
		return _fail(res, "Damaged MIDI header")
	var format = _u16(bytes, start + 8)
	var division = _u16(bytes, start + 12)
	if division == 0:
		return _fail(res, "Damaged MIDI header (time division is 0)")
	res["format"] = format
	res["division"] = division
	_tt = [0]
	_ts = [0.0]
	_tu = [500000]
	_smpte_tick = 0.0
	_tpq = division
	if division & 0x8000:
		var fps = 256 - (division >> 8)   # the high byte is a negative number of frames per second
		var tpf = division & 0xFF
		if fps == 29:
			fps = 29.97
		if fps <= 0 or tpf == 0:
			return _fail(res, "Damaged MIDI header (SMPTE time)")
		_smpte_tick = 1.0 / (fps * tpf)

	var p = start + 8 + hlen
	var raw = []
	var tempos = []
	var total = 0
	while p + 8 <= n and raw.size() < MAX_TRACKS:
		var cid = _tag(bytes, p)
		var cl = _u32(bytes, p + 4)
		var body = p + 8
		if cid == "MTrk":
			var t = _track(bytes, body, min(body + cl, n), tempos)
			raw.append(t)
			total += t["notes"].size()
			if total > MAX_NOTES:
				return _fail(res, "Too many notes (more than %d)" % MAX_NOTES)
		p = body + cl
	if raw.empty():
		return _fail(res, "No tracks found")

	_build_tempo_table(tempos)

	# every note to seconds, then sort all notes by start time with one native sort of packed integer keys
	var all = []
	var keys = []
	var drums_only = []
	var longest = 0.0
	for ti in raw.size():
		var t = raw[ti]
		var only9 = true
		for nt in t["notes"]:
			var on_s = _sec(nt[0])
			var off_s = _sec(nt[1])
			if off_s < on_s:
				off_s = on_s
			if nt[4] != 9:
				only9 = false
			if off_s > longest:
				longest = off_s
			all.append([on_s, off_s, nt[2], nt[3], ti, nt[4]])
			keys.append((int(on_s * 1000000.0) << 18) | (all.size() - 1))
		drums_only.append(only9 and t["notes"].size() > 0)
	if all.empty():
		return _fail(res, "No notes in this file")
	if longest > MAX_SECONDS:
		return _fail(res, "The song is longer than 10 hours")
	keys.sort()
	var sorted_notes = []
	sorted_notes.resize(all.size())
	for i in keys.size():
		sorted_notes[i] = all[keys[i] & 0x3FFFF]

	var tracks = []
	for ti in raw.size():
		var t = raw[ti]
		tracks.append({"name": t["name"], "program": t["program"], "channel_count": t["channels"].size(),
			"notes": t["notes"].size(), "drums": drums_only[ti]})
	res["tracks"] = tracks
	res["notes"] = sorted_notes
	res["note_count"] = sorted_notes.size()
	res["duration"] = longest
	res["ok"] = true
	return res


# Reads the variable length number at b[p]; returns [value, next position], or null when it is damaged / cut off.
func _vlq(b, p, end):
	var v = 0
	for i in 4:
		if p >= end:
			return null
		var c = b[p]
		p += 1
		v = (v << 7) | (c & 0x7F)
		if not (c & 0x80):
			return [v, p]
	return null


func _text(b, p, length):
	var out = ""
	for i in min(length, 64):
		var c = b[p + i]
		if c >= 32 and c < 127:
			out += char(c)
		elif c >= 128:
			out += "?"
	return out.strip_edges()


# One MTrk chunk body b[p .. end). Returns {name, program, channels, notes: [[on_tick, off_tick, pitch, vel, channel]]}.
func _track(b, p, end, tempos):
	var t = {"name": "", "program": -1, "channels": {}, "notes": []}
	var notes = t["notes"]
	var tick = 0
	var status = 0
	var active = {}   # channel * 128 + pitch -> [[start tick, velocity], ...] (first in, first out)
	while p < end:
		if notes.size() > MAX_NOTES:
			break   # far too many for one track: parse() refuses the file
		var d = _vlq(b, p, end)
		if d == null:
			break
		tick += d[0]
		p = d[1]
		if p >= end:
			break
		var s = b[p]
		if s >= 0x80:
			p += 1
		else:
			s = status   # running status: the byte is data of the previous message
			if s < 0x80 or s >= 0xF0:
				break
		if s < 0xF0:
			status = s
			var kind = s & 0xF0
			var ch = s & 0x0F
			if kind == 0xC0 or kind == 0xD0:
				if p >= end:
					break
				if kind == 0xC0 and ch != 9 and t["program"] < 0:
					t["program"] = b[p] & 0x7F
				p += 1
			else:
				if p + 1 >= end:
					break
				var pitch = b[p] & 0x7F
				var vel = b[p + 1] & 0x7F
				p += 2
				if kind == 0x90 and vel > 0:
					var key = ch * 128 + pitch
					if not active.has(key):
						active[key] = []
					active[key].append([tick, vel])
					t["channels"][ch] = true
				elif kind == 0x80 or kind == 0x90:
					var key2 = ch * 128 + pitch
					if active.has(key2) and not active[key2].empty():
						var st = active[key2].pop_front()
						notes.append([st[0], tick, pitch, st[1], ch])
		elif s == 0xFF:
			status = 0
			if p >= end:
				break
			var mtype = b[p]
			p += 1
			var l = _vlq(b, p, end)
			if l == null:
				break
			p = l[1]
			var dend = p + l[0]
			if dend > end:
				break
			if mtype == 0x2F:
				break
			elif mtype == 0x51 and l[0] == 3:
				var us = (b[p] << 16) | (b[p + 1] << 8) | b[p + 2]
				if us > 0:
					tempos.append([tick, us, tempos.size()])
			elif mtype == 0x03 and t["name"] == "":
				t["name"] = _text(b, p, l[0])
			p = dend
		elif s == 0xF0 or s == 0xF7:
			status = 0
			var l2 = _vlq(b, p, end)
			if l2 == null:
				break
			p = l2[1] + l2[0]
		else:
			status = 0
			if s == 0xF2:
				p += 2
			elif s == 0xF1 or s == 0xF3:
				p += 1
	# notes that never got their "off" end with the track
	for key in active.keys():
		for st in active[key]:
			notes.append([st[0], max(tick, st[0]), key % 128, st[1], int(key / 128)])
	return t


func _cmp_tempo(a, b):
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[2] < b[2]


func _build_tempo_table(tempos):
	_tt = [0]
	_ts = [0.0]
	_tu = [500000]
	tempos.sort_custom(self, "_cmp_tempo")
	for e in tempos:
		var tk = e[0]
		var last = _tt.size() - 1
		if tk <= _tt[last]:
			_tu[last] = e[1]
		else:
			_ts.append(_ts[last] + float(tk - _tt[last]) * _tu[last] / 1000000.0 / _tpq)
			_tt.append(tk)
			_tu.append(e[1])


func _sec(tick):
	if _smpte_tick > 0.0:
		return tick * _smpte_tick
	var lo = 0
	var hi = _tt.size() - 1
	while lo < hi:
		var mid = (lo + hi + 1) >> 1
		if _tt[mid] <= tick:
			lo = mid
		else:
			hi = mid - 1
	return _ts[lo] + float(tick - _tt[lo]) * _tu[lo] / 1000000.0 / _tpq
