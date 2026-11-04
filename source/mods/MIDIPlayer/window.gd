extends Panel

# The MIDI window inside the guitar menu: list of imported songs, Import / Remove, play controls, and a few options.
# It only shows things and passes clicks on to the mod (main.gd) which owns the library, the song and the player.

const WIDTH = 700.0
const REMOVE_CONFIRM = 3.0

var mod = null

var header = null
var title = null
var btn_min = null
var margin = null
var body = null
var list = null
var empty_hint = null
var info = null
var msg = null
var btn_import = null
var btn_remove = null
var btn_folder = null
var btn_play = null
var btn_stop = null
var btn_prev = null
var btn_next = null
var btn_repeat = null
var seek = null
var time_label = null
var speed_slider = null
var speed_label = null
var semi_label = null
var btn_semi_dn = null
var btn_semi_up = null
var chk_octave = null
var chk_keep = null
var btn_tracks_all = null
var btn_tracks_none = null
var tracks_scroll = null
var track_box = null
var dialog = null

var _fade = 0.0
var _drag = false
var _drag_off = Vector2.ZERO
var _seeking = false
var _updating = false
var _songs_v = -1
var _cur_v = -1
var _remove_armed = ""
var _remove_until = 0.0
var _clock = 0.0


func _ready():
	name = "MIDIPlayerWindow"
	theme = load("res://Assets/Themes/main.tres")
	var pm = load("res://Assets/Themes/panel_med.tres")
	if pm != null:
		add_stylebox_override("panel", pm)
	_build()
	modulate.a = 0.0
	rect_position = Vector2(mod.settings["x"], mod.settings["y"])
	_apply_collapsed()
	_refresh(true)


func _label(text):
	var l = Label.new()
	l.text = text
	return l


# A check box without the theme's green button background: it reads as a plain row.
func _plain(cb):
	var e = StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		cb.add_stylebox_override(st, e)
	cb.focus_mode = Control.FOCUS_NONE
	var col = get_color("font_color", "Label")   # the label colour of the panel (the theme's check box text is light)
	cb.add_color_override("font_color", col)
	cb.add_color_override("font_color_hover", col)
	cb.add_color_override("font_color_pressed", col)
	cb.add_color_override("font_color_hover_pressed", col)
	cb.add_color_override("font_color_disabled", Color(col.r, col.g, col.b, 0.55))
	return cb


func _button(text, handler):
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, handler)
	return b


func _build():
	margin = MarginContainer.new()
	margin.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	margin.add_constant_override("margin_left", 22)
	margin.add_constant_override("margin_right", 22)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 18)
	add_child(margin)
	var root = VBoxContainer.new()
	root.add_constant_override("separation", 10)
	margin.add_child(root)

	header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.connect("gui_input", self, "_header_input")
	root.add_child(header)
	title = _label("MIDI Player")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	btn_min = _button("-", "_on_min")
	btn_min.rect_min_size = Vector2(52, 0)
	header.add_child(btn_min)

	body = VBoxContainer.new()
	body.add_constant_override("separation", 10)
	root.add_child(body)

	list = ItemList.new()
	list.rect_min_size = Vector2(0, 220)
	list.allow_reselect = true
	list.connect("item_selected", self, "_on_list_selected")
	list.connect("item_activated", self, "_on_list_activated")
	body.add_child(list)
	empty_hint = _label("")
	empty_hint.autowrap = true
	body.add_child(empty_hint)

	var row1 = HBoxContainer.new()
	row1.add_constant_override("separation", 8)
	body.add_child(row1)
	btn_import = _button("Import...", "_on_import")
	btn_import.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(btn_import)
	btn_remove = _button("Remove", "_on_remove")
	btn_remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(btn_remove)
	btn_folder = _button("Open folder", "_on_folder")
	btn_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(btn_folder)

	info = _label("")
	info.autowrap = true
	info.rect_min_size = Vector2(0, 92)
	body.add_child(info)

	var row2 = HBoxContainer.new()
	row2.add_constant_override("separation", 8)
	body.add_child(row2)
	btn_prev = _button("<<", "_on_prev")
	row2.add_child(btn_prev)
	btn_play = _button("Play", "_on_play")
	btn_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(btn_play)
	btn_stop = _button("Stop", "_on_stop")
	btn_stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(btn_stop)
	btn_next = _button(">>", "_on_next")
	row2.add_child(btn_next)
	btn_repeat = _button("Repeat: off", "_on_repeat")
	btn_repeat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(btn_repeat)

	var row3 = HBoxContainer.new()
	row3.add_constant_override("separation", 10)
	body.add_child(row3)
	seek = HSlider.new()
	seek.min_value = 0.0
	seek.max_value = 1.0
	seek.step = 0.0005
	seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seek.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seek.focus_mode = Control.FOCUS_NONE
	seek.connect("value_changed", self, "_on_seek")
	seek.connect("gui_input", self, "_seek_input")
	row3.add_child(seek)
	time_label = _label("0:00 / 0:00")
	row3.add_child(time_label)

	var row4 = HBoxContainer.new()
	row4.add_constant_override("separation", 10)
	body.add_child(row4)
	row4.add_child(_label("Speed"))
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.5
	speed_slider.max_value = 1.5
	speed_slider.step = 0.05
	speed_slider.value = 1.0
	speed_slider.rect_min_size = Vector2(190, 0)
	speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.connect("value_changed", self, "_on_speed")
	row4.add_child(speed_slider)
	speed_label = _label("100%")
	speed_label.rect_min_size = Vector2(64, 0)
	row4.add_child(speed_label)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_child(sp)
	row4.add_child(_label("Pitch"))
	btn_semi_dn = _button("-", "_on_semi_down")
	btn_semi_dn.rect_min_size = Vector2(44, 0)
	row4.add_child(btn_semi_dn)
	semi_label = _label("0")
	semi_label.rect_min_size = Vector2(40, 0)
	semi_label.align = Label.ALIGN_CENTER
	row4.add_child(semi_label)
	btn_semi_up = _button("+", "_on_semi_up")
	btn_semi_up.rect_min_size = Vector2(44, 0)
	row4.add_child(btn_semi_up)

	chk_octave = _plain(CheckBox.new())
	chk_octave.text = "Fit the song to the guitar's range (shifts octaves)"
	chk_octave.connect("toggled", self, "_on_octave")
	body.add_child(chk_octave)

	chk_keep = _plain(CheckBox.new())
	chk_keep.text = "Keep playing when the menu is closed"
	chk_keep.hint_tooltip = "Close this menu and walk around with the guitar while the song plays. Put the guitar away to stop."
	chk_keep.connect("toggled", self, "_on_keep")
	body.add_child(chk_keep)

	var trow = HBoxContainer.new()
	trow.add_constant_override("separation", 8)
	body.add_child(trow)
	var tl = _label("Tracks to play")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	btn_tracks_all = _button("All", "_on_tracks_all")
	btn_tracks_all.rect_min_size = Vector2(70, 0)
	trow.add_child(btn_tracks_all)
	btn_tracks_none = _button("None", "_on_tracks_none")
	btn_tracks_none.rect_min_size = Vector2(90, 0)
	trow.add_child(btn_tracks_none)
	tracks_scroll = ScrollContainer.new()
	tracks_scroll.rect_min_size = Vector2(0, 130)
	tracks_scroll.scroll_horizontal_enabled = false
	body.add_child(tracks_scroll)
	track_box = VBoxContainer.new()
	track_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracks_scroll.add_child(track_box)

	msg = _label("")
	msg.autowrap = true
	body.add_child(msg)

	dialog = FileDialog.new()
	dialog.mode = FileDialog.MODE_OPEN_FILES
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PoolStringArray(["*.mid, *.midi, *.kar ; MIDI files"])
	dialog.window_title = "Import MIDI files"
	dialog.connect("files_selected", self, "_on_files_chosen")
	dialog.connect("popup_hide", self, "_on_dialog_hidden")
	add_child(dialog)


func _fit():
	var m = margin.get_combined_minimum_size()
	rect_size = Vector2(WIDTH, m.y)
	_clamp_to_screen()


# A saved position from another screen size must not leave the window out of reach.
func _clamp_to_screen():
	var vs = get_viewport_rect().size
	rect_position = Vector2(clamp(rect_position.x, 0.0, max(0.0, vs.x - rect_size.x)),
		clamp(rect_position.y, 0.0, max(0.0, vs.y - 80.0)))


func _apply_collapsed():
	var c = bool(mod.settings["collapsed"])
	body.visible = not c
	btn_min.text = "+" if c else "-"
	call_deferred("_fit")


func _on_min():
	mod.settings["collapsed"] = not bool(mod.settings["collapsed"])
	mod.save_soon()
	_apply_collapsed()


func _header_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_drag = ev.pressed
		_drag_off = get_global_mouse_position() - rect_position
		if not ev.pressed:
			mod.settings["x"] = rect_position.x
			mod.settings["y"] = rect_position.y
			mod.save_soon()
	elif ev is InputEventMouseMotion and _drag:
		var vs = get_viewport_rect().size
		var p = get_global_mouse_position() - _drag_off
		p.x = clamp(p.x, 0.0, max(0.0, vs.x - rect_size.x))
		p.y = clamp(p.y, 0.0, max(0.0, vs.y - 80.0))
		rect_position = p


func _seek_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_seeking = ev.pressed


func _process(delta):
	_clock += delta
	if _fade < 1.0:
		_fade = min(1.0, _fade + delta * 3.0) if _clock > 0.35 else 0.0
		modulate.a = _fade
	if _remove_armed != "" and _clock > _remove_until:
		_remove_armed = ""
		_refresh_buttons()
	_refresh(false)


# Brings every control up to date with the mod (the lists only when they changed).
func _refresh(force):
	if force or _songs_v != mod.songs_version:
		_songs_v = mod.songs_version
		_rebuild_list()
	if force or _cur_v != mod.cur_version:
		_cur_v = mod.cur_version
		_rebuild_tracks()
		_refresh_info()
		_refresh_buttons()
	_updating = true
	var p = mod.player
	var total = p.end_time
	if not _seeking:
		seek.value = (p.clock / total) if total > 0.0 else 0.0
	time_label.text = "%s / %s" % [_fmt(p.clock), _fmt(total)]
	btn_play.text = "Pause" if p.playing else "Play"
	if abs(speed_slider.value - mod.settings["speed"]) > 0.001:
		speed_slider.value = mod.settings["speed"]
	speed_label.text = "%d%%" % int(round(mod.settings["speed"] * 100.0))
	var sm = int(mod.settings["semitones"])
	semi_label.text = ("+%d" % sm) if sm > 0 else str(sm)
	if chk_octave.pressed != bool(mod.settings["auto_octave"]):
		chk_octave.pressed = bool(mod.settings["auto_octave"])
	if chk_keep.pressed != bool(mod.settings["keep_playing"]):
		chk_keep.pressed = bool(mod.settings["keep_playing"])
	btn_repeat.text = ["Repeat: off", "Repeat: song", "Repeat: all"][int(mod.settings["repeat"])]
	_updating = false
	if mod.message != "" and OS.get_ticks_msec() / 1000.0 < mod.message_until:
		msg.text = mod.message
	else:
		msg.text = ""
	seek.editable = p.has_song()
	btn_play.disabled = mod.songs.empty()


func _fmt(sec):
	var s = int(max(0.0, sec))
	return "%d:%02d" % [s / 60, s % 60]


func _song_text(s):
	var d = "..."
	if s["bad"]:
		d = "can't be read"
	elif s["duration"] >= 0.0:
		d = _fmt(s["duration"])
	return "%s   %s" % [s["name"], d]


func _rebuild_list():
	list.clear()
	for s in mod.songs:
		list.add_item(_song_text(s))
		if s["bad"]:
			list.set_item_custom_fg_color(list.get_item_count() - 1, Color(0.6, 0.5, 0.45, 1))
	if mod.cur_index >= 0 and mod.cur_index < list.get_item_count():
		list.select(mod.cur_index)
		list.ensure_current_is_visible()
	empty_hint.visible = mod.songs.empty()
	empty_hint.text = "No songs yet. Click Import, or drop .mid files onto the game window."
	_refresh_buttons()


func _rebuild_tracks():
	for c in track_box.get_children():
		c.queue_free()
		track_box.remove_child(c)
	var cur = mod.cur
	if cur == null:
		return
	var shown = 0
	for i in cur["tracks"].size():
		var t = cur["tracks"][i]
		if t["notes"] == 0:
			continue
		if shown >= 64:
			break
		shown += 1
		var nm = t["name"]
		if nm == "":
			nm = _instrument_name(t["program"])
		var cb = _plain(CheckBox.new())
		if t["drums"]:
			cb.text = "%d  %s  (drums are skipped)" % [i + 1, nm if nm != "" else "Drums"]
			cb.disabled = true
			cb.pressed = false
		else:
			cb.text = "%d  %s  (%d notes)" % [i + 1, nm, t["notes"]]
			cb.pressed = mod.track_on.has(i)
			cb.connect("toggled", self, "_on_track_toggled", [i])
		track_box.add_child(cb)
	tracks_scroll.scroll_vertical = 0


func _instrument_name(program):
	var n = mod.MidiFile.program_name(program)
	return n if n != "" else "Track"


func _refresh_info():
	var lines = []
	var cur = mod.cur
	if cur == null:
		if mod.cur_index >= 0 and mod.cur_index < mod.songs.size():
			lines.append(mod.songs[mod.cur_index]["name"])
			lines.append("This file can't be played.")
		else:
			lines.append("Pick a song from the list, then press Play.")
		info.text = "\n".join(lines)
		return
	var m = mod.map
	lines.append(mod.songs[mod.cur_index]["name"])
	var pct = 0
	if m["total"] > 0:
		pct = int(round(100.0 * m["played"] / m["total"]))
	lines.append("%s  |  %d notes  |  %d played (%d%%)" % [_fmt(cur["duration"]), m["total"], m["played"], pct])
	var extra = []
	if m["octaves"] != 0:
		extra.append("moved %d octave%s %s to fit" % [abs(m["octaves"]), "" if abs(m["octaves"]) == 1 else "s", "up" if m["octaves"] > 0 else "down"])
	if m["folded"] > 0:
		extra.append("%d notes outside the range folded by octaves" % m["folded"])
	if m["out_of_range"] > 0:
		extra.append("%d notes outside the range left out" % m["out_of_range"])
	if m["too_many"] > 0:
		extra.append("%d notes left out (more than 6 at once)" % m["too_many"])
	if m["too_fast"] > 0:
		extra.append("%d notes left out (too fast for the network)" % m["too_fast"])
	if m["total"] == 0:
		extra.append("no tracks selected")
	if not extra.empty():
		lines.append("; ".join(extra))
	info.text = "\n".join(lines)


func _refresh_buttons():
	var has_sel = mod.cur_index >= 0 and mod.cur_index < mod.songs.size()
	btn_remove.disabled = not has_sel
	btn_remove.text = "Sure?" if (_remove_armed != "" and has_sel and _remove_armed == mod.songs[mod.cur_index]["file"]) else "Remove"
	btn_prev.disabled = mod.songs.size() < 2
	btn_next.disabled = mod.songs.size() < 2
	btn_stop.disabled = not mod.player.has_song()


# --- clicks ---

func _on_list_selected(i):
	mod.select_song(i, false)


func _on_list_activated(i):
	mod.select_song(i, true)


func _on_import():
	if dialog.visible:
		return
	var dir = str(mod.settings["last_dir"])
	if dir == "" or not Directory.new().dir_exists(dir):
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir != "":
		dialog.current_dir = dir
	mod.set_keys_blocked(true)
	dialog.popup_centered(Vector2(900, 620))


func _on_files_chosen(paths):
	if paths.size() > 0:
		mod.settings["last_dir"] = str(paths[0]).get_base_dir()
		mod.save_soon()
	mod.import_paths(paths)


func _on_dialog_hidden():
	if dialog.visible:
		return   # popping it up again first hides it: it is still open
	mod.set_keys_blocked(false)


func _on_remove():
	if mod.cur_index < 0 or mod.cur_index >= mod.songs.size():
		return
	var f = mod.songs[mod.cur_index]["file"]
	if _remove_armed == f and _clock <= _remove_until:
		_remove_armed = ""
		mod.delete_song(mod.cur_index)
	else:
		_remove_armed = f
		_remove_until = _clock + REMOVE_CONFIRM
	_refresh_buttons()


func _on_folder():
	mod.open_folder()


func _on_play():
	mod.play_pause()


func _on_stop():
	mod.stop()


func _on_prev():
	mod.step_song(-1)


func _on_next():
	mod.step_song(1)


func _on_repeat():
	mod.cycle_repeat()


func _on_seek(v):
	if not _updating:
		mod.seek_fraction(v)


func _on_speed(v):
	if not _updating:
		mod.set_speed(v)


func _on_semi_down():
	mod.set_semitones(int(mod.settings["semitones"]) - 1)


func _on_semi_up():
	mod.set_semitones(int(mod.settings["semitones"]) + 1)


func _on_octave(on):
	if not _updating:
		mod.set_auto_octave(on)


func _on_keep(on):
	if not _updating:
		mod.set_keep_playing(on)


func _on_track_toggled(on, i):
	mod.set_track(i, on)


func _on_tracks_all():
	mod.set_all_tracks(true)


func _on_tracks_none():
	mod.set_all_tracks(false)
