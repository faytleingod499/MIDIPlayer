extends SceneTree
# Tests the MIDI reader (midi_file.gd) against the songs written by make_midis.py (MIDI_DIR) and against damaged files.
#   run through tests/run.sh

var checks = 0
var fails = 0
var D = ""
var MidiFile = null


func ok(c, label):
	checks += 1
	if c:
		print("ok   ", label)
	else:
		fails += 1
		print("FAIL ", label)


func _init():
	var pck = OS.get_environment("MP_PCK")   # test the built pck instead of the source folder
	if pck != "":
		print("note  mounting ", pck, ": ", ProjectSettings.load_resource_pack(pck))
	call_deferred("_go")


func _bytes(path):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b = f.get_buffer(f.get_len())
	f.close()
	return b


func _json(path):
	var f = File.new()
	f.open(path, File.READ)
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.result


func _key(n):
	return [int(round(n[0] * 100000.0)), n[2], n[4]]


func _cmp_notes(a, b):
	var ka = _key(a)
	var kb = _key(b)
	for i in 3:
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


func _same(got, want):
	if got.size() != want.size():
		return "%d notes, expected %d" % [got.size(), want.size()]
	var g = got.duplicate()
	g.sort_custom(self, "_cmp_notes")
	var e = want.duplicate()
	e.sort_custom(self, "_cmp_notes")
	for i in g.size():
		var x = g[i]
		var y = e[i]
		if abs(x[0] - y[0]) > 1e-6 or abs(x[1] - y[1]) > 1e-6:
			return "note %d: time %s-%s, expected %s-%s" % [i, x[0], x[1], y[0], y[1]]
		if x[2] != int(y[2]) or x[3] != int(y[3]) or x[4] != int(y[4]) or x[5] != int(y[5]):
			return "note %d: %s, expected %s" % [i, x.slice(2, 5), y.slice(2, 5)]
	return ""


func _go():
	D = OS.get_environment("MIDI_DIR")
	MidiFile = load("res://mods/MIDIPlayer/midi_file.gd")
	var good = ["scale", "tempo", "running", "multi", "smpte", "cut", "bad_chunklen"]
	for name in good:
		var want = _json(D + "/" + name + ".json")
		var r = MidiFile.new().parse(_bytes(D + "/" + name + ".mid"))
		ok(r["ok"], name + ": reads")
		var why = _same(r["notes"], want["notes"])
		ok(why == "", name + ": every note, start, end, pitch, velocity, track and channel as written" + ("" if why == "" else " (" + why + ")"))
		ok(r["tracks"].size() == int(want["tracks"]), name + ": %d tracks" % int(want["tracks"]))
		var last = -1.0
		var sorted = true
		for n in r["notes"]:
			if n[0] < last:
				sorted = false
			last = n[0]
		ok(sorted, name + ": notes come sorted by start time")
	# the RIFF wrapper
	var wr = MidiFile.new().parse(_bytes(D + "/wrapped.rmi"))
	var wexp = _json(D + "/wrapped.json")
	ok(wr["ok"] and _same(wr["notes"], wexp["notes"]) == "", "wrapped.rmi: a RIFF RMID file reads like the plain one")
	# track details
	var multi = MidiFile.new().parse(_bytes(D + "/multi.mid"))
	var mexp = _json(D + "/multi.json")
	for i in 4:
		ok(multi["tracks"][i]["name"] == mexp["names"][i], "multi: track %d is called %s" % [i, mexp["names"][i]])
		ok(multi["tracks"][i]["program"] == int(mexp["programs"][i]), "multi: track %d first program %d" % [i, int(mexp["programs"][i])])
		ok(multi["tracks"][i]["drums"] == mexp["drums"][i], "multi: track %d drums = %s" % [i, str(mexp["drums"][i])])
	ok(multi["tracks"][2]["channel_count"] == 2, "multi: the bass track uses 2 channels")
	ok(MidiFile.program_name(25) == "Steel Guitar" and MidiFile.program_name(-1) == "" and MidiFile.program_name(200) == "", "instrument names")
	# tempo: the long note across three tempo changes ends where the generator says (checked above) and the song length
	var tempo = MidiFile.new().parse(_bytes(D + "/tempo.mid"))
	var texp = _json(D + "/tempo.json")
	var longest = 0.0
	for n in texp["notes"]:
		longest = max(longest, n[1])
	ok(abs(tempo["duration"] - longest) < 1e-6, "tempo: duration is the end of the last note (%.3f s)" % longest)

	# files that are not songs
	for name in ["bad_empty", "bad_garbage", "bad_text", "bad_nonotes", "bad_header", "bad_division", "bad_vlq", "bad_big"]:
		var r = MidiFile.new().parse(_bytes(D + "/" + name + ".mid"))
		ok(not r["ok"] and r["error"] != "" and r["notes"].empty(), name + ": refused with a message (\"%s\")" % r["error"])

	# lots of notes: speed, sorting, and the note limit
	var t0 = OS.get_ticks_msec()
	var big = MidiFile.new().parse(_bytes(D + "/many.mid"))
	var ms = OS.get_ticks_msec() - t0
	print("note  many.mid (%d notes) read in %d ms" % [big["note_count"], ms])
	ok(big["ok"] and big["note_count"] == 120000, "many.mid: 120000 notes read")
	ok(ms < 20000, "many.mid: read in under 20 s here (took %d ms)" % ms)
	var sorted_ok = true
	for i in range(1, big["notes"].size()):
		if big["notes"][i][0] < big["notes"][i - 1][0]:
			sorted_ok = false
			break
	ok(sorted_ok, "many.mid: sorted by start time")
	var too = MidiFile.new().parse(_bytes(D + "/toomany.mid"))
	ok(not too["ok"] and too["error"].find("Too many") >= 0, "toomany.mid: refused (\"%s\")" % too["error"])

	# nothing may crash on damaged input: cut at every length, and random byte changes
	var scale = _bytes(D + "/scale.mid")
	var survived = true
	for n in range(0, scale.size() + 1):
		var r = MidiFile.new().parse(scale.subarray(0, max(0, n - 1)))
		if typeof(r) != TYPE_DICTIONARY or typeof(r["ok"]) != TYPE_BOOL:
			survived = false
	ok(survived, "scale.mid cut at every length: always an answer")
	seed(12345)
	var bad_note = 0
	var runs = 0
	for name in ["multi", "tempo", "running", "scale", "smpte"]:
		var src = _bytes(D + "/" + name + ".mid")
		for it in 250:
			var b = PoolByteArray(src)
			var changes = 1 + randi() % 4
			for c in changes:
				b[randi() % b.size()] = randi() % 256
			if randi() % 4 == 0:
				b = b.subarray(0, randi() % b.size())
			var r = MidiFile.new().parse(b)
			runs += 1
			if typeof(r) != TYPE_DICTIONARY:
				bad_note += 1
				continue
			if r["ok"]:
				for n in r["notes"]:
					if n[1] < n[0] or n[2] < 0 or n[2] > 127 or n[3] < 1 or n[3] > 127 or is_inf(n[0]) or is_nan(n[0]) or n[0] < 0:
						bad_note += 1
						break
	ok(bad_note == 0, "%d random damaged files: every answer is sane" % runs)
	print("SUMMARY %d checks, %d failed" % [checks, fails])
	quit()
