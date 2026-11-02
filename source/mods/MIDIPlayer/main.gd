extends Node

# MIDI Player
# Adds a window to the guitar menu (the one that opens when you play the guitar) to import MIDI files, keep a list of
# them and play them on the guitar by itself. Each note becomes the game's own guitar strum (PlayerData._play_guitar),
# so the game plays the sound and sends it to the other players just like a note you play by hand. Client side only:
# nothing needs to be installed on the server.
#
#   midi_file.gd    reads .mid files (untrusted input: bounds checked and size limited)
#   guitar_map.gd   picks the string and fret for every note
#   song_player.gd  the clock: fires the strums on time
#   window.gd       the window in the guitar menu
#   main.gd         this file: finds the guitar menu, keeps the library (user://MIDIPlayer), settings and the song

const VERSION = "1.0.0"
const MOD_DIR = "res://mods/MIDIPlayer/"
const LIB_DIR = "user://MIDIPlayer"
const SETTINGS_FILE = "user://MIDIPlayer/_settings.json"
const INDEX_FILE = "user://MIDIPlayer/_index.json"
const MAX_SONGS = 500
const MAX_IMPORT_AT_ONCE = 60
const POLL = 0.25
const MESSAGE_SECONDS = 9.0
const RESERVED = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

var MidiFile = null
var GuitarMap = null
var WindowScript = null

var settings = {"x": 600.0, "y": 60.0, "collapsed": false, "speed": 1.0, "semitones": 0, "auto_octave": true,
	"repeat": 0, "last_song": "", "last_dir": ""}
var songs = []             # [{file, name, size, duration (-1 = not read yet), notes, bad}]
var songs_version = 0      # changes when the list changes
var index = {}             # file -> {size, duration, notes, bad}: what was learned about each file, so it is read once
var scan_queue = []
var cur_index = -1
var cur = null             # the parsed current song (MidiFile.parse result) or null
var map = null             # GuitarMap.build result for it
var track_on = {}          # tracks that are played: track number -> true
var cur_version = 0        # changes when the current song or its mapping changes
var message = ""
var message_until = 0.0
var player = null          # song_player.gd
var minigame = null        # the game's guitar menu while it is open
var window = null
var keys_blocked = false
var saved_actions = {}     # the game's key bindings taken away while a file dialog is open
var clock = 0.0
var poll = 0.0
var save_at = -1.0
var index_dirty = false
var markers_dirty = false
var auto = true            # tests turn the polling off


func _ready():
	MidiFile = load(MOD_DIR + "midi_file.gd")
	GuitarMap = load(MOD_DIR + "guitar_map.gd")
	WindowScript = load(MOD_DIR + "window.gd")
	player = load(MOD_DIR + "song_player.gd").new()
	player.name = "SongPlayer"
	add_child(player)
	player.connect("note_fired", self, "_on_note")
	player.connect("finished", self, "_on_finished")
	_ensure_dir()
	_load_settings()
	_load_index()
	player.speed = settings["speed"]
	scan_library()
	if auto:
		get_tree().connect("files_dropped", self, "_on_files_dropped")


func _process(delta):
	clock += delta
	if save_at >= 0.0 and clock >= save_at:
		save_now()
	if not scan_queue.empty():
		_scan_step()
	if not auto:
		return
	poll += delta
	if poll >= POLL:
		poll = 0.0
		_poll_minigame()


# ---------- the guitar menu ----------

func _find_minigame():
	for p in get_tree().get_nodes_in_group("controlled_player"):
		var h = p.get("hud")
		if typeof(h) != TYPE_OBJECT or h == null or not is_instance_valid(h):
			continue
		for c in h.get_children():
			if c is CanvasLayer and c.has_method("_strum_string") and c.has_method("_select_shape") \
					and not c.is_queued_for_deletion():
				return c
	return null


func _poll_minigame():
	if minigame != null and (not is_instance_valid(minigame) or minigame.is_queued_for_deletion()):
		_detach()
	if minigame != null:
		return
	var m = _find_minigame()
	if m != null:
		attach(m)


func attach(m):
	minigame = m
	keys_blocked = false
	window = WindowScript.new()
	window.mod = self
	m.add_child(window)
	if settings["last_song"] != "" and cur == null:
		for i in songs.size():
			if songs[i]["file"] == settings["last_song"]:
				select_song(i, false)
				break


func _detach():
	if player.playing:
		player.pause()
	player.stop()
	set_keys_blocked(false)
	minigame = null
	window = null
	markers_dirty = false


# While a file dialog has the keyboard, typing a path must not do things in the game. The game reads its keys by asking
# the input map every frame, whatever has the keyboard focus: the guitar menu strums on Q W E R T Y, and the player barks
# on G, interacts on E, equips the hotbar on 1-5. So every binding except the menu keys (ui_*) is taken away while the
# dialog is open and put back afterwards. The dialog itself reads the keys as text, which is not affected.
func set_keys_blocked(on):
	if on and not keys_blocked:
		saved_actions = {}
		for a in InputMap.get_actions():
			if str(a).begins_with("ui_"):
				continue
			saved_actions[a] = InputMap.get_action_list(a)
			InputMap.action_erase_events(a)
	elif not on and keys_blocked:
		_restore_actions()
	keys_blocked = on
	if minigame != null and is_instance_valid(minigame):
		minigame.set_process(not on)


func _restore_actions():
	for a in saved_actions:
		if not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		for e in saved_actions[a]:
			InputMap.action_add_event(a, e)
	saved_actions = {}


func _exit_tree():
	if keys_blocked:
		_restore_actions()
		keys_blocked = false


# What the player sees on the guitar while the song plays: the fret markers follow the notes and the string wobbles.
# The saved chord shapes are not touched (only the signal that moves the markers is sent).
func _on_note(s, f, _v):
	if minigame == null or not is_instance_valid(minigame):
		return
	minigame.emit_signal("_fret_update", s, f)
	var strings = minigame.get_node_or_null("strings_main/strings")
	if strings != null and s < strings.get_child_count():
		strings.get_child(s).set("wobble", 9.0)
	markers_dirty = true


func _restore_markers():
	if not markers_dirty:
		return
	markers_dirty = false
	if minigame == null or not is_instance_valid(minigame):
		return
	var fr = minigame.get("string_frets")
	if typeof(fr) != TYPE_ARRAY:
		return
	for i in min(6, fr.size()):
		minigame.emit_signal("_fret_update", i, fr[i])


# ---------- settings and index ----------

func _ensure_dir():
	var d = Directory.new()
	if not d.dir_exists(LIB_DIR):
		d.make_dir_recursive(LIB_DIR)


func _read_json(path):
	var f = File.new()
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return null
	var text = f.get_as_text()
	f.close()
	var r = JSON.parse(text)
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY:
		return null
	return r.result


func _write_json(path, data):
	var f = File.new()
	var tmp = path + ".tmp"
	if f.open(tmp, File.WRITE) != OK:
		return false
	f.store_string(JSON.print(data))
	f.close()
	var d = Directory.new()
	if d.file_exists(path):
		d.remove(path)
	return d.rename(tmp, path) == OK


func _load_settings():
	var r = _read_json(SETTINGS_FILE)
	if r == null:
		return
	settings["x"] = clamp(float(r.get("x", settings["x"])), 0.0, 4000.0)
	settings["y"] = clamp(float(r.get("y", settings["y"])), 0.0, 3000.0)
	settings["collapsed"] = bool(r.get("collapsed", false))
	settings["speed"] = clamp(stepify(float(r.get("speed", 1.0)), 0.05), 0.5, 1.5)
	settings["semitones"] = int(clamp(int(r.get("semitones", 0)), -12, 12))
	settings["auto_octave"] = bool(r.get("auto_octave", true))
	settings["repeat"] = int(clamp(int(r.get("repeat", 0)), 0, 2))
	settings["last_song"] = str(r.get("last_song", ""))
	settings["last_dir"] = str(r.get("last_dir", ""))


func save_soon():
	if save_at < 0.0:
		save_at = clock + 1.0


func save_now():
	save_at = -1.0
	_ensure_dir()
	_write_json(SETTINGS_FILE, settings)
	if index_dirty:
		index_dirty = false
		_write_json(INDEX_FILE, {"files": index})


func _load_index():
	var r = _read_json(INDEX_FILE)
	if r != null and typeof(r.get("files", null)) == TYPE_DICTIONARY:
		index = r["files"]


# ---------- the library ----------

func _is_midi_name(f):
	var e = f.get_extension().to_lower()
	return e == "mid" or e == "midi" or e == "kar"


func _cmp_names(a, b):
	return a.to_lower() < b.to_lower()


func _file_size(path):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return -1
	var n = f.get_len()
	f.close()
	return n


# Returns the bytes of a file, or null when it can't be read or is too big.
func _read_bytes(path):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return null
	var n = f.get_len()
	if n > MidiFile.MAX_BYTES:
		f.close()
		return null
	var b = f.get_buffer(n)
	f.close()
	return b


func scan_library():
	_ensure_dir()
	var found = []
	var d = Directory.new()
	if d.open(LIB_DIR) == OK:
		d.list_dir_begin(true, true)
		var f = d.get_next()
		while f != "":
			if not d.current_is_dir() and _is_midi_name(f) and found.size() < MAX_SONGS:
				found.append(f)
			f = d.get_next()
		d.list_dir_end()
	found.sort_custom(self, "_cmp_names")
	var keep = ""
	if cur_index >= 0 and cur_index < songs.size():
		keep = songs[cur_index]["file"]
	songs = []
	scan_queue = []
	for f in found:
		var size = _file_size(LIB_DIR + "/" + f)
		var s = {"file": f, "name": f.get_basename(), "size": size, "duration": -1.0, "notes": 0, "bad": false}
		var meta = index.get(f, null)
		if typeof(meta) == TYPE_DICTIONARY and int(meta.get("size", -2)) == size:
			s["duration"] = float(meta.get("duration", -1.0))
			s["notes"] = int(meta.get("notes", 0))
			s["bad"] = bool(meta.get("bad", false))
		else:
			scan_queue.append(f)
		songs.append(s)
	cur_index = -1
	for i in songs.size():
		if songs[i]["file"] == keep:
			cur_index = i
	songs_version += 1


func _find_song(file):
	for i in songs.size():
		if songs[i]["file"] == file:
			return i
	return -1


# Reads one file that is not in the index yet (a file that was put in the folder by hand).
func _scan_step():
	var f = scan_queue.pop_front()
	var i = _find_song(f)
	if i < 0:
		return
	var bytes = _read_bytes(LIB_DIR + "/" + f)
	var r = null
	if bytes != null:
		r = MidiFile.new().parse(bytes)
	_note_meta(i, r)


func _note_meta(i, r):
	var s = songs[i]
	if r != null and r["ok"]:
		s["duration"] = r["duration"]
		s["notes"] = r["note_count"]
		s["bad"] = false
	else:
		s["duration"] = 0.0
		s["notes"] = 0
		s["bad"] = true
	index[s["file"]] = {"size": s["size"], "duration": s["duration"], "notes": s["notes"], "bad": s["bad"]}
	index_dirty = true
	save_soon()
	songs_version += 1


func _safe_name(base):
	var out = ""
	for i in base.length():
		var c = base[i]
		if base.ord_at(i) < 32 or c in "\\/:*?\"<>|":
			out += "_"
		else:
			out += c
	out = out.strip_edges()
	while out.ends_with("."):
		out = out.substr(0, out.length() - 1)
	if out == "":
		out = "song"
	if out.length() > 80:
		out = out.substr(0, 80).strip_edges()
	if RESERVED.has(out.split(".")[0].to_upper()):
		out = "_" + out
	return out


func _same_bytes(path, bytes):
	var b = _read_bytes(path)
	return b != null and b == bytes


# Copies the chosen files into the library. Every file is parsed first, so only real MIDI files get in.
# Returns the message that was shown.
func import_paths(paths):
	_ensure_dir()
	var added = 0
	var already = 0
	var bad = []
	var last = ""
	var n = 0
	for path in paths:
		n += 1
		if n > MAX_IMPORT_AT_ONCE:
			bad.append("more than %d files at once" % MAX_IMPORT_AT_ONCE)
			break
		var fname = str(path).get_file()
		if not _is_midi_name(fname):
			bad.append("%s (not a .mid file)" % fname)
			continue
		var bytes = _read_bytes(path)
		if bytes == null:
			bad.append("%s (can't be read, or bigger than 3 MB)" % fname)
			continue
		var r = MidiFile.new().parse(bytes)
		if not r["ok"]:
			bad.append("%s (%s)" % [fname, r["error"]])
			continue
		var base = _safe_name(fname.get_basename())
		var target = base + ".mid"
		var k = 2
		var dup = false
		while File.new().file_exists(LIB_DIR + "/" + target):
			if _same_bytes(LIB_DIR + "/" + target, bytes):
				dup = true
				break
			target = "%s (%d).mid" % [base, k]
			k += 1
			if k > 99:
				break
		if dup:
			already += 1
			last = target
			continue
		if songs.size() + added >= MAX_SONGS:
			bad.append("%s (the list is full: %d songs)" % [fname, MAX_SONGS])
			continue
		if not _write_bytes(LIB_DIR + "/" + target, bytes):
			bad.append("%s (can't be saved)" % fname)
			continue
		index[target] = {"size": bytes.size(), "duration": r["duration"], "notes": r["note_count"], "bad": false}
		index_dirty = true
		added += 1
		last = target
	var parts = []
	if added > 0:
		parts.append("Added %d song%s." % [added, "" if added == 1 else "s"])
	if already > 0:
		parts.append("%d already in the list." % already)
	if not bad.empty():
		parts.append("Not added: " + ", ".join(bad) + ".")
	if parts.empty():
		parts.append("Nothing to add.")
	set_message(" ".join(parts))
	save_soon()
	scan_library()
	if last != "":
		var i = _find_song(last)
		if i >= 0:
			select_song(i, false)
	return message


func _write_bytes(path, bytes):
	var f = File.new()
	var tmp = path + ".tmp"
	if f.open(tmp, File.WRITE) != OK:
		return false
	f.store_buffer(bytes)
	f.close()
	return Directory.new().rename(tmp, path) == OK


func _on_files_dropped(files, _screen):
	if window != null and is_instance_valid(window):
		import_paths(files)


func set_message(text):
	message = text
	message_until = OS.get_ticks_msec() / 1000.0 + MESSAGE_SECONDS


func delete_song(i):
	if i < 0 or i >= songs.size():
		return
	var f = songs[i]["file"]
	if not _is_midi_name(f) or f.find("/") >= 0 or f.find("\\") >= 0:
		return
	var was_cur = (i == cur_index)
	if was_cur:
		player.stop()
		_restore_markers()
	Directory.new().remove(LIB_DIR + "/" + f)
	index.erase(f)
	index_dirty = true
	save_soon()
	if was_cur:
		cur = null
		map = null
		track_on = {}
		player.load_events([], 0.0)
		cur_version += 1
	scan_library()
	set_message("Removed %s." % f.get_basename())


func open_folder():
	_ensure_dir()
	OS.shell_open(ProjectSettings.globalize_path(LIB_DIR))


# ---------- the song ----------

func select_song(i, autoplay):
	if i < 0 or i >= songs.size():
		return
	player.pause()
	_restore_markers()
	cur_index = i
	var s = songs[i]
	var bytes = _read_bytes(LIB_DIR + "/" + s["file"])
	var r = null
	if bytes != null:
		r = MidiFile.new().parse(bytes)
	cur = null
	map = null
	track_on = {}
	if r == null or not r["ok"]:
		_note_meta(i, r)
		player.load_events([], 0.0)
		set_message("%s can't be played%s." % [s["name"], "" if r == null else ": " + r["error"]])
		cur_version += 1
		return
	cur = r
	_note_meta(i, r)
	for t in r["tracks"].size():
		var tr = r["tracks"][t]
		if tr["notes"] > 0 and not tr["drums"]:
			track_on[t] = true
	settings["last_song"] = s["file"]
	save_soon()
	_remap(true)
	if autoplay:
		player.play()


# Builds the strums again after an option changed (keeps the position and whether it is playing).
func _remap(reset):
	if cur == null:
		return
	var was = player.playing
	var t = player.clock
	map = GuitarMap.new().build(cur["notes"], {"tracks": track_on, "semitones": settings["semitones"],
		"auto_octave": settings["auto_octave"], "fold": true})
	player.speed = settings["speed"]
	player.load_events(map["events"], cur["duration"])
	if not reset:
		player.seek(t)
		player.playing = was and player.has_song()
	cur_version += 1


func play_pause():
	if player.playing:
		player.pause()
		_restore_markers()
		return
	if cur == null:
		var i = cur_index
		if i < 0 and not songs.empty():
			i = 0
		if i < 0:
			return
		select_song(i, false)
	player.play()


func stop():
	player.stop()
	_restore_markers()


func seek_fraction(f):
	player.seek(clamp(f, 0.0, 1.0) * player.end_time)


func step_song(dir):
	if songs.size() < 1:
		return
	var was = player.playing
	var i = cur_index
	for k in songs.size():
		i = (i + dir) % songs.size()
		if i < 0:
			i += songs.size()
		if not songs[i]["bad"]:
			select_song(i, was)
			return


func cycle_repeat():
	settings["repeat"] = (int(settings["repeat"]) + 1) % 3
	save_soon()


func set_speed(v):
	settings["speed"] = clamp(stepify(float(v), 0.05), 0.5, 1.5)
	player.speed = settings["speed"]
	save_soon()


func set_semitones(n):
	var v = int(clamp(n, -12, 12))
	if v == settings["semitones"]:
		return
	settings["semitones"] = v
	save_soon()
	_remap(false)


func set_auto_octave(on):
	if bool(on) == bool(settings["auto_octave"]):
		return
	settings["auto_octave"] = bool(on)
	save_soon()
	_remap(false)


func set_track(t, on):
	if on:
		track_on[t] = true
	else:
		track_on.erase(t)
	_remap(false)


func set_all_tracks(on):
	track_on = {}
	if on and cur != null:
		for t in cur["tracks"].size():
			var tr = cur["tracks"][t]
			if tr["notes"] > 0 and not tr["drums"]:
				track_on[t] = true
	_remap(false)


func _on_finished():
	_restore_markers()
	var mode = int(settings["repeat"])
	if mode == 1:
		player.seek(0.0)
		player.play()
	elif mode == 2:
		var before = cur_index
		step_song(1)
		if cur_index == before or cur == null:
			player.seek(0.0)
		player.play()
	cur_version += 1
